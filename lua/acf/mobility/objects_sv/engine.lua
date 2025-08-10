local ACF	= ACF
local Meta	= {}
local String	= "Engine [Displacement = %s]"
--local Debug		= ACF.Debug
local Objects	= ACF.Mobility.Objects
--local deg		= math.deg
--local Clamp		= math.Clamp
local max		= math.max
local pi		= math.pi
local DryGasConstant	= 286.9 -- J/kgK

--	Other fuels, just a central spot to find this link
--	https://www.engineeringtoolbox.com/alternative-fuels-d_1221.html
--	https://en.wikipedia.org/wiki/Flash_point
--	https://www.engineeringtoolbox.com/fuels-ignition-temperatures-d_171.html
--	https://www.engineeringtoolbox.com/flash-point-fuels-d_937.html DOUBLE CHECK TEMPERATURE
--

--	https://en.wikipedia.org/wiki/Stoichiometry
--	https://en.wikipedia.org/wiki/Heat_of_combustion
--	https://en.wikipedia.org/wiki/Energy_density

--[[
	Index of expansion
	cP / cV
	Ratio of specific heats of the input gases cP and cV

	cP = Specific heat at a constant Pressure
	cV = Specific heat at a constant Volume

	Using this we get the dry gas constant of air, 286.9J/kgK
]]

--	https://hpwizard.com/engine.html some good reads
--	https://books.google.com/books?id=rvD_kLm180YC&printsec=frontcover#v=onepage&q&f=false more good reads

-- Predetermined patterns for engines?
--[[
	I-shape engines
	Flat engines
	V-shape engines
	W-shape engines
	Radial engines with variable bank count (3-12)

	Separate turbine and electric motor simulation
	Wankel/Rotaries also require a slightly different simulation due to different parts
]]

-- Stick to one fucking unit system (SI)

--[[
	Air-Fuel Ratios

	Gasoline:	14.7 : 1 	- Burns very hot at this, and is usually not actually reached unless under light loads
	Diesel		14.5 : 1	- Burns as it is injected, and usually has an abundance of air making it very lean
]]

--[[

	  <Bore>
	   ____
	S |    | - Clearance volume
	T |[||]|
	R | || | - Displacement
	O | || |
	K | || |
	E | || |


	Since airflow is being roughly calculated, this also opens up the possibility of positive pressure intake (supercharger/turbocharger), as well as exhaust entities with correct flowrates and appearance

]]

function Objects.Engine(EngineData)
	local Engine = {
		Active		= false,
		Clutch		= 0,
		LastThink	= 0,
		Throttle	= 0,

		Bore		= EngineData.Bore or 1,					-- Radius in cm
		Stroke		= EngineData.Stroke or 1,				-- Length in cm (total travel of piston)
		Clearance	= EngineData.Clearance or 1,			-- Length in cm (leftover length at top crank) This determines the compression ratio of the piston
		Banks		= math.max(EngineData.Banks, 1) or 1,	-- Rows of pistons
		Pistons		= EngineData.Pistons or 4,				-- Pistons per bank

		Heat			= 0,	-- Set to ambient temperature on creation? Can be used to directly determine fuel efficiency which can affect torque output, and necessitate radiators
		FlyRPM			= 0,	-- Current RPM of the crankshaft/flywheel
		FlyMass			= EngineData.FlywheelMass,	-- Mass of the flywheel (kg)
		FlyRadius		= EngineData.FlywheelRadius / 100,	-- Radius of the flywheel (input as cm, stored as m for calculations)
		Entity			= NULL	-- Populated on creation
	}

	Engine.Cylinders		= Engine.Banks * Engine.Pistons			-- Number of cylinders in the engine
	Engine.BoreArea			= (Engine.Bore ^ 2) * pi				-- Bore area of a single piston, cm^2
	Engine.TotalBoreArea	= Engine.Cylinders * Engine.BoreArea	-- Total bore area of all pistons, cm^2
	Engine.CylinderVolume	= Engine.Stroke * Engine.BoreArea		-- Volume of a single cylinder, cm^3
	Engine.Displacement		= Engine.Stroke * Engine.TotalBoreArea	-- Total displacement of the engine, cm^3
	Engine.FlyMOI			= 0.5 * Engine.FlyMass * (Engine.FlyRadius ^ 2)	-- Moment of inertia, kg/cm^2
	Engine.ClearanceVolume	= Engine.Clearance * Engine.BoreArea	-- Volume at top-dead-center

	local PistonCircumference	= Engine.Bore * 2 * pi				-- Perimeter of piston
	Engine.PistonWallArea	= PistonCircumference * Engine.Stroke * 0.125	-- vertical """size""" of a piston as area, used for friction estimation

	Engine.CompressionRatio	= Engine.CylinderVolume / Engine.ClearanceVolume

	Engine.IntakeVolume		= Engine.Displacement * 0.75			-- Really crude way to do this, but I need *something* without yet another user variable

	Engine.CRotPerCycle		= 2 -- 2 rotations per cycle for 4-stroke

	setmetatable(Engine, Meta)

	return Engine
end

AccessorFunc(Meta, "Entity", "Entity")
AccessorFunc(Meta, "Active", "Active", FORCE_BOOL)
AccessorFunc(Meta, "Clutch", "Clutch", FORCE_NUMBER)
AccessorFunc(Meta, "Throttle", "Throttle", FORCE_NUMBER)
AccessorFunc(Meta, "LastThink", "LastThink", FORCE_NUMBER)

--	Energy density of the fuel used in the engine
--	This is NOT all applied, some of this energy is lost due to inefficiency (heating cylinder walls, piston head, etc) instead of heating the gas
--	https://en.wikipedia.org/wiki/Air%E2%80%93fuel_ratio
--	https://en.wikipedia.org/wiki/Stoichiometry#Stoichiometric_air-to-fuel_ratios_of_common_fuels
function Meta:FuelEnergy()
	return 0
end

function Meta:ConsumeFuel(Intake)
	-- To be done alongside air/fuel ratio calculations, actually draw fuel with this function and return an amount pulled, to be fed to AFR formula

	return (Intake.PeakAirFlow / 14.7) * self.Throttle -- just something for now, this will be dynamic later
end

--
--	https://web.archive.org/web/20070206060439/http://www.tech.plym.ac.uk/sme/ther305-web/Combust1.PDF
--	https://x-engineer.org/fuel-conversion-efficiency/
--	https://x-engineer.org/air-fuel-ratio/

-- Don't forget to factor in flamewall speeds, it can take different times to completely burn depending on bore radius and intake velocity (also spark advance, but we're not simulating that)
-- https://www.cycleworld.com/story/blogs/ask-kevin/accelerating-combustion-increase-motorcycle-engine-power/
-- https://www.speed-talk.com/forum/viewtopic.php?t=3652 Bunch of old farts talking about squish/turbulence/etc

function Meta:Combust(Intake)
	local FuelMass	= self:ConsumeFuel(Intake)
	local AirMass	= Intake.MassAirFlow

	local AFR		= AirMass / FuelMass
	local FuelStoich	= 14.7

	return {
		Energy	= self:FuelEnergy() * FuelMass * math.max(AFR / FuelStoich, 1)
	}
end


-- To be made dynamic, for purposes of boosting
-- Can also be an entry point for infmaps with atmosphere thinning from altitude
-- Temperature can also be dynamic by map, but will need a system for saving info like that per-map
local AirPressure	= 99 -- kPa
local AirTemp		= 21.1 -- Celsis

-- https://x-engineer.org/calculate-volumetric-efficiency/
function Meta:DoIntake()
	local Pressure		= AirPressure * self:GetThrottle()

	-- Adjust AirTemp by engine temperature slightly (as the intake manifold gets hot too)
	local AirDensity	= (Pressure * 1000) / (DryGasConstant * (AirTemp + 273.15))	-- kg/m^3
	local RPS			= self:RPM() / 60

	-- ya, sue me, I need a way to approximate this somehow
	local Intake		= self.IntakeVolume * self.Throttle
	local AirMass		= AirDensity * Intake
	local PeakAirMass	= AirDensity * self.IntakeVolume
	local MassAirFlow	= (AirMass * RPS) / self.CRotPerCycle
	local PeakAirFlow	= (PeakAirMass * RPS) / self.CRotPerCycle

	local Efficiency	= (MassAirFlow * self.CRotPerCycle) / (AirDensity * (self.Displacement * 1e-6) * RPS)

	return {
		MassAirFlow = MassAirFlow,			-- kg/s Air flow
		PeakAirFlow = PeakAirFlow,			-- kg/s Peak air flow (for load calculation)
		Density = AirDensity,				-- kg/m^3 Density of air in intake
		Pressure = Pressure,				-- kPa of air in intake
		VolumetricEfficiency = Efficiency	-- percentage of how much air is actually making it through the engine compared to the peak flow at standard temperature/pressure
	}
end

function Meta:MeanPistonSpeed() -- Piston speed, m/s
	return 2 * (self.Stroke / 100) * (self:RPM() / 60)
end

-- TODO: Actually finish energy release from fuel combustion (with efficiency loss)

function Meta:IndicatedMeanEffectivePressure(Intake)
	return Intake.Pressure * self.CylinderVolume / self.ClearanceVolume
end

function Meta:PeakCylinderPressure(Intake) -- Should be during/post-combustion pressure, after air in the piston has been heated up by fuel
	local Combustion	= self:Combust()

	return self:IndicatedMeanEffectivePressure(Intake)
end

function Meta:FrictionMeanEffectivePressure()
	-- https://www.sciencedirect.com/science/article/pii/S2214157X21007875
	-- https://x-engineer.org/mechanical-efficiency-friction-mean-effective-pressure-fmep/
	-- https://www.mdpi.com/1999-4893/18/7/415

	-- Too goddamn many articles behind a paywall
	-- Also as seeing way too much of this relies on measured data, we have to make do with *something*
	-- Chen-Flynn friction correlation model

	-- This is an approximation of one the "parasitic" forces in an engine, to help self-balance

	local Speed		= self:RadS() -- Engine speed in rad/s
	local Factor	= (Speed * (self.Stroke / 100)) / 2 -- Engine speed factor
	local PMax		= self:PeakCylinderPressure() -- Peak cylinder pressure (85bar for example)

	-- Constants
	-- All of this is usually based on real values, but I don't have much for that, so I have to make do with what I have, and align it close to said real values
	local A			= 0.4		-- Accessory draw, in bar (constant)
	local B			= 0.005		-- Factor for load effect (in-cylinder pressure)
	-- Can possibly be based on surface area of the round side of the pistons?
	local C			= 0.08		-- Engine speed effect (bar*s/m)	Hydrodynamic friction
	local D			= 0.0012	-- Engine speed effect (bar*s^2/m^2)	Oil windage (quadratic)

	-- Returns (MPa) friction pressure (originally bar)
	return (A + (B * PMax + C * Factor + D * Factor^2)) / 10 -- /10 turns bar to MPa
end

function Meta:BrakeMeanEffectivePressure(Intake) -- Not *technically* correct to do, but its in a game, we have to approximate somewhere
	return self:IndicatedMeanEffectivePressure(Intake) - self:FrictionMeanEffectivePressure()
end

function Meta:Load(Intake)
	return Intake.MassAirFlow / Intake.PeakAirFlow
end

function Meta:RPM()
	return max(self.FlyRPM, 1)
end

function Meta:RadS()
	return (pi * self:RPM()) / 30
end

function Meta:FlyEnergy()	-- Current energy of the flywheel (using solid cylinder)
	return 0.5 * self.FlyMOI * self:RadS()
end

-- A gross approximation of power, being used with our approximation of BMEP (which in itself is an approximation of friction losses versus IMEP, which too is an approximation. We love approximation here.)
function Meta:Power()
	local i		= 0.5 -- Cycles per revolution
	local Vd	= self.Displacement	-- Displacement
	local n		= self:RPM() / 60 -- Revs per second
	local Pme	= self:BrakeMeanEffectivePressure() / 1000

	--print(i, Vd, n, Pme)

	-- https://en.wikipedia.org/wiki/Mean_effective_pressure
	-- Returns in kW
	return (i * Vd * n * Pme) / 1000
end

function Meta:Torque()
	return 9548.8 * self:Power() / max(self:RPM(), 1)
end

function Meta:Run()
	if self:GetActive() == false then return end

	local Intake	= self:DoIntake()


end

-- Also figure out rolling resistances? These may not mix well but we'll see
-- https://www.webtec.com/education/tractive-effort/#  Figuring out tractive effort would actually be absolutely perfect for auto-tread style mobility

function Meta:Transfer() -- Negative torque slows down engine, positive torque speeds up engine?

end

function Meta:ToString()
	return String:format(math.Round(self.Displacement / 1000, 1))
end

Meta.__index	= Meta
Meta.__tostring	= Meta.ToString

--[[
local Engine = Objects.Engine({
	Bore = 9.4 / 2,
	Stroke = 9.5,
	Banks = 2,
	Pistons = 3
})

print("ENGINE")
print(math.ceil(Engine.Displacement / 10) / 100 .. "L Engine")

for i = 1, 8, 1 do
	Engine.FlyRPM = i * 1000

	print("RPM: " .. Engine.FlyRPM, Engine:Power() .. " kW", Engine:Torque() .. " Nm")
end
]]
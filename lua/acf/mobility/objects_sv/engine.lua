local ACF	= ACF
local Meta	= {}
local String	= "Engine [Displacement = %s]"
--local Debug		= ACF.Debug
local Objects	= ACF.Mobility.Objects
local deg		= math.deg
local Clamp		= math.Clamp
local pi		= math.pi
local DryGasConstant	= 286.9 -- J/kgK

--	https://hpwizard.com/engine.html some good reads

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

function Objects.Engine(EngineData)
	local Engine = {
		Active		= false,
		Clutch		= 0,
		LastThink	= 0,
		Throttle	= 0,

		Bore		= EngineData.Bore or 1,		-- Radius in cm
		Stroke		= EngineData.Stroke or 1,	-- Length in cm
		Banks		= math.max(EngineData.Banks, 1) or 1,	-- Rows of pistons
		Pistons		= EngineData.Pistons or 4,	-- Pistons per bank

		Heat			= 0,	-- Set to ambient temperature on creation? Can be used to directly determine fuel efficiency which can affect torque output, and necessitate radiators
		FlyRPM			= 0,
		FlywheelMass	= 0,
		Entity			= NULL	-- Populated on creation
	}

	Engine.Cylinders		= Engine.Banks * Engine.Pistons			-- Number of cylinders in the engine
	Engine.BoreArea			= (Engine.Bore ^ 2) * pi				-- Bore area of a single piston, cm^2
	Engine.TotalBoreArea	= Engine.Cylinders * Engine.BoreArea	-- Total bore area of all pistons, cm^2
	Engine.CylinderVolume	= Engine.Stroke * Engine.BoreArea		-- Volume of a single cylinder, cm^3
	Engine.Displacement		= Engine.Stroke * Engine.TotalBoreArea	-- Total displacement of the engine, cm^3

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

-- Energy density of the fuel used in the engine
-- This is NOT all applied, some of this energy is lost due to inefficiency (heating cylinder walls, piston head, etc) instead of heating the gas
function Meta:FuelEnergy()
	return 0
end

function Meta:ConsumeFuel()
	-- To be done alongside air/fuel ratio calculations, actually draw fuel with this function and return an amount pulled, to be fed to AFR formula
end


-- To be made dynamic, for purposes of boosting
-- Can also be an entry point for infmaps with atmosphere thinning from altitude
-- Temperature can also be dynamic by map,
local AirPressure	= 99 -- kPa
local AirTemp		= 21.1 -- Celsis

-- https://x-engineer.org/calculate-volumetric-efficiency/
function Meta:DoIntake()
	local Pressure		= AirPressure * self:GetThrottle()

	local AirDensity	= (Pressure * 1000) / (DryGasConstant * (AirTemp + 273.15))	-- kg/m^3
	local RPS			= self:RPM() / 60

	-- ya, sue me, I need a way to approximate this somehow
	local AirMass		= AirDensity * self.IntakeVolume
	local MassAirFlow	= (AirMass * RPS) / self.CRotPerCycle

	local Efficiency	= (MassAirFlow * self.CRotPerCycle) / (AirDensity * (self.Displacement * 1e-6) * RPS)

	return {
		MassAirFlow = MassAirFlow,			-- kg/s Air flow
		Density = AirDensity,				-- kg/m^3 Density of air in intake
		Pressure = Pressure,				-- kPa of air in intake
		VolumetricEfficiency = Efficiency	-- 0-1 of how much air is actually making it through the engine
	}
end

function Meta:CompressionRatio()
	return 13 -- Make adjustable/change based on fuel type? Can greatly affect everything else
end

function Meta:MeanPistonSpeed() -- Piston speed, m/s
	return 2 * (self.Stroke / 100) * (self:RPM() / 60)
end

-- TODO: Actually finish energy release from fuel combustion (with efficiency loss)

function Meta:PeakCylinderPressure() -- Should be during/post-combustion pressure, after air in the piston has been heated up by fuel

end

function Meta:IndicatedMeanEffectivePressure()
	local Intake	= self:DoIntake()
	local BDCVolume	= pi * self.Stroke * (self.Bore ^ 2)
	local TDCVolume = pi * (self.Stroke / self:CompressionRatio()) * (self.Bore ^ 2) -- I realize now this is slightly wrong

	return Intake.Pressure * BDCVolume / TDCVolume
end

function Meta:FrictionMeanEffectivePressure()
	-- https://x-engineer.org/mechanical-efficiency-friction-mean-effective-pressure-fmep/
	-- Too goddamn many articles behind a paywall
	-- Also as seeing way too much of this relies on measured data, we have to make do with *something*
	-- Chen-Flynn friction correlation model

	local Speed		= self:RPM() * (pi / 30) -- Engine speed in rad/s
	local Factor	= (Speed * (self.Stroke / 100)) / 2 -- Engine speed factor
	local PMax		= self:PeakCylinderPressure() -- Peak cylinder pressure

	-- Constants
	-- All of this is usually based on real values, but I don't have much for that, so I have to make do with what I have, and align it close to said real values
	local A			= (self.Banks * self.Pistons * 0.05) + 0.08	-- Accessory draw, in bar
	local B			= 0	-- Factor for load effect (in-cylinder pressure)
	-- Can possibly be based on surface area of the round side of the pistons?
	local C			= 0	-- Engine speed effect (bar*s/m)
	local D			= 0	-- Engine speed effect (bar*s^2/m^2)

	-- Returns (MPa) friction pressure (originally bar)
	return (A + B * PMax + C * Factor + D * Factor^2) / 10 -- /10 turns bar to MPa
end

function Meta:MeanEffectivePressure()
	return self:IndicatedMeanEffectivePressure() - self:FrictionMeanEffectivePressure()
end

function Meta:RPM()
	return math.max(self.FlyRPM, 1)
end

function Meta:Power()
	local i		= 0.5 -- Cycles per revolution
	local Vd	= self.Displacement	-- Displacement
	local n		= self:RPM() / 60 -- Revs per second
	local Pme	= self:MeanEffectivePressure() / 1000

	--print(i, Vd, n, Pme)

	-- https://en.wikipedia.org/wiki/Mean_effective_pressure
	-- Returns in kW
	return (i * Vd * n * Pme) / 1000
end

function Meta:Torque()
	return 9548.8 * self:Power() / self:RPM()
end

function Meta:Run(SelfTbl)
	if self:GetActive() == false then return end

	local SelfTbl = SelfTbl or self:GetTable()
end

function Meta:Transfer(Torque) -- Negative torque slows down engine, positive torque speeds up engine?

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
local ACF = ACF
local Turrets = ACF.Classes.Turrets
local InchToMm = ACF.InchToMm

--[[
	For the purposes of calculations and customization, all turrets are considered to be gear-driven

	https://www.balnex.pl/uploads/file/download/ksiazka-techniczna-lozyska-wiencowe.pdf - Has info on slewing rings and applying power to them, pg 16-17

	https://qcbslewingrings.com/product-category/geared-motors/ - Has more PDFs, including the hydraulic one below
	https://qcbslewingrings.com/wp-content/uploads/2021/01/E1-SPOOLVALVE.pdf - Has info on hydraulic motors
]]

Turrets.Register("1-Turret",{
	Name		= "Turrets",
	Description	= "The turret drives themselves.\nThese have a fallback handcrank that is used automatically if no motor is available.",
	Entity		= "acf_turret",
	CreateMenu	= ACF.CreateTurretMenu,
	LimitConVar	= {
		Name	= "_acf_turret",
		Amount	= 20,
		Text	= "Maximum number of ACF turrets a player can create."
	},
	GetMass		= function(Data, Size)
		return math.Round(math.max(Data.Mass * (Size / Data.Size.Base),5), 1)
	end,
	GetTeethCount	= function(Data, Size)
		local SizePerc = (Size - Data.Size.Min) / (Data.Size.Max - Data.Size.Min)
		return math.Round((Data.Teeth.Min * (1 - SizePerc)) + (Data.Teeth.Max * SizePerc))
	end,
	GetRingHeight	= function(TurretData,Size)
		local RingHeight = math.max(Size * TurretData.Ratio,4)

		if (TurretData.Type == "Turret-H") and (Size < 12) then
			return 12 -- sticc
		end

		return RingHeight
	end,

	HandGear	= { -- Fallback incase a motor is unavailable
		Teeth	= 16, -- For use in calculating end effective speed of a turret
		Speed	= 180, -- deg/s
		Torque	= 14, -- 0.1m * 140N * sin(90), torque to turn a small handwheel 90 degrees with slightly more than recommended force for a human
		Efficiency	= 0.99, -- Gearbox efficiency, won't be too punishing for handcrank
		Accel	= 0.5,
		Sound	= "acf_extra/turret/cannon_turn_loop_manual.wav",
	},

	--[[
		TurretData should include:
			- TotalMass	: All of the mass (kg) on the turret
			- LocalCoM	: Local vector (gmu) of center of mass
			- RingSize	: Diameter of ring (gmu)
			- RingHeight: Height of ring (gmu)
			- Teeth		: Number of teeth of the turret ring

		PowerData should include: (look at HandGear above for example, that can be directly fed to this function)
			- Teeth		: Number of teeth of gear on input source
			- Speed		: Maximum speed of input source (deg/s)
			- Torque	: Maximum torque of input source (Nm)
			- Efficiency: Efficiency of the gearbox
			- Accel		: Time, in seconds, to reach Speed
	]]

	CalcSpeed	= function(TurretData, PowerData) -- Called whenever something on the turret changes, returns resistance from mass on the ring (overall, not inertial)
		local Teeth		= TurretData.Teeth
		local GearRatio	= PowerData.Teeth / Teeth
		local TopSpeed	= GearRatio * (PowerData.Speed / 6) -- Converting deg/s to RPM, and adjusting by gear ratio
		local MaxPower	= ((PowerData.Torque / GearRatio) * TopSpeed) / (9550 * PowerData.Efficiency)
		local Diameter	= (TurretData.RingSize * InchToMm) -- Used for some of the formulas from the referenced page, needs to be in mm
		local CoMDistance	= (TurretData.LocalCoM * Vector(1,1,0)):Length() * (InchToMm / 1000) -- (Lateral) Distance of center of mass from center of axis, in meters for calculation
		local OffBaseDistance	= math.max(CoMDistance - math.max(CoMDistance - (Diameter / 2),0),0)

		-- Slewing ring friction moment caused by load (kNm)
		-- 1kg weight (mass * gravity) is about 9.81N
		-- 0.006 = fric coefficient for ball slewing rings
		-- k = 4.4 = coefficient of load accommodation for ball slewing rings
		local Weight	= (TurretData.TotalMass * 9.81) / 1000
		local Mz		= 0 -- Nm resistance to torque

		if TurretData.TurretClass == "Turret-H" then
			Mk		= Weight * OffBaseDistance -- Sum of tilting moments (kNm) (off balance load)
			Fa		= Weight * math.Clamp(1 - (CoMDistance * 2),0,1) -- Sum of axial dynamic forces (kN) (on balance load)
			Mz		= 0.006 * 4.4 * (((Mk * 1000) / Diameter) +  (Fa / 4.4)) * (Diameter / 2000)
		else
			local ZDist = TurretData.LocalCoM.z * (InchToMm / 1000)

			OffBaseDistance	= math.max(ZDist - math.max(ZDist - ((TurretData.RingHeight * InchToMm) / 2),0),0)
			Mk		= Weight * OffBaseDistance -- Sum of tilting moments (kNm) (off balance load)
			Fr		= Weight * math.Clamp(1 - (CoMDistance * 2),0,1) -- Sum of radial dynamic forces (kN), included for vertical turret drives
			Mz		= 0.006 * 4.4 * (((Mk * 1000) / Diameter) + (Fr / 2)) * (Diameter / 2000)
		end

		-- 9.55 is 1 rad/s to RPM
		-- Required power to rotate at full speed
		-- With this we can lower maximum attainable speed
		local ReqConstantPower	= (Mz * TopSpeed) / (9.55 * PowerData.Efficiency)

		if (math.max(1,ReqConstantPower) / math.max(MaxPower,1)) > 1 then return {SlewAccel = 0, MaxSlewRate = 0} end -- Too heavy to rotate, so we'll just stop here

		local FinalTopSpeed = TopSpeed * math.min(1,MaxPower / ReqConstantPower) * 6 -- converting back to deg/s

		-- Moment from acceleration of rotating mass (kNm)
		local RotInertia	= 0.01 * TurretData.TotalMass * (CoMDistance ^ 2)
		local LoadInertia	= RotInertia * (1 / ((1 / GearRatio) ^ 2))
		local Accel 	= (3.1415 * FinalTopSpeed) / (30 * PowerData.Accel)
		local Mg 		= LoadInertia * Accel

		-- 9.55 is 1 rad/s to RPM
		local ReqAccelPower	= ((Mg + Mz) * Accel) / (9.55 * PowerData.Efficiency)

		if (math.max(1,ReqAccelPower) / math.max(1,Accel)) > 4 then return {SlewAccel = 0, MaxSlewRate = 0} end -- Too heavy to accelerate, so we'll just stop here

		local FinalAccel	= Accel * math.Clamp(MaxPower / ReqAccelPower,0,1) * 6 -- converting back to deg/s^2

		return {SlewAccel = FinalAccel, MaxSlewRate = FinalTopSpeed}
	end
})

do	-- Horizontal turret component
	Turrets.RegisterItem("Turret-H","1-Turret",{
		Name			= "Horizontal Turret",
		Description		= "The large stable base of a turret.",
		Model			= "models/props_phx/construct/metal_plate_curve360.mdl",
		ModelSmall		= "models/holograms/hq_cylinder.mdl", -- To be used for diameters < 12u, for RWS or other small turrets
		Mass			= 200, -- At default size, this is the mass of the turret ring. Will scale up/down with diameter difference

		Size = {
			Base		= 60,	-- The default size for the menu
			Min			= 2,	-- To accomodate itty bitty RWS turrets
			Max			= 512,	-- To accomodate ship turrets
			Ratio		= 0.05	-- Height modifier for total size
		},

		Teeth			= {		-- Used to give a final teeth count with size
			Min			= 12,
			Max			= 3072
		},

		MassLimit = {
			Min			= 50,		-- Max amount of mass this component can support at minimum size
			Max			= 80000		-- Max amount of mass th is component can support at maximum size
		},

		Armor			= {
			Min			= 5,
			Max			= 175
		},

		SetupInputs		= function(_,List)
			local Count = #List

			List[Count + 1] = "Bearing (Local degrees from home angle)"
		end
	})
end

do	-- Vertical turret component
	Turrets.RegisterItem("Turret-V","1-Turret",{
		Name			= "Vertical Turret",
		Description		= "The smaller part of a turret, usually has the weapon directly attached to it.\nCan be naturally stabilized up to 25% if there is no motor attached, but the mass must be balanced.",
		Model			= "models/holograms/hq_cylinder.mdl",
		Mass			= 100, -- At default size, this is the mass of the turret ring. Will scale up/down with diameter difference

		Size = {
			Base		= 12,	-- The default size for the menu
			Min			= 1,	-- To accomodate itty bitty RWS turrets
			Max			= 36,	-- To accomodate ship turrets
			Ratio		= 1.5	-- Height modifier for total size
		},

		Teeth			= {		-- Used to give a final teeth count with size
			Min			= 8,
			Max			= 288
		},

		MassLimit = {
			Min			= 20,		-- Max amount of mass this component can support at minimum size
			Max			= 40000		-- Max amount of mass th is component can support at maximum size
		},

		Armor			= {
			Min			= 5,
			Max			= 175
		},

		SetupInputs		= function(_,List)
			local Count	= #List

			List[Count + 1] = "Elevation (Local degrees from home angle)"
		end
	})
end
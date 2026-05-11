local FuelTypes = ACF.Classes.FuelTypes

-- 85% ethanol with remainder 15% gasoline
-- ethanol autoignition 363C flashpoint 63C

FuelTypes.Register("E85", {
	Name			= "Gasahol E85",

	Density			= 0.779,	-- kg/L
	SpecificEnergy	= 33.1,		-- MJ/kg
	Stoichiometric	= 14.7,		-- Air to fuel ratio (value / fuel)
	FlashPoint		= 8.0,		-- Temperature (C) at which ignitable vapors come off the fluid
	AutoIgnition	= 350.0,	-- Temperature (C) at which it combusts without an ignition source
})

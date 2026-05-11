local FuelTypes = ACF.Classes.FuelTypes


FuelTypes.Register("Diesel", {
	Name			= "Diesel Fuel",

	Density			= 0.832,	-- kg/L
	SpecificEnergy	= 45.6,		-- MJ/kg
	Stoichiometric	= 14.5,		-- Air to fuel ratio (value / fuel)
	FlashPoint		= 52.0,		-- Temperature (C) at which ignitable vapors come off the fluid
	AutoIgnition	= 210.0,	-- Temperature (C) at which it combusts without an ignition source
})

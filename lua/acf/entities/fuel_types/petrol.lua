local FuelTypes = ACF.Classes.FuelTypes


FuelTypes.Register("Petrol", {
	Name			= "Petrol Fuel",

	Density			= 0.755,	-- kg/L
	SpecificEnergy	= 46.4,		-- MJ/kg
	Stoichiometric	= 14.7,		-- Air to fuel ratio (value / fuel)
	FlashPoint		= -45.0,	-- Temperature (C) at which ignitable vapors come off the fluid
	AutoIgnition	= 280.0,	-- Temperature (C) at which it combusts without an ignition source
})

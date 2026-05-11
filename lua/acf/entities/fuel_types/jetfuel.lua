local FuelTypes = ACF.Classes.FuelTypes

--	https://en.wikipedia.org/wiki/Jet_fuel	JP-8 is a militarized version of Jet A-1, with some other additives


FuelTypes.Register("JP-8", {
	Name			= "Jet Propellant 8",

	Density			= 0.840,	-- kg/L
	SpecificEnergy	= 46.4,		-- MJ/kg
	Stoichiometric	= 14.5,		-- Air to fuel ratio (value / fuel).
	FlashPoint		= 38.0,		-- Temperature (C) at which ignitable vapors come off the fluid
	AutoIgnition	= 210.0,	-- Temperature (C) at which it combusts without an ignition source
})

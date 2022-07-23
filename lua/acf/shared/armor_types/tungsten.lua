local Armor = ACF.RegisterArmorType("Tungsten", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Tungsten"
	self.Density     = 19.25 -- g/cm3
	self.Tensile     = 980
	self.Yield		 = 750
	self.Description = "Very heavy, very expensive, but can hold its own, provided you can hold it."
end

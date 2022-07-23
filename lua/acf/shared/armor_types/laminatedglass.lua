local Armor = ACF.RegisterArmorType("Laminated Glass", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Laminated Glass"
	self.Density     = 2.48 -- g/cm3
	self.Tensile     = 20
	self.Yield		 = 18
	self.Description = "Supposedly transparent."
end

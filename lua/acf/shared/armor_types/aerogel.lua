local Armor = ACF.RegisterArmorType("Aerogel", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Silica Aerogel"
	self.Density     = 0.1 -- g/cm3
	self.Tensile     = 0.01
	self.Yield		 = 0.01
	self.Description = "It's.... air, but not."
	self.Hide		 = true
end

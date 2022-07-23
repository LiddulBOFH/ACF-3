local Armor = ACF.RegisterArmorType("Neutrons", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Neutrons"
	self.Density     = 2.3 * 10^14 -- g/cm3
	self.Tensile     = 200
	self.Yield		 = 50
	self.Description = "Yeah, good luck with that."
	self.Hide		 = true -- Makes the material NOT show up in any menus
end

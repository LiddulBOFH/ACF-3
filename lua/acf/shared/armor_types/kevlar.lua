-- https://www.alternatewars.com/BBOW/Ballistics/Term/Armor_Material.htm

local Armor = ACF.RegisterArmorType("Kevlar", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Kevlar 29"
	self.Density     = 1.44 -- g/cm3
	self.Tensile     = 2920
	self.Yield		 = 2500
	self.Description = "Extremely lightweight and very resilient."
end

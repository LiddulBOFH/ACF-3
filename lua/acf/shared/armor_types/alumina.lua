-- https://www.alternatewars.com/BBOW/Ballistics/Term/Armor_Material.htm

local Armor = ACF.RegisterArmorType("Alumina", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Alumina AD-90"
	self.Density     = 3.6 -- g/cm3
	self.Tensile     = 221
	self.Yield		 = 200
	self.Description = "Heavier than aluminum and more prone to shattering."
end

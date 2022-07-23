-- https://www.alternatewars.com/BBOW/Ballistics/Term/Armor_Material.htm

local Armor = ACF.RegisterArmorType("Titanium", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Titanium ATSM Grade 38"
	self.Density     = 4.48 -- g/cm3
	self.Tensile     = 1140
	self.Yield		 = 1020
	self.Description = "Lighter than RHA, and almost as strong."
end

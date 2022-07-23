-- https://www.alternatewars.com/BBOW/Ballistics/Term/Armor_Material.htm

local Armor = ACF.RegisterArmorType("DepletedUranium", "RHA")

function Armor:OnLoaded()
	self.Name		 = "Depleted Uranium"
	self.Density     = 18.5 -- g/cm3
	self.Tensile     = 1565
	self.Yield		 = 965
	self.Description = "The glowy armor of choice."
end

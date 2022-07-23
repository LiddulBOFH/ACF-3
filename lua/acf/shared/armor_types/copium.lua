local Armor = ACF.RegisterArmorType("Copium", "RHA")

function Armor:OnLoaded()
	self.Name			= "Copium"
	self.Density		= 200 -- g/cm3
	self.Tensile		= 50
	self.Yield			= 5
	self.Description	= "The purest form of it, compressed into workable material."
	self.Hide		 	= true
end

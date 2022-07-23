-- http://k-mac-plastics.com/data-sheets/hdpe.htm

local Armor = ACF.RegisterArmorType("HDPE", "RHA")

function Armor:OnLoaded()
	self.Name		 = "HDPE"
	self.Density     = 0.948 -- g/cm3
	self.Tensile     = 30
	self.Yield		 = 21.9
	self.Description = "Extremely lightweight."
end

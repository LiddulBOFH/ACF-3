local ACF     = ACF
local Objects = ACF.TempDamage.Objects
local Meta    = {}

--- Creates a new DamageResult object with all its fields set to default values.
-- @return The new DamageResult object.
function Objects.DamageResult()
	local Object = {
		Area        = 1,
		Penetration = 1,
		Thickness   = 1,
		Angle       = 0,
		Factor      = 1,
	}

	setmetatable(Object, Meta)

	return Object
end

--- Generates the damage result table based on the values stored on the object.
-- @return The damage result table, contains the Damage, Overkill, Loss and Kill fields.
function Meta:Compute()
	local Effective   = self.Thickness / math.abs(math.cos(math.rad(self.Angle)) ^ self.Factor)
	local Penetration = self.Penetration
	local Ratio       = math.min(1, Penetration / Effective)

	return {
		Damage   = self.Area * Ratio * Ratio, -- <=== old - new  ===> Area * math.min(Penetration, Effective) * 10,
		Overkill = math.max(0, Penetration - Effective),
		Loss     = math.min(1, Effective / Penetration),
		Kill     = false,
	}
end

--- Returns a blank damage result table with all its values set to zero (false for Kill).
-- @return The blank damage result table.
function Meta:GetBlank()
	return {
		Damage   = 0,
		Overkill = 0,
		Loss     = 0,
		Kill     = false,
	}
end

AccessorFunc(Meta, "Area", "Area", FORCE_NUMBER) -- cm2
AccessorFunc(Meta, "Penetration", "Penetration", FORCE_NUMBER) -- mm
AccessorFunc(Meta, "Thickness", "Thickness", FORCE_NUMBER) -- mm
AccessorFunc(Meta, "Angle", "Angle", FORCE_NUMBER) -- degrees
AccessorFunc(Meta, "Factor", "Factor", FORCE_NUMBER) -- thickness / caliber

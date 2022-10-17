AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

local ACF = ACF

do -- Spawning and Updating
	local Classes  = ACF.Classes
	local Armors   = Classes.ArmorTypes
	local Entities = Classes.Entities

	local function VerifyData(Data)
		if not isstring(Data.ArmorType) then
			Data.ArmorType = "RHA"
		end

		local Armor = Armors.Get(Data.ArmorType)

		if not Armor then
			Data.ArmorType = RHA

			Armor = Armors.Get("RHA")
		end

		do -- Verifying dimension values
			if not isnumber(Data.Width) then
				Data.Width = ACF.CheckNumber(Data.PlateSizeX, 24)
			end

			if not isnumber(Data.Height) then
				Data.Height = ACF.CheckNumber(Data.PlateSizeY, 24)
			end

			if not isnumber(Data.Thickness) then
				Data.Thickness = ACF.CheckNumber(Data.PlateSizeZ, 5)
			end

			Data.Width  = math.Clamp(Data.Width, 0.25, 420)
			Data.Height = math.Clamp(Data.Height, 0.25, 420)

			local MaxPossible = 50000 / (Data.Width * Data.Height * Armor.Density * ACF.gCmToKgIn) * ACF.InchToMm
			local MaxAllowed  = math.min(ACF.MaximumArmor, ACF.GetServerNumber("MaxThickness"))

			Data.Thickness = math.min(Data.Thickness, MaxPossible)
			Data.Size      = Vector(Data.Width, Data.Height, math.Clamp(Data.Thickness, ACF.MinimumArmor, MaxAllowed) * ACF.MmToInch)
		end

		do -- External verifications
			if Armor.VerifyData then
				Armor:VerifyData(Data)
			end

			hook.Run("ACF_VerifyData", "acf_armor", Data, Armor)
		end
	end

	local function UpdatePlate(Entity, Data, Armor)
		local Size = Data.Size

		Entity.ACF.Density = Armor.Density

		Entity:SetNW2String("ArmorType", Armor.ID)
		Entity:SetSize(Size)

		-- Storing all the relevant information on the entity for duping
		for _, V in ipairs(Entity.DataStore) do
			Entity[V] = Data[V]
		end

		ACF.Armor.SetMassByDensity(Entity,Entity.ACF.Density)
	end

	function MakeACF_Armor(Player, Pos, Angle, Data)
		VerifyData(Data)
		local Plate
		local Armor = Armors.Get(Data.ArmorType)

		if Primitive and true then -- use the cool primitive props made by shadowscion, also leveraging the new volumetric armor system
			Plate = ents.Create("primitive_shape")
			Plate:Spawn()
			Plate:Activate()
			Plate:SetAngles(Angle)
			Plate:SetPos(Pos)

			Plate:SetPrimTYPE("cube")
			Plate:SetPrimMESHPHYS(true)
			Plate:SetPrimMESHUV(48)

			local Density = Armor.Density

			if Data.BuildDupeInfo then -- Data is saved differently than what is given by the tooldata
				Plate:SetPrimSIZE(Vector(Data.Width,Data.Height,Data.Thickness * ACF.MmToInch))
			else
				Plate:SetPrimSIZE(Vector(Data.PlateSizeX,Data.PlateSizeY,Data.PlateSizeZ * ACF.MmToInch))
			end

			Plate.Owner = Player
			Plate.ACF = {}
			Plate.ACF.Density = Density

			Player:AddCount("primitive", Plate)
			Player:AddCleanup("primitive", Plate)

			ACF.Armor.SetMassByDensity(Plate,Density)

			do -- Mass entity mod removal
				local EntMods = Data.EntityMods

				if EntMods and EntMods.mass then
					EntMods.mass = nil
				end
			end

			return Plate
		end
		if not Player:CheckLimit("_acf_armor") then return end
		Plate = ents.Create("acf_armor")

		if not IsValid(Plate) then return end

		local CanSpawn = hook.Run("ACF_PreEntitySpawn", "acf_armor", Player, Data, Armor)
		if CanSpawn == false then return false end

		Player:AddCount("_acf_armor", Plate)
		Player:AddCleanup("_acf_armor", Plate)

		Plate:SetModel("models/holograms/cube.mdl")
		Plate:SetMaterial("sprops/textures/sprops_metal1")
		Plate:SetPlayer(Player)
		Plate:SetAngles(Angle)
		Plate:SetPos(Pos)
		Plate:Spawn()

		Plate.Owner     = Player -- MUST be stored on ent for PP
		Plate.ACF = {}
		Plate.ACF.Density = Density
		Plate.DataStore = Entities.GetArguments("acf_armor")

		UpdatePlate(Plate, Data, Armor)

		if Armor.OnSpawn then
			Armor:OnSpawn(Plate, Data)
		end

		hook.Run("ACF_OnEntitySpawn", "acf_armor", Plate, Data, Armor)

		do -- Mass entity mod removal
			local EntMods = Data.EntityMods

			if EntMods and EntMods.mass then
				EntMods.mass = nil
			end
		end

		ACF.Activate(Plate)

		local state = Plate:GetNW2Bool("ACF.Volumetric",false) -- solves some ??????? issue when spawning plates by tool, would break looking at a plate with the armor tool
		Plate:SetNW2Bool("ACF.Volumetric",false)
		timer.Simple(0,function() Plate:SetNW2Bool("ACF.Volumetric",state) end)

		return Plate
	end

	Entities.Register("acf_armor", MakeACF_Armor, "Width", "Height", "Thickness", "ArmorType")

	------------------- Updating ---------------------

	function ENT:Update(Data)
		VerifyData(Data)

		local Armor = Armors.Get(Data.ArmorType)

		hook.Run("ACF_OnEntityLast", "acf_armor", self, OldClass)

		ACF.SaveEntity(self)

		UpdatePlate(self, Data, Armor)

		ACF.RestoreEntity(self)

		if Armor.OnUpdate then
			Armor:OnUpdate(Plate, Data)
		end

		hook.Run("ACF_OnEntityUpdate", "acf_armor", self, Data, Armor)

		net.Start("ACF_UpdateEntity")
			net.WriteEntity(self)
		net.Broadcast()

		return true, "Armor plate updated successfully!"
	end
end

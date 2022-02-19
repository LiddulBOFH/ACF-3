AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

local ACF = ACF

ACF.RegisterClassLink("acf_vision_controller", "prop_vehicle_prisoner_pod", function(VisionController, Target)
	if VisionController.VehicleLink[Target] then return false, "This vehicle is already linked to this vision controller!" end
	if Target.ACFVisionController == VisionController then return false, "This vehicle is already linked to this vision controller!" end

	Target.ACFVisionController = VisionController
	Target:CallOnRemove( "acf_vision_controller_remove_pod", function()
		local dr = Target:GetDriver()
		if dr:IsValid() then ACF_Vision.enable(dr,0) end
		VisionController:Unlink( Target )
	end)

	VisionController.Vehicles[#VisionController.Vehicles + 1] = Target

	VisionController.VehicleLink[Target] = true

	Target.ACFVisionController = VisionController

	VisionController:UpdateOverlay()

	return true, "Vehicle linked successfully!"
end)

ACF.RegisterClassUnlink("acf_vision_controller", "prop_vehicle_prisoner_pod", function(VisionController, Target)
	if VisionController.VehicleLink[Target] or Target.VisionController == VisionController then
		local idx = 0
		for i = 1,#VisionController.Vehicles do
			if VisionController.Vehicles[i] == Target then
				idx = i
				break
			end
		end

		table.remove( VisionController.Vehicles, idx )
		VisionController.VehicleLink[Target] = nil
		Target.ACFVisionController = nil
		Target:RemoveCallOnRemove( "acf_vision_controller_remove_pod" )

		VisionController:UpdateOverlay()

		return true, "Vehicle unlinked successfully!"
	end

	return false, "This vehicle is not linked to this vision controller."
end)

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--

local CheckLegal  = ACF_CheckLegal
local Components  = ACF.Classes.Components
local HookRun     = hook.Run

--===============================================================================================--

do -- Spawn and update function
	local function VerifyData(Data)
		if not Data.VisionController then
			Data.VisionController = Data.Component or Data.Id
		end

		local Class = ACF.GetClassGroup(Components, Data.VisionController)

		if not Class or Class.Entity ~= "acf_vision_controller" then
			Data.VisionController = "VS-CNTRL"

			Class = ACF.GetClassGroup(Components, "VS-CNTRL")
		end

		do -- External verifications
			if Class.VerifyData then
				Class.VerifyData(Data, Class)
			end

			HookRun("ACF_VerifyData", "acf_vision_controller", Data, Class)
		end
	end

	local function CreateInputs(Entity, Data, Class, VisionController)
		local List = {}

		if Class.SetupInputs then
			Class.SetupInputs(List, Entity, Data, Class, VisionController)
		end

		HookRun("ACF_OnSetupInputs", "acf_vision_controller", List, Entity, Data, Class, VisionController)

		if Entity.Inputs then
			Entity.Inputs = WireLib.AdjustInputs(Entity, List)
		else
			Entity.Inputs = WireLib.CreateInputs(Entity, List)
		end
	end

	local function CreateOutputs(Entity, Data, Class, VisionController)
		local List = { "Entity [ENTITY]" }

		if Class.SetupOutputs then
			Class.SetupOutputs(List, Entity, Data, Class, VisionController)
		end

		HookRun("ACF_OnSetupOutputs", "acf_vision_controller", List, Entity, Data, Class, VisionController)

		if Entity.Outputs then
			Entity.Outputs = WireLib.AdjustOutputs(Entity, List)
		else
			Entity.Outputs = WireLib.CreateOutputs(Entity, List)
		end
	end

	local function UpdateVisionController(Entity, Data, Class, VisionController)
		Entity.ACF = Entity.ACF or {}
		Entity.ACF.Model = VisionController.Model -- Must be set before changing model

		Entity:SetModel(VisionController.Model)

		Entity:PhysicsInit(SOLID_VPHYSICS)
		Entity:SetMoveType(MOVETYPE_VPHYSICS)

		if Entity.OnLast then
			Entity:OnLast()
		end

		-- Storing all the relevant information on the entity for duping
		for _, V in ipairs(Entity.DataStore) do
			Entity[V] = Data[V]
		end

		Entity.Name         = VisionController.Name
		Entity.ShortName    = Entity.VisionController
		Entity.EntType      = Class.Name
		Entity.ClassData    = Class
		Entity.OnUpdate     = VisionController.OnUpdate or Class.OnUpdate
		Entity.OnLast       = VisionController.OnLast or Class.OnLast
		Entity.OverlayTitle = VisionController.OnOverlayTitle or Class.OnOverlayTitle
		Entity.OverlayBody  = VisionController.OnOverlayBody or Class.OnOverlayBody
		Entity.OnDamaged    = VisionController.OnDamaged or Class.OnDamaged
		Entity.OnEnabled    = VisionController.OnEnabled or Class.OnEnabled
		Entity.OnDisabled   = VisionController.OnDisabled or Class.OnDisabled
		Entity.OnThink      = VisionController.OnThink or Class.OnThink

		Entity:SetNWString("WireName", "ACF " .. VisionController.Name)
		Entity:SetNW2String("ID", Entity.VisionController)

		CreateInputs(Entity, Data, Class, VisionController)
		CreateOutputs(Entity, Data, Class, VisionController)

		ACF.Activate(Entity, true)

		Entity.ACF.LegalMass	= VisionController.Mass
		Entity.ACF.Model		= VisionController.Model

		local Phys = Entity:GetPhysicsObject()
		if IsValid(Phys) then Phys:SetMass(VisionController.Mass) end

		if Entity.OnUpdate then
			Entity:OnUpdate(Data, Class, VisionController)
		end

		if Entity.OnDamaged then
			Entity:OnDamaged()
		end
	end

	hook.Add("ACF_OnSetupInputs", "ACF Vision Controller Inputs", function(Class, List, _, _, _, VisionController)
		if Class ~= "acf_vision_controller" then return end
		if not VisionController.Inputs then return end

		local Count = #List

		for I, Input in ipairs(VisionController.Inputs) do
			List[Count + I] = Input
		end
	end)

	hook.Add("ACF_OnSetupOutputs", "ACF Vision Controller Outputs", function(Class, List, _, _, _, VisionController)
		if Class ~= "acf_vision_controller" then return end
		if not VisionController.Outputs then return end

		local Count = #List

		for I, Output in ipairs(VisionController.Outputs) do
			List[Count + I] = Output
		end
	end)

	-- Handle entering/leaving vehicle with a controller on
	hook.Add("PlayerEnteredVehicle", "acf_vision_controller", function(player, vehicle)
		if IsValid(vehicle.ACFVisionController) and (vehicle.ACFVisionController.VisionSettings.VisionMode ~= 0) then
			ACF_Vision.enable(player, vehicle.ACFVisionController.VisionSettings.VisionMode)
		end
	end)
	hook.Add("PlayerLeaveVehicle", "acf_vision_controller", function(player, vehicle)
		if IsValid(vehicle.ACFVisionController) and (vehicle.ACFVisionController.VisionSettings.VisionMode ~= 0) then
			ACF_Vision.enable(player, 0)
		end
	end)

	--------------------------------------------------
	-- Leave camera manually
	--------------------------------------------------
	concommand.Add( "acf_vision_controller_leave", function(player)
		if IsValid(player.ACFVisionController) then
			ACF_Vision.enable(player, 0)
		end
	end)

	-------------------------------------------------------------------------------

	function MakeACF_VisionController(Player, Pos, Angle, Data)
		VerifyData(Data)

		local Class = ACF.GetClassGroup(Components, Data.VisionController)
		local VisionController = Class.Lookup[Data.VisionController]
		local Limit = Class.LimitConVar.Name

		if not Player:CheckLimit(Limit) then return false end

		local Entity = ents.Create("acf_vision_controller")

		if not IsValid(Entity) then return end

		Entity:SetPlayer(Player)
		Entity:SetAngles(Angle)
		Entity:SetPos(Pos)
		Entity:Spawn()

		Player:AddCleanup("acf_vision_controller", Entity)
		Player:AddCount(Limit, Entity)

		Entity.Owner     	= Player -- MUST be stored on ent for PP
		Entity.Vehicles   	= {}
		Entity.VehicleLink	= {}
		Entity.DataStore 	= ACF.GetEntityArguments("acf_vision_controller")

		Entity.VisionSettings = {
			NightVision 	= false,
			ThermalVision	= false,
			ThermalMode		= false,
			VisionMode		= 0,
		}

		UpdateVisionController(Entity, Data, Class, VisionController)

		if Class.OnSpawn then
			Class.OnSpawn(Entity, Data, Class, VisionController)
		end

		HookRun("ACF_OnEntitySpawn", "acf_vision_controller", Entity, Data, Class, VisionController)

		WireLib.TriggerOutput(Entity, "Entity", Entity)

		Entity:UpdateOverlay(true)

		do -- Mass entity mod removal
			local EntMods = Data and Data.EntityMods

			if EntMods and EntMods.mass then
				EntMods.mass = nil
			end
		end

		CheckLegal(Entity)

		return Entity
	end

	ACF.RegisterEntityClass("acf_vision_controller", MakeACF_VisionController, "VisionController")
	ACF.RegisterLinkSource("acf_vision_controller", "Vehicles")

	------------------- Updating ---------------------

	function ENT:Update(Data)
		VerifyData(Data)

		local Class    = ACF.GetClassGroup(Components, Data.VisionController)
		local VisionController = Class.Lookup[Data.VisionController]

		HookRun("ACF_OnEntityLast", "acf_vision_controller", self, OldClass)

		ACF.SaveEntity(self)

		UpdateVisionController(self, Data, Class, VisionController)

		ACF.RestoreEntity(self)

		if Class.OnUpdate then
			Class.OnUpdate(self, Data, Class, VisionController)
		end

		HookRun("ACF_OnEntityUpdate", "acf_vision_controller", self, Data, Class, VisionController)

		self:UpdateOverlay(true)

		net.Start("ACF_UpdateEntity")
			net.WriteEntity(self)
		net.Broadcast()

		return true, "Vision Controller updated successfully!"
	end
end

function ENT:SetVision(force)
	if #self.Vehicles > 0 then
		for i = 1, #self.Vehicles do
			local driver = self.Vehicles[i]:GetDriver()
			if driver:IsValid() then
				if not force then ACF_Vision.enable(driver,self.VisionSettings.VisionMode) else ACF_Vision.enable(driver,0) end
			end
		end
	end
end

function ENT:ACF_OnDamage(Energy, FrArea, Angle, Inflictor)
	local HitRes = ACF.PropDamage(self, Energy, FrArea, Angle, Inflictor)

	--self.Spread = ACF.MaxDamageInaccuracy * (1 - math.Round(self.ACF.Health / self.ACF.MaxHealth, 2))
	if self.OnDamaged then
		self:OnDamaged()
	end

	return HitRes
end

function ENT:Enable()
	if self.OnEnabled then
		self:OnEnabled()
	end
end

function ENT:Disable()
	if self.OnDisabled then
		self:OnDisabled()
	end
end

function ENT:UpdateOverlayText()
	local Title = self.OverlayTitle and self:OverlayTitle() or "Idle"
	local Body = self.OverlayBody and self:OverlayBody()

	Body = Body and ("\n\n" .. Body) or ""

	return Title .. Body
end

function ENT:Think()
	if self.OnThink then
		self:OnThink()
	end

	self:NextThink(ACF.CurTime)

	return true
end

function ENT:PreEntityCopy()
	if next(self.Vehicles) then
		local Entities = {}

		for Vehicle in pairs(self.Vehicles) do
			Entities[#Entities + 1] = Vehicle:EntIndex()
		end

		duplicator.StoreEntityModifier(self, "Vehicles", Entities)
	end

	-- wire dupe info
	self.BaseClass.PreEntityCopy(self)
end

function ENT:PostEntityPaste(Player, Ent, CreatedEntities)
	local EntMods = Ent.EntityMods

	if EntMods.Vehicles then
		for _, EntID in pairs(EntMods.Vehicles) do
			self:Link(CreatedEntities[EntID])
		end

		EntMods.Vehicles = nil
	end

	-- Wire dupe info
	self.BaseClass.PostEntityPaste(self, Player, Ent, CreatedEntities)
end

function ENT:ClearEntities()
	for i = 1,#self.Vehicles do
		self.Vehicles[i]:RemoveCallOnRemove( "acf_vision_controller_remove_pod" )
		self.Vehicles[i].ACFVisionController = nil
	end

	self.Vehicles = {}
	return true
end

function ENT:OnRemove()
	local OldClass = self.ClassData

	if OldClass.OnLast then
		OldClass.OnLast(self, OldClass)
	end

	HookRun("ACF_OnEntityLast", "acf_vision_controller", self, OldClass)

	self:ClearEntities()

	if self.OnLast then
		self:OnLast()
	end

	timer.Remove("ACF VisionController Clock " .. self:EntIndex())

	WireLib.Remove(self)
end

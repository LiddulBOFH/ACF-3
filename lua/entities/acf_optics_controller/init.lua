AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- ACF Link Bullshittery

ACF.RegisterClassLink("acf_optics_controller", "prop_vehicle_prisoner_pod", function(OpticsController, Target)
	if OpticsController.VehicleLink[Target] then return false, "This vehicle is already linked to this optics controller!" end
	if Target.ACFOpticsController == OpticsController then return false, "This vehicle is already linked to this optics controller!" end

	Target.ACFOpticsController = OpticsController
	Target:CallOnRemove( "acf_optics_controller_remove_pod", function()
		local dr = Target:GetDriver()
		if dr:IsValid() then ACF_Vision.enable(dr,0) end
		OpticsController:Unlink( Target )
	end)

	OpticsController.Vehicles[#OpticsController.Vehicles + 1] = Target
	OpticsController.Players = {}

	OpticsController.VehicleLink[Target] = true

	Target.ACFOpticsController = OpticsController

	OpticsController:UpdateOverlay()

	return true, "Vehicle linked successfully!"
end)

ACF.RegisterClassUnlink("acf_optics_controller", "prop_vehicle_prisoner_pod", function(OpticsController, Target)
	if OpticsController.VehicleLink[Target] or Target.OpticsController == OpticsController then
		local idx = 0
		for i = 1,#OpticsController.Vehicles do
			if OpticsController.Vehicles[i] == Target then
				idx = i
				break
			end
		end

		table.remove( OpticsController.Vehicles, idx )
		OpticsController.VehicleLink[Target] = nil
		Target.ACFOpticsController = nil
		Target:RemoveCallOnRemove( "acf_optics_controller_remove_pod" )

		OpticsController:UpdateOverlay()

		return true, "Vehicle unlinked successfully!"
	end

	return false, "This rack is not linked to this optics controller."
end)

ACF.RegisterLinkSource("acf_optics_controller", "Vehicles")

--------------------------------------------------
-- Initialize
--------------------------------------------------

local ClassLink = ACF.GetClassLink
local ClassUnlink = ACF.GetClassUnlink

-- TODO: Make CamController FLIR disabled

function ENT:Initialize()
	self:SetModel("models/props_combine/combine_binocular01.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)

	self.Inputs = WireLib.CreateInputs( self, {"Thermal Vision", "Thermal Mode", "Night Vision"} )

	self.Players = {}
	self.Vehicles = {}
	self.VehicleLink = {}

	self.NightVision = false
	self.ThermalVision = false
	self.ThermalMode = 0
	self.VisionMode = 0

	ACF_AddThermalEntity(self)

	self:SetNWString("WireName", "ACF Optics Controller")
	self:UpdateOverlay()
end

--------------------------------------------------
-- UpdateOverlay
--------------------------------------------------

function ENT:UpdateOverlay()
	local Text = "Seats linked: %s\nMode: %s"
	local VicCount = #self.Vehicles
	local Mode = self.NightVision and "Night Vision Active" or self.ThermalVision and "Thermal Vision Active" or "Inactive"

	self:SetOverlayText(Text:format(VicCount,Mode))
end

--------------------------------------------------
-- UpdateOutputs
--------------------------------------------------
function ENT:UpdateOutputs()
	if CurTime() < self.NextUpdateOutputs then return end



	self.NextUpdateOutputs = CurTime() + 0.1
end

--------------------------------------------------
-- OnRemove
--------------------------------------------------

function ENT:OnRemove()

	self:ClearEntities()
end

--------------------------------------------------
-- Set Vision
--------------------------------------------------

function ENT:SetVision(force)
	if #self.Vehicles > 0 then
		for i = 1, #self.Vehicles do
			local driver = self.Vehicles[i]:GetDriver()
			if driver:IsValid() then
				if not force then ACF_Vision.enable(driver,self.VisionMode) else ACF_Vision.enable(driver,0) end
			end
		end
	end
end

--------------------------------------------------
-- TriggerInput
--------------------------------------------------

function ENT:TriggerInput( name, value )
	if name == "Night Vision" then
		self.NightVision = value ~= 0
		self.ThermalVision = false
	elseif name == "Thermal Vision" then
		self.NightVision = false
		self.ThermalVision = value ~= 0
	elseif name == "Thermal Mode" then
		self.ThermalMode = math.Clamp(value,0,2)
	end
	self.VisionMode = (self.NightVision and 1) or (self.ThermalVision and (2 + self.ThermalMode)) or 0
	self:SetVision()
	self:UpdateOverlay()
end

--------------------------------------------------
-- Enter/exit vehicle hooks
--------------------------------------------------

hook.Add("PlayerEnteredVehicle", "acf_optics_controller", function(player, vehicle)
	if IsValid(vehicle.ACFOpticsController) and (vehicle.ACFOpticsController.VisionMode ~= 0) then
		ACF_Vision.enable(player, vehicle.ACFOpticsController.VisionMode)
	end
end)
hook.Add("PlayerLeaveVehicle", "acf_optics_controller", function(player, vehicle)
	if IsValid(vehicle.ACFOpticsController) and (vehicle.ACFOpticsController.VisionMode ~= 0) then
		ACF_Vision.enable(player, 0)
	end
end)

--------------------------------------------------
-- Leave camera manually
--------------------------------------------------
concommand.Add( "acf_optics_controller_leave", function(player)
	if IsValid(player.ACFOpticsController) then
		ACF_Vision.enable(player, 0)
	end
end)

--------------------------------------------------
-- Linking to vehicles
--------------------------------------------------

function ENT:Link(Target)
	if not IsValid(Target) then return false, "Attempted to link an invalid entity." end
	if self == Target then return false, "Can't link an optics controller to itself." end

	local Function = ClassLink(self:GetClass(), Target:GetClass())

	if Function then
		return Function(self, Target)
	end

	return false, "Optics controllers can't be linked to '" .. Target:GetClass() .. "'."
end

function ENT:Unlink(Target)
	if not IsValid(Target) then return false, "Attempted to unlink an invalid entity." end
	if self == Target then return false, "Can't unlink an optics controller from itself." end

	local Function = ClassUnlink(self:GetClass(), Target:GetClass())

	if Function then
		return Function(self, Target)
	end

	return false, "Optics controllers can't be unlinked from '" .. Target:GetClass() .. "'."
end

function ENT:ClearEntities()
	for i = 1,#self.Vehicles do
		self.Vehicles[i]:RemoveCallOnRemove( "acf_optics_controller_remove_pod" )
		self.Vehicles[i].ACFOpticsController = nil
	end

	self.Vehicles = {}
	return true
end

--------------------------------------------------
-- Dupe support
--------------------------------------------------

function ENT:BuildDupeInfo()
	local info = BaseClass.BuildDupeInfo(self)
	local veh = {}
	for i = 1,#self.Vehicles do
		veh[i] = self.Vehicles[i]:EntIndex()
	end
	info.Vehicles = veh

	info.OldDupe = self.OldDupe

	-- Other options are saved using duplicator.RegisterEntityClass

	return info
end

function ENT:ApplyDupeInfo(ply, ent, info, GetEntByID)
	BaseClass.ApplyDupeInfo(self, ply, ent, info, GetEntByID)

	if info.cam or info.pod or info.OldDupe then -- OLD DUPE DETECTED
		if info.cam then
			local CamEnt = GetEntByID( info.cam )
			if IsValid( CamEnt ) then CamEnt:Remove() end
		end

		if info.pod then
			self.Vehicles[1] = GetEntByID( info.pod )
		end

		WireLib.AdjustSpecialInputs( self, {"Thermal Vision", "Thermal Mode", "Night Vision"} )

		self.OldDupe = true
	else
		local veh = info.Vehicles
		if veh then
			for i = 1,#veh do
				self:LinkEnt( GetEntByID( veh[i] ) )
			end
		end
	end
end

duplicator.RegisterEntityClass("acf_optics_controller", WireLib.MakeWireEnt, "Data")

ACF.RegisterComponentClass("VS-CNTRL", {
	Name	= "Vision Controller",
	Entity	= "acf_vision_controller",
	LimitConVar = {
		Name	= "_acf_vision_controller",
		Amount	= 4,
		Text	= "Maximum amount of ACF Vision Controllers a player can create."
	}
})

-- Input actions
if SERVER then
	ACF.AddInputAction("acf_vision_controller", "Night Vision", function(Entity, Value)
		if Entity.VisionSettings == nil then return end

		Value = tobool(Value)

		if Entity.VisionSettings.NightVision == Value then return end

		Entity.VisionSettings.NightVision = Value
	end)
end

do -- Vision Controller

	ACF.RegisterComponent("VS-CNTRL", "VS-CNTRL", {
		Name		= "Vision Controller",
		Description	= "A device capable of providing night vision.",
		Model		= "models/props_combine/combine_binocular01.mdl",
		Mass		= 50,
		Inputs		= { "Night Vision" },
		Outputs		= {},
		Preview = {
			FOV = 110,
		},
		CreateMenu = function(Data, Menu)
			Menu:AddLabel("Mass : " .. Data.Mass .. " kg")
			Menu:AddLabel("This entity can be fully parented.")

			ACF.SetClientData("PrimaryClass", "acf_vision_controller")
		end,
		-- Serverside actions
		OnUpdate = function(Entity)
			--WireLib.TriggerOutput(Entity, "Current Coordinates", Vector())
		end,
		OnLast = function(Entity)
			Entity.VisionSettings = nil
		end,
		OnOverlayTitle = function(Entity)
			if Entity.VisionSettings == nil then return end
			if Entity.VisionSettings.VisionMode ~= 0 then return "Active" end
		end,
		OnOverlayBody = function(Entity)
			if Entity.VisionSettings == nil then return end
			local T = "Inactive"
			if Entity.VisionSettings.VisionMode == 1 then T = "Night Vision Active" end

			return T
		end,
		OnDamaged = function(Entity) -- Make damage affect vision? should darken to the point of being unusable
			if Entity.VisionSettings == nil then return end
		end,
		OnEnabled = function(Entity)

		end,
		OnDisabled = function(Entity)
			Entity:TriggerInput("Night Vision", 0)
		end,
		OnThink = function(Entity)
			local CheckVisionChange = (Entity.VisionSettings.NightVision and 1) or (Entity.VisionSettings.ThermalVision and (2 + Entity.VisionSettings.ThermalMode)) or 0
			if Entity.VisionSettings.VisionMode == CheckVisionChange then return end
			Entity.VisionSettings.VisionMode = CheckVisionChange
			Entity:SetVision()

			Entity:UpdateOverlay()
		end,
	})
end

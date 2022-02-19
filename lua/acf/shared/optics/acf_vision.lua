--[[
	Totally not ripped from Wire FLIR
--]]

--TODO: IR Lamps and Laser Designator beam show up

AddCSLuaFile("wire/flir.lua")

-- Removes the flir command that Wire adds
concommand.Remove("flir_enable")

-- Creates the master table with some default shit
if not ACF_Vision then ACF_Vision = {mode = 0, intensitymod = 0, intensitycheck = 0, PreColor = Vector()} end

if CLIENT then

	--[[
	-- Materials created for use in thermals
	ACF_Vision.temp_sensative = Material("models/optics/acf_thermal")

	local function FinalHeatColor(entity)
		if entity.ACF_Temperature or false then return Vector(1,1,1) * entity.ACF_Temperature
		elseif entity:IsPlayer() or entity:IsNPC() or entity:IsNextBot() then return Vector(0.8,0.8,0.8) end

		return Vector(0,0,0)
	end

	matproxy.Add( {
		name = "ACF_Temperature", -- the name of the proxy added to the vmt file
		init = function( self, _, values ) -- that blank entry is the material itself, not needed for this case
			self.Temp = values.resultvar -- I still don't fucking get how this works, but it works
		end,
		bind = function( self, mat, ent ) -- this is the function that runs on a per-entity basis, but on the material
			if ( not IsValid( ent ) ) then return end
			-- $color2 doesn't normally have the ability to accept a vector via proxy, but this is gmod and we do what we want
			mat:SetVector(self.Temp,FinalHeatColor(ent))
		end
	} )
	]]

	ACF_Vision.opaque = Material("models/debug/debugwhite")

	-- Color modification used in thermals
	ACF_Vision.thermal_colmod = {
		[ "$pp_colour_addr" ] = -2.1,
		[ "$pp_colour_addg" ] = -2.1,
		[ "$pp_colour_addb" ] = -2.1,
		[ "$pp_colour_brightness" ] = 2,
		[ "$pp_colour_contrast" ] = 1,
		[ "$pp_colour_colour" ] = 0,
		[ "$pp_colour_mulr" ] = 0,
		[ "$pp_colour_mulg" ] = 0,
		[ "$pp_colour_mulb" ] = 0
	}

	-- Color modification used in nightvision (dynamically changes)
	ACF_Vision.nv_colmod = {
		[ "$pp_colour_addr" ] = -0.02,
		[ "$pp_colour_addg" ] = -0.0,
		[ "$pp_colour_addb" ] = -0.02,
		[ "$pp_colour_brightness" ] = 0.02,
		[ "$pp_colour_contrast" ] = 0,
		[ "$pp_colour_colour" ] = 0,
		[ "$pp_colour_mulr" ] = 0.5,
		[ "$pp_colour_mulg" ] = 1,
		[ "$pp_colour_mulb" ] = 0.5
	}

	-- Material overrides, used in thermals
	local materialOverrides = {
		PlayerDraw = { ACF_Vision.temp_sensative },
		DrawOpaqueRenderables = { ACF_Vision.temp_sensative, nil },
		DrawTranslucentRenderables = { ACF_Vision.temp_sensative, nil },
	}

	--local IntensityFlip = 1

	local function CheckValidVision()
		if not IsValid(LocalPlayer():GetVehicle()) then return false end
		return LocalPlayer():GetVehicle():GetThirdPersonMode()
	end

	-- Actual functions to start/stop vision control

	function ACF_Vision.nightvision_start()
		ACF_Vision.PreColor = render.GetAmbientLightColor()

		local T = Material("color")
		hook.Add("PostDraw2DSkyBox", "ACF_Vision", function()
			if CheckValidVision() then return end
			render.OverrideDepthEnable( true, false )

			cam.Start3D(Vector(0, 0, 0), EyeAngles())
				render.SetColorModulation(0,0,0)
				render.SetMaterial(T)
				render.DrawSphere(Vector(),-16,16,8,Color(12,12,12))
			cam.End3D()

			render.OverrideDepthEnable( false, false )
		end)

		hook.Add("RenderScreenspaceEffects", "ACF_Vision", function()
			if CheckValidVision() then return end
			DrawColorModify(ACF_Vision.nv_colmod)
			--DrawBloom(-0,0,12,12,10,1,0.2,0.2,0.2)
			DrawSharpen(1,1.5)
			DrawSobel(10)
			DrawTexturize(0,Material("postprocessing/acf_nightvision.png"))
		end)

		hook.Add("PostDrawOpaqueRenderables","ACF_Vision",function(a,b)
			if CheckValidVision() then return end
			if a == true then return end
			--render.BrushMaterialOverride(ACF_Vision.opaque)
			--render.ModelMaterialOverride(ACF_Vision.opaque)
		end)

		hook.Add("PostRender","ACF_Vision Intensity Mod",function()
			if CheckValidVision() then return end
			if CurTime() > ACF_Vision.intensitycheck then ACF_Vision.AdjustIntensity() end
		end)
	end

	--[[
	function ACF_Vision.thermal_start(mode)
		local T = Material("color")
		hook.Add("PostDraw2DSkyBox", "ACF_Vision", function()
			if CheckValidVision() then return end
			render.OverrideDepthEnable( true, false )

			cam.Start3D(Vector(0, 0, 0), EyeAngles())
				render.SetColorModulation(0,0,0)
				render.SetMaterial(T)
				render.DrawSphere(Vector(),-16,16,8,Color(12,12,12))
			cam.End3D()

			render.OverrideDepthEnable( false, false )
		end)

		for hookName, materials in pairs(materialOverrides) do -- make this dynamically change "materials" dependent on temperature
			hook.Add("Pre" .. hookName, "ACF_Vision", function() if CheckValidVision() then return end render.ModelMaterialOverride(materials[1]) end)
			hook.Add("Post" .. hookName, "ACF_Vision", function() if CheckValidVision() then return end render.ModelMaterialOverride(materials[2]) end)
		end

		local FinalOverlay = "postprocessing/acf_thermal.png"
		if mode == 3 then FinalOverlay = "postprocessing/acf_thermal_whot.png"
		elseif mode == 4 then FinalOverlay = "postprocessing/acf_thermal_bhot.png" end

		hook.Add("RenderScreenspaceEffects", "ACF_Vision", function()
			if CheckValidVision() then return end
			DrawColorModify(ACF_Vision.thermal_colmod)
			DrawBloom(0,200,5,5,3,0.1,0,0,0)
			DrawSharpen(1,0.5)
			DrawTexturize(0,Material(FinalOverlay))
		end)

		hook.Add("PostRender","ACF_Vision Intensity Mod",function()
			if CheckValidVision() then return end
			if CurTime() > ACF_Vision.intensitycheck then ACF_Vision.AdjustIntensity() end
		end)
	end
	]]--

	function ACF_Vision.stop()
		for hookName, _ in pairs(materialOverrides) do
			hook.Remove("Pre" .. hookName, "ACF_Vision")
			hook.Remove("Post" .. hookName, "ACF_Vision")
		end

		render.SetLightingMode(0)
		hook.Remove("PreRender","ACF_Vision")
		hook.Remove("RenderScreenspaceEffects", "ACF_Vision")
		hook.Remove("PostRender", "ACF_Vision Intensity Mod")
		hook.Remove("PostDraw2DSkyBox", "ACF_Vision")
		hook.Remove("PostDrawOpaqueRenderables","ACF_Vision_WorldStencil")

		render.MaterialOverride(nil)

		ACF_Vision.nv_colmod["$pp_colour_contrast"] = 4
		ACF_Vision.thermal_colmod["$pp_colour_contrast"] = 2

		ACF_Vision.intensitycheck = CurTime()
		ACF_Vision.intensitymod = 0
	end

	function ACF_Vision.enable(mode) -- actually toggles the whole system
		if ACF_Vision.mode == mode then return end
		ACF_Vision.mode = mode

		render.RedownloadAllLightmaps(true,true)

		ACF_Vision.stop()

		if mode == 1 then ACF_Vision.nightvision_start() end
		--elseif mode >= 2 and mode <= 4 then ACF_Vision.thermal_start(mode) end

		IntensityFlip = (ACF_Vision.mode == 4) and -1 or 1
	end

	local function FormatPixel(r,g,b)
		return (r + g + b) / 765
	end

	function ACF_Vision.AdjustIntensity()
		local X = ScrW()
		local Y = ScrH()
		local XD = X / 16
		local YD = Y / 16
		render.CapturePixels()

		-- get the brightness of each pixel
		-- center (more weight to brightness here)
		local Sum = 0
		local Count = 10
		Sum = Sum + (FormatPixel(render.ReadPixel(math.floor(X / 2), math.floor(Y / 2))) * 10)

		-- checking in various sized circles for pixel brightness
		for I = 1, 8 do
			Count = Count + 3
			local Ang = (360 / 8) * I
			Sum = Sum + FormatPixel(render.ReadPixel(math.floor((X / 2) + (math.cos(Ang) * XD)), math.floor((Y / 2) + (math.sin(Ang) * YD))))
			Sum = Sum + FormatPixel(render.ReadPixel(math.floor((X / 2) + (math.cos(Ang) * XD * 2)), math.floor((Y / 2) + (math.sin(Ang) * YD * 2))))
			Sum = Sum + FormatPixel(render.ReadPixel(math.floor((X / 2) + (math.cos(Ang) * XD * 4)), math.floor((Y / 2) + (math.sin(Ang) * YD * 4))))
		end

		local Average = Sum / Count
		local CenterPoint = 0.25 - Average
		if math.abs(CenterPoint) > 0.05 then
			ACF_Vision.intensitymod = math.Clamp(ACF_Vision.intensitymod + (CenterPoint / 20),-4,4)
		end

		if ACF_Vision.mode == 1 then
			ACF_Vision.nv_colmod["$pp_colour_contrast"] = 4 + (ACF_Vision.intensitymod * 4)
		elseif ACF_Vision.mode ~= 2 then
			ACF_Vision.thermal_colmod["$pp_colour_contrast"] = 2 + (ACF_Vision.intensitymod * 4)
		end

		ACF_Vision.intensitycheck = CurTime() + (FrameTime() * 20)
	end

	LocalPlayer():SetNWVarProxy("ACF_Vision_Mode",function(_,_,_,mode) ACF_Vision.enable(mode) end)
else
	-- Provides a function that enables usage
	-- 0 is off
	-- 1 is nightvision
	-- 2,3,4 is thermal vision, but different modes
	function ACF_Vision.enable(player, mode)
		player:SetNWInt("ACF_Vision_Mode",math.Clamp(math.floor(mode),0,1)) -- set 1 to 4 for all thermal settings, but those are disabled anyway; just a note for later ;)
	end

	engine.LightStyle(0,"b")

	-- An attempt at preventing interference between this and wire flir
	--FLIR.start = nil
	--function FLIR.start(player) ACF_Vision.enable(player, 0) FLIR.enable(player, true) end
end

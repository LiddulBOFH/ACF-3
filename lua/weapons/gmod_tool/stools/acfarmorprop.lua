local ACF = ACF

TOOL.Category	= (ACF.CustomToolCategory and ACF.CustomToolCategory:GetBool()) and "ACF" or "Construction"
TOOL.Name		= "#tool.acfarmorprop.name"
TOOL.Command	= nil
TOOL.ConfigName	= ""

TOOL.ClientConVar["thickness"] = 1
TOOL.ClientConVar["ductility"] = 0
TOOL.ClientConVar["density"] = 0

local MinimumArmor = ACF.MinimumArmor
local MaximumArmor = ACF.MaximumArmor

-- Calculates mass, armor, and health given prop area and desired ductility and thickness.
local function CalcArmor(Area, Ductility, Thickness, Ent)
	local mass = Area * (1 + Ductility) ^ 0.5 * Thickness * 0.00078
	local armor = ACF_CalcArmor(Area, Ductility, mass)
	local health = ACF.Armor.CalculateHealth(Ent,7.84) * (1 + Ductility)

	return mass, armor, health
end

local function UpdateValues(Entity, Data, PhysObj, Area, Ductility)
	local Thickness, Mass

	if Data.Thickness then
		Thickness = math.Clamp(Data.Thickness, MinimumArmor, MaximumArmor)
		Mass      = CalcArmor(Area, Ductility * 0.01, Thickness, Entity)

		duplicator.ClearEntityModifier(Entity, "mass")
	else
		local EntMods = Entity.EntityMods
		local MassMod = EntMods and EntMods.mass

		Mass = MassMod and MassMod.Mass or PhysObj:GetMass()
	end

	Entity.ACF.Thickness = Thickness
	Entity.ACF.Ductility = Ductility * 0.01

	if Mass ~= Entity.ACF.Mass then
		Entity.ACF.Mass = Mass

		PhysObj:SetMass(Mass)
	end
end

local function UpdateArmor(_, Entity, Data)
	if CLIENT then return end
	if not Data then return end
	if not ACF.Check(Entity) then return end

	local PhysObj   = Entity.ACF.PhysObj
	local Area      = Entity.ACF.Area
	local Ductility = math.Clamp(Data.Ductility or 0, -80, 80)

	UpdateValues(Entity, Data, PhysObj, Area, Ductility)

	duplicator.ClearEntityModifier(Entity, "ACF_Armor")
	duplicator.StoreEntityModifier(Entity, "ACF_Armor", { Thickness = Data.Thickness, Ductility = Ductility })
end

hook.Add("ACF_OnServerDataUpdate", "ACF_ArmorTool_MaxThickness", function(_, Key, Value)
	if Key ~= "MaxThickness" then return end

	MaximumArmor = math.floor(ACF.CheckNumber(Value, ACF.MaximumArmor))
end)

if CLIENT then
	language.Add("tool.acfarmorprop.name", "ACF Armor Properties")
	language.Add("tool.acfarmorprop.desc", "Sets the weight of a prop by desired armor thickness and ductility.")
	language.Add("tool.acfarmorprop.0", "Left click to apply settings. Right click to copy settings. Reload to get the total mass of an object and all constrained objects.")

	surface.CreateFont("Torchfont", { size = 40, weight = 1000, font = "arial" })

	local ArmorProp_Area = CreateClientConVar("acfarmorprop_area", 0, false, true) -- we don't want this one to save
	local ArmorProp_Ductility = CreateClientConVar("acfarmorprop_ductility", 0, false, true, "", -80, 80)
	local ArmorProp_Thickness = CreateClientConVar("acfarmorprop_thickness", 1, false, true, "", MinimumArmor, MaximumArmor)
	local ArmorProp_Density = CreateClientConVar("acfarmorprop_density", 7.84, false, true, "", 0.0001,math.huge)

	local ScanSwitch = CreateClientConVar("acfarmorprop_scanswitch", 0, false, true, "", 0, 1)

	local Sphere = CreateClientConVar("acfarmorprop_sphere_search", 0, false, true, "", 0, 1)
	local Radius = CreateClientConVar("acfarmorprop_sphere_radius", 0, false, true, "", 0, 10000)

	local UseDensity = CreateClientConVar("acfarmorprop_densityswitch", 0, false, true, "", 0, 1)
	local NominalSwitch = CreateClientConVar("acfarmorprop_nominalswitch", 0, false, true, "", 0, 1)

	local TextGray = Color(224, 224, 255)
	local BGGray = Color(200, 200, 200)
	local Blue = Color(50, 200, 200)
	local Red = Color(200, 50, 50)
	local Green = Color(50, 200, 50)
	local Black = Color(0, 0, 0)

	local ArmorColor = Color(65,255,65)
	local NominalColor = Color(65,65,255)

	local drawText = draw.SimpleTextOutlined

	surface.CreateFont("ACF_ToolTitle", {
		font = "Arial",
		size = 32
	})

	surface.CreateFont("ACF_ToolSub", {
		font = "Arial",
		size = 25
	})

	surface.CreateFont("ACF_ToolLabel", {
		font = "Arial",
		size = 32,
		weight = 620
	})

	surface.CreateFont("ACF_WorldText", {
		font = "Arial",
		size = 18,
		weight = 600
	})

	local ArmorScanData = {}
	local function ScanArmor(trace,density) -- this was broken out of the DrawHUD function both to enable cross function readability as well as allow me to delay it, for performance
		local time = SysTime()

		local StartPos = trace.StartPos
		local BaseDir = LocalPlayer():EyeAngles():Forward()

		if ArmorScanData.NextScan and (time < ArmorScanData.NextScan) then return
		else
			local NominalStart, NominalEnd = StartPos
			local ArmorDir,NominalDir = BaseDir,BaseDir

			local Armor, ArmorEnd, ArmorStart = ACF.Armor.GetArmor(trace,density)
			local Nominal = "INSIDE"
			local ArmorValid,NominalValid = false

			if trace.HitPos ~= trace.StartPos then
				Nominal, NominalEnd, NominalStart = ACF.Armor.GetArmor({StartPos = trace.HitPos + (trace.HitNormal * 10),HitPos = trace.HitPos,Entity = trace.Entity},density)

				Nominal = math.Round(Nominal,1) .. "mm"

				if ArmorEnd then ArmorDir = (ArmorEnd - ArmorStart):GetNormalized() ArmorValid = true end -- HitPos can still occasionally be nil, not sure why exactly
				if NominalEnd then NominalDir = (NominalEnd - NominalStart):GetNormalized() NominalValid = true end
			end

			Armor = math.Round(Armor,1)

			ArmorScanData.armor = {armor = Armor, startPos = ArmorStart, endPos = ArmorEnd, dir = ArmorDir, valid = ArmorValid}
			ArmorScanData.nominal = {armor = Nominal, startPos = NominalStart, endPos = NominalEnd, dir = NominalDir, valid = NominalValid}

			local timeDiff = SysTime() - time
			ArmorScanData.NextScan = time + math.min(timeDiff * 10,0.1)
		end
	end

	local ArmorList = ArmorList or {}
	local LongestText = 0
	local LowDensity,HighDensity = 7.84,7.84 -- set to steel, not important

	function TOOL.BuildCPanel(Panel) -- TODO: Make a line of text change depending on settings
		local Presets = vgui.Create("ControlPresets")
			Presets:AddConVar("acfarmorprop_thickness")
			Presets:AddConVar("acfarmorprop_ductility")
			Presets:AddConVar("acfarmorprop_density")
			Presets:SetPreset("acfarmorprop")
		Panel:AddItem(Presets)

		Panel:NumSlider("Thickness", "acfarmorprop_thickness", MinimumArmor, MaximumArmor)
		Panel:ControlHelp("Set the desired armor thickness (in mm) and the mass will be adjusted accordingly.")

		Panel:NumSlider("Ductility", "acfarmorprop_ductility", -80, 80)
		Panel:ControlHelp("Set the desired armor ductility (thickness-vs-health bias). A ductile prop can survive more damage but is penetrated more easily (slider > 0). A non-ductile prop is brittle - hardened against penetration, but more easily shattered by bullets and explosions (slider < 0).")

		local Divider1 = vgui.Create("DPanel",Panel)
		Divider1:SetSize(100,1)
		Divider1:DockMargin(2,6,2,0)
		Divider1:Dock(TOP)
		Divider1.Paint = function(_,w,h)
			surface.SetDrawColor(color_black)
			surface.DrawRect(0,0,w,h)
		end

		local DensityToggle = Panel:CheckBox("Thickness (ON), Density (OFF)", "acfarmorprop_densityswitch")
		Panel:ControlHelp("This toggles setting the density directly for eligible props, or using the setting below to determine the density required to match the thickness set above.")

		local NominalToggle = Panel:CheckBox("Nominal (ON), Line of sight (OFF)", "acfarmorprop_nominalswitch")
		Panel:ControlHelp("If on, this will use the NOMINAL distance (based on the face you are looking at), otherwise it is the distance through the prop from your perspective.")

		--DensityToggle:SetChecked(false)

		local Armors = ACF.Classes.ArmorTypes
		for _,v in pairs(Armors) do
			LowDensity = math.min(LowDensity,v.Density)
			HighDensity = math.max(HighDensity,v.Density)

			if v.Hide then continue end

			if #v.Name > LongestText then LongestText = #v.Name end
			ArmorList[#ArmorList + 1] = {Name = v.Name,Density = v.Density}
		end
		table.sort(ArmorList,function(a,b) return a.Density < b.Density end)

		local DensitySlider = Panel:NumSlider("Density", "acfarmorprop_density", LowDensity, math.min(HighDensity,400))
		DensitySlider:SetValue(7.84)
		Panel:ControlHelp("Select an armor material to set the density above. (g/cm3)")

		local ArmorSelect = vgui.Create("DListView",Panel)
		ArmorSelect:SetSize(100,14 + (14 * #ArmorList))
		ArmorSelect:DockMargin(0,5,0,5)
		ArmorSelect:Dock(TOP)
		ArmorSelect:SetMultiSelect(false)
		ArmorSelect:SetHeaderHeight(14)
		ArmorSelect:SetDataHeight(14)

		local MatCol = ArmorSelect:AddColumn("Material")
		local DensCol = ArmorSelect:AddColumn("Density (g/cm3)")

		MatCol:SetFixedWidth(200)

		for _,v in ipairs(ArmorList) do
			ArmorSelect:AddLine(v.Name,v.Density)
		end

		ArmorSelect.OnRowSelected = function(_,index,_)
			DensitySlider:SetValue(ArmorList[index].Density)
		end

		local Divider2 = vgui.Create("DPanel",Panel)
		Divider2:SetSize(100,1)
		Divider2:DockMargin(2,6,2,0)
		Divider2:Dock(TOP)
		Divider2.Paint = function(_,w,h)
			surface.SetDrawColor(color_black)
			surface.DrawRect(0,0,w,h)
		end

		local ScanToggle = Panel:CheckBox("LOS Armor Scan (ON), Mass Check (OFF)", "acfarmorprop_scanswitch")
		Panel:ControlHelp("If checked, pressing RELOAD will perform a line of sight check for armor")

		local SphereCheck = Panel:CheckBox("Use sphere search for armor readout", "acfarmorprop_sphere_search")
		Panel:ControlHelp("If checked, the tool will find all the props in a sphere around the hit position instead of getting all the entities connected to a prop.")

		local SphereRadius = Panel:NumSlider("Sphere search radius", "acfarmorprop_sphere_radius", 0, 2000, 0)
		Panel:ControlHelp("Defines the radius of the search sphere, only applies if the checkbox above is checked.")

		function SphereCheck:OnChange(Bool)
			SphereRadius:SetEnabled(Bool)
		end

		SphereRadius:SetEnabled(SphereCheck:GetChecked())
	end

	local BubbleText = "Current:\nMass: %s kg\nArmor: %s mm\nHealth: %s hp\n\nAfter:\nMass: %s kg\nArmor: %s mm\nHealth: %s hp"

	--[[
	if IsValid(ent) and ent:GetNW2Bool("ACF.Volumetric",false) then
		render.SetColorMaterial()

		local nominal = ArmorScanData.nominal
		local armor = ArmorScanData.armor
		if armor.valid then
			local start = armor.startPos
			local endPos = armor.endPos
			local ang = armor.dir:Angle()

			render.DrawLine(start,endPos,ArmorColor)
			render.DrawWireframeBox(start,ang,Vector(0,-1,-1),Vector(0,1,1),ArmorColor)
			render.DrawWireframeBox(endPos,ang,Vector(0,-1,-1),Vector(0,1,1),ArmorColor)
		end
		if nominal.valid then
			local start = nominal.startPos
			local endPos = nominal.endPos
			local ang = nominal.dir:Angle()

			render.DrawLine(start,endPos,NominalColor)
			render.DrawWireframeBox(start,ang,Vector(0,-1,-1),Vector(0,1,1),NominalColor)
			render.DrawWireframeBox(endPos,ang,Vector(0,-1,-1),Vector(0,1,1),NominalColor)
		end
	end
	]]

	local function Line2DPos(V1,V2)
		local P1,P2 = V1:ToScreen(),V2:ToScreen()
		return P1.x,P1.y,P2.x,P2.y
	end

	function TOOL:DrawHUD()
		local Trace = self:GetOwner():GetEyeTrace()
		local Ent = Trace.Entity

		if not IsValid(Ent) then return false end
		if Ent:IsPlayer() or Ent:IsNPC() then return false end
		if Ent.GetArmor then return end

		if Ent:GetNW2Bool("ACF.Volumetric",false) then
			local Armor = ArmorScanData.armor
			local Nominal = ArmorScanData.nominal

			if Nominal.valid then
				local ang = Nominal.dir:Angle()
				local startPos = Nominal.startPos
				local endPos = Nominal.endPos
				local u = ang:Up()
				local r = ang:Right()
				-- aaaaaaaaa
				local s1 = u + r
				local s2 = -u + r
				local s3 = -u - r
				local s4 = u - r

				surface.SetDrawColor(NominalColor)
				draw.NoTexture()

				surface.DrawLine(Line2DPos(startPos,endPos))

				surface.DrawLine(Line2DPos(startPos + s1,startPos + s2))
				surface.DrawLine(Line2DPos(startPos + s2,startPos + s3))
				surface.DrawLine(Line2DPos(startPos + s3,startPos + s4))
				surface.DrawLine(Line2DPos(startPos + s4,startPos + s1))

				surface.DrawLine(Line2DPos(endPos + s1,endPos + s2))
				surface.DrawLine(Line2DPos(endPos + s2,endPos + s3))
				surface.DrawLine(Line2DPos(endPos + s3,endPos + s4))
				surface.DrawLine(Line2DPos(endPos + s4,endPos + s1))

				local textPos = (Vector(0,0,6) + (endPos + startPos) / 2):ToScreen()
				drawText("NOMINAL: " .. Nominal.armor,"ACF_WorldText",textPos.x,textPos.y,TextGray,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER,1,Black)
			end
			if Armor.valid then
				local ang = Armor.dir:Angle()
				local startPos = Armor.startPos
				local endPos = Armor.endPos
				local u = ang:Up()
				local r = ang:Right()
				-- aaaaaaaaa
				local s1 = u + r
				local s2 = -u + r
				local s3 = -u - r
				local s4 = u - r

				surface.SetDrawColor(ArmorColor)
				draw.NoTexture()

				surface.DrawLine(Line2DPos(startPos,endPos))

				surface.DrawLine(Line2DPos(startPos + s1,startPos + s2))
				surface.DrawLine(Line2DPos(startPos + s2,startPos + s3))
				surface.DrawLine(Line2DPos(startPos + s3,startPos + s4))
				surface.DrawLine(Line2DPos(startPos + s4,startPos + s1))

				surface.DrawLine(Line2DPos(endPos + s1,endPos + s2))
				surface.DrawLine(Line2DPos(endPos + s2,endPos + s3))
				surface.DrawLine(Line2DPos(endPos + s3,endPos + s4))
				surface.DrawLine(Line2DPos(endPos + s4,endPos + s1))

				local textPos = (Vector(0,0,6) + (Armor.endPos + Armor.startPos) / 2):ToScreen()
				drawText("ARMOR: " .. Armor.armor .. "mm","ACF_WorldText",textPos.x,textPos.y,TextGray,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER,1,Black)
			end

			return false
		end

		local Weapon = self.Weapon
		local Mass = math.Round(Weapon:GetNWFloat("WeightMass"), 2)
		local Armor = math.Round(Weapon:GetNWFloat("MaxArmour"), 2)
		local Health = math.Round(Weapon:GetNWFloat("MaxHP"), 2)

		local Area = ArmorProp_Area:GetFloat()
		local Ductility = ArmorProp_Ductility:GetFloat()
		local Thickness = ArmorProp_Thickness:GetFloat()

		local NewMass, NewArmor, NewHealth = CalcArmor(Area, Ductility * 0.01, Thickness, Ent)
		local Text = BubbleText:format(Mass, Armor, Health, math.Round(NewMass, 2), math.Round(NewArmor, 2), math.Round(NewHealth, 2))

		AddWorldTip(nil, Text, nil, Ent:GetPos())
	end

	function TOOL:DrawToolScreen()
		local Trace = self:GetOwner():GetEyeTrace()
		local Ent   = Trace.Entity
		local Weapon = self.Weapon
		local Health = math.Round(Weapon:GetNWFloat("HP", 0))
		local MaxHealth = math.Round(Weapon:GetNWFloat("MaxHP", 0))

		if IsValid(Ent) and Ent.GetArmor then -- Is procedural armor
			local Material = Ent.ArmorType
			local Mass     = math.Round(Weapon:GetNWFloat("WeightMass", 0), 1)
			local Angle    = math.Round(ACF.GetHitAngle(Trace.HitNormal, (Trace.HitPos - Trace.StartPos):GetNormalized()), 1)
			local Armor    = math.Round(Ent:GetArmor(Trace))
			local Size     = Ent:GetSize()
			local Nominal  = math.Round(math.min(Size[1], Size[2], Size[3]) * 25.4, 1)
			local MaxArmor = Ent:GetSize():Length() * 25.4

			cam.Start2D()
				render.Clear(0, 0, 0, 0)
				surface.SetDrawColor(Black)
				surface.DrawRect(0, 0, 256, 256)
				surface.SetDrawColor(BGGray)
				surface.DrawRect(0, 34, 256, 2)

				drawText("ACF Armor Data", "ACF_ToolTitle", 128, 20, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)
				drawText("Material: " .. Material, "ACF_ToolSub", 128, 48, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)
				drawText("Weight: " .. Mass .. "kg", "ACF_ToolSub", 128, 70, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)
				drawText("Nominal Armor: " .. Nominal .. "mm", "ACF_ToolSub", 128, 92, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)

				draw.RoundedBox(6, 10, 110, 236, 32, BGGray)
				draw.RoundedBox(6, 10, 110, Angle / 90 * 236, 32, Green)
				drawText("Hit Angle: " .. Angle .. "°", "ACF_ToolLabel", 15, 110, Black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 0, BGGray)

				draw.RoundedBox(6, 10, 160, 236, 32, BGGray)
				draw.RoundedBox(6, 10, 160, Armor / MaxArmor * 236, 32, Blue)
				drawText("Armor: " .. Armor .. "mm", "ACF_ToolLabel", 15, 160, Black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 0, BGGray)

				draw.RoundedBox(6, 10, 210, 236, 32, BGGray)
				draw.RoundedBox(6, 10, 210, Health / MaxHealth * 236, 32, Red)
				drawText("Health: " .. Health, "ACF_ToolLabel", 15, 210, Black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 0, Black)
				--drawText("")
			cam.End2D()
		elseif IsValid(Ent) and Ent:GetNW2Bool("ACF.Volumetric",false) then
			local Mass     = math.Round(Weapon:GetNWFloat("WeightMass", 0), 1)
			local Size     = Ent.MeshTotalSize or (Ent:OBBMaxs() - Ent:OBBMins()) * 0.99
			local Density  = Ent:GetNW2Float("ACF.Density",1)

			local MaxArmor = ACF.Armor.RHAe(Size:Length() * 25.4,Density)

			local Angle    = 0
			if Trace.StartPos ~= Trace.HitPos then
				Angle = math.Round(ACF.GetHitAngle(Trace.HitNormal, (Trace.HitPos - Trace.StartPos):GetNormalized()), 1)
			end

			ScanArmor(Trace,Density)
			local Armor = ArmorScanData.armor.armor or 0
			local Nominal = ArmorScanData.nominal.armor or 0

			--if not ACF.ModelData.IsOnStandby(Ent:GetModel()) then Armor = math.Round(ACF.Armor.GetArmor(Trace,Density),1) end

			cam.Start2D()
				render.Clear(0, 0, 0, 0)
				surface.SetDrawColor(Black)
				surface.DrawRect(0, 0, 256, 256)
				surface.SetDrawColor(BGGray)
				surface.DrawRect(0, 34, 256, 2)

				drawText("ACF Armor Data", "ACF_ToolTitle", 128, 20, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)
				drawText("Density: " .. math.Round(Density,3) .. " g/cm3", "ACF_ToolSub", 128, 48, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)
				drawText("Weight: " .. Mass .. "kg", "ACF_ToolSub", 128, 70, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)
				drawText("Nominal: " .. Nominal, "ACF_ToolSub", 128, 92, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, BGGray)

				draw.RoundedBox(6, 10, 110, 236, 32, BGGray)
				draw.RoundedBox(6, 10, 110, Angle / 90 * 236, 32, Green)
				drawText("Hit Angle: " .. Angle .. "°", "ACF_ToolLabel", 15, 110, Black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 0, BGGray)

				draw.RoundedBox(6, 10, 160, 236, 32, BGGray)
				draw.RoundedBox(6, 10, 160, Armor / MaxArmor * 236, 32, Blue)
				drawText("Armor: " .. Armor .. "mm", "ACF_ToolLabel", 15, 160, Black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 0, BGGray)

				draw.RoundedBox(6, 10, 210, 236, 32, BGGray)
				draw.RoundedBox(6, 10, 210, Health / MaxHealth * 236, 32, Red)
				drawText("Health: " .. Health, "ACF_ToolLabel", 15, 210, Black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 0, Black)
				--drawText("")
			cam.End2D()
		else
			local Armour = math.Round(Weapon:GetNWFloat("Armour", 0), 2)
			local MaxArmour = math.Round(Weapon:GetNWFloat("MaxArmour", 0), 2)
			local HealthTxt = Health .. "/" .. MaxHealth
			local ArmourTxt = Armour .. "/" .. MaxArmour

			cam.Start2D()
				render.Clear(0, 0, 0, 0)

				surface.SetDrawColor(Black)
				surface.DrawRect(0, 0, 256, 256)
				surface.SetFont("Torchfont")

				-- header
				draw.SimpleTextOutlined("ACF Stats", "Torchfont", 128, 30, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, color_black)

				-- armor bar
				draw.RoundedBox(6, 10, 83, 236, 64, BGGray)
				if Armour ~= 0 and MaxArmour ~= 0 then
					draw.RoundedBox(6, 15, 88, Armour / MaxArmour * 226, 54, Blue)
				end

				draw.SimpleTextOutlined("Armour", "Torchfont", 128, 100, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, color_black)
				draw.SimpleTextOutlined(ArmourTxt, "Torchfont", 128, 130, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, color_black)

				-- health bar
				draw.RoundedBox(6, 10, 183, 236, 64, BGGray)
				if Health ~= 0 and MaxHealth ~= 0 then
					draw.RoundedBox(6, 15, 188, Health / MaxHealth * 226, 54, Red)
				end

				draw.SimpleTextOutlined("Health", "Torchfont", 128, 200, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, color_black)
				draw.SimpleTextOutlined(HealthTxt, "Torchfont", 128, 230, TextGray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, color_black)
			cam.End2D()
		end


	end

	-- clamp thickness if the change in ductility puts mass out of range
	cvars.AddChangeCallback("acfarmorprop_ductility", function(_, _, value)

		local area = ArmorProp_Area:GetFloat()

		-- don't bother recalculating if we don't have a valid ent
		if area == 0 then return end

		local ductility = math.Clamp((tonumber(value) or 0) / 100, -0.8, 0.8)
		local thickness = math.Clamp(ArmorProp_Thickness:GetFloat(), MinimumArmor, MaximumArmor)
		local mass = CalcArmor(area, ductility, thickness)

		if mass > 50000 or mass < 0.1 then
			mass = math.Clamp(mass, 0.1, 50000)

			thickness = ACF_CalcArmor(area, ductility, mass)
			ArmorProp_Thickness:SetFloat(math.Clamp(thickness, MinimumArmor, MaximumArmor))
		end
	end)

	-- clamp ductility if the change in thickness puts mass out of range
	cvars.AddChangeCallback("acfarmorprop_thickness", function(_, _, value)

		local area = ArmorProp_Area:GetFloat()

		-- don't bother recalculating if we don't have a valid ent
		if area == 0 then return end

		local thickness = math.Clamp(tonumber(value) or MinimumArmor, MinimumArmor, MaximumArmor)
		local ductility = math.Clamp(ArmorProp_Ductility:GetFloat() * 0.01, -0.8, 0.8)
		local mass = CalcArmor(area, ductility, thickness)

		if mass > 50000 or mass < 0.1 then
			mass = math.Clamp(mass, 0.1, 50000)

			ductility = -(39 * area * thickness - mass * 50000) / (39 * area * thickness)
			ArmorProp_Ductility:SetFloat(math.Clamp(ductility * 100, -80, 80))
		end
	end)

	local GreenSphere = Color(0, 200, 0, 50)
	local GreenFrame = Color(0, 200, 0, 100)

	hook.Add("PostDrawOpaqueRenderables", "Armor Tool Search Sphere", function()
		local Player = LocalPlayer()
		local Tool = Player:GetTool()
		local eyeTrace = Player:GetEyeTrace()
		local ent = eyeTrace.Entity

		if not Tool then return end -- Player has no toolgun
		if Tool ~= Player:GetTool("acfarmorprop") then return end -- Current tool is not the armor tool
		if Tool.Weapon ~= Player:GetActiveWeapon() then return end -- Player is not holding the toolgun

		if Sphere:GetBool() then -- Spherical contraption search
			local Value = Radius:GetFloat()

			if Value <= 0 then return end

			local Pos = eyeTrace.HitPos

			render.SetColorMaterial()
			render.DrawSphere(Pos, Value, 20, 20, GreenSphere)
			render.DrawWireframeSphere(Pos, Value, 20, 20, GreenFrame, true)
		end
	end)
else -- Serverside-only stuff
	function TOOL:Think()
		local Player = self:GetOwner()
		local Ent = Player:GetEyeTrace().Entity

		if Ent == self.AimEntity then return end

		local Weapon = self.Weapon

		if ACF.Check(Ent) then
			Player:ConCommand("acfarmorprop_area " .. Ent.ACF.Area)
			Player:ConCommand("acfarmorprop_thickness " .. self:GetClientNumber("thickness")) -- Force sliders to update themselves

			Weapon:SetNWFloat("WeightMass", Ent.ACF.Mass)
			Weapon:SetNWFloat("HP", Ent.ACF.Health)
			Weapon:SetNWFloat("Armour", Ent.ACF.Armour)
			Weapon:SetNWFloat("MaxHP", Ent.ACF.MaxHealth)
			Weapon:SetNWFloat("MaxArmour", Ent.ACF.MaxArmour)
		else
			Player:ConCommand("acfarmorprop_area 0")

			Weapon:SetNWFloat("WeightMass", 0)
			Weapon:SetNWFloat("HP", 0)
			Weapon:SetNWFloat("Armour", 0)
			Weapon:SetNWFloat("MaxHP", 0)
			Weapon:SetNWFloat("MaxArmour", 0)
		end

		self.AimEntity = Ent
	end

	duplicator.RegisterEntityModifier("ACF_Armor", UpdateArmor)
	duplicator.RegisterEntityModifier("acfsettings", function(_, Entity, Data)
		if CLIENT then return end
		if not ACF.Check(Entity, true) then return end

		local EntMods   = Entity.EntityMods
		local MassMod   = EntMods and EntMods.mass
		local PhysObj   = Entity.ACF.PhysObj
		local Area      = Entity.ACF.Area
		local Mass      = MassMod and MassMod.Mass or PhysObj:GetMass()
		local Ductility = math.Clamp(Data.Ductility or 0, -80, 80) * 0.01
		local Thickness = ACF_CalcArmor(Area, Ductility, Mass, Entity)

		duplicator.ClearEntityModifier(Entity, "mass")
		duplicator.ClearEntityModifier(Entity, "acfsettings")

		UpdateArmor(_, Entity, { Thickness = Thickness, Ductility = Ductility * 100 })
	end)

	-- ProperClipping compatibility

	if ProperClipping then
		local Override = {
			AddClip = true,
			RemoveClip = true,
			RemoveClips = true,
		}

		for Name in pairs(Override) do
			local Old = ProperClipping[Name]

			ProperClipping[Name] = function(Entity, ...)
				local EntMods = Entity.EntityMods
				local MassMod = EntMods and EntMods.mass
				local Result  = Old(Entity, ...)

				if not EntMods then return Result end

				local Armor = EntMods.ACF_Armor

				if Armor and Armor.Thickness then
					if MassMod then
						duplicator.ClearEntityModifier(Entity, "ACF_Armor")
						duplicator.StoreEntityModifier(Entity, "ACF_Armor", { Ductility = Armor.Ductility })
					else
						duplicator.ClearEntityModifier(Entity, "mass")
					end
				end

				return Result
			end
		end
	end
end

do -- Allowing everyone to read contraptions
	local HookCall = hook.Call

	function hook.Call(Name, Gamemode, Player, Entity, Tool, ...)
		if Name == "CanTool" and Tool == "acfarmorprop" and Player:KeyPressed(IN_RELOAD) then
			return true
		end

		return HookCall(Name, Gamemode, Player, Entity, Tool, ...)
	end
end

-- Apply settings to prop
function TOOL:LeftClick(Trace)
	local Ent = Trace.Entity

	if not IsValid(Ent) then return false end
	if Ent:IsPlayer() or Ent:IsNPC() then return false end
	if CLIENT then return true end
	if not ACF.Check(Ent) then return false end

	local Thickness = self:GetClientNumber("thickness")

	if Ent.ACF.ArmorCalcType == "Volumetric" then
		local Density = math.Round(self:GetClientNumber("density",7.84),6)
		local DensitySwitch = self:GetClientNumber("densityswitch",0)
		local NominalSwitch = self:GetClientNumber("nominalswitch",0)

		if DensitySwitch == 0 then
			ACF.Armor.SetMassByDensity(Ent,Density)
		else
			print("Setting armor to " .. Thickness)
			local StartPos,EndPos = Trace.StartPos,Trace.HitPos
			local Length = 1
			if (NominalSwitch == 1) and (StartPos ~= EndPos) then
				Length = ACF.Armor.GetDistanceThroughMesh({StartPos = EndPos + (Trace.HitNormal * 10),HitPos = EndPos,Entity = Ent})
			else
				Length = ACF.Armor.GetDistanceThroughMesh({StartPos = StartPos,HitPos = EndPos,Entity = Ent},self:GetOwner():EyeAngles():Forward())
			end
			ACF.Armor.SetMassByDensity(Ent,(Thickness / Length) * 7.84)
		end
	else
		local Ductility = self:GetClientNumber("ductility")
		duplicator.ClearEntityModifier(Ent, "mass")

		UpdateArmor(_, Ent, { Thickness = Thickness, Ductility = Ductility })
	end

	-- this invalidates the entity and forces a refresh of networked armor values
	self.AimEntity = nil

	return true
end

-- Suck settings from prop
function TOOL:RightClick(Trace)
	local Ent = Trace.Entity

	if not IsValid(Ent) then return false end
	if Ent:IsPlayer() or Ent:IsNPC() then return false end
	if CLIENT then return true end
	if not ACF.Check(Ent) then return false end

	local Player = self:GetOwner()

	Player:ConCommand("acfarmorprop_thickness " .. Ent.ACF.MaxArmour)
	Player:ConCommand("acfarmorprop_ductility " .. Ent.ACF.Ductility * 100)

	return true
end

do -- Armor readout
	local SendMessage = ACF.SendMessage

	local Text1 = "--- Contraption Readout (Owner: %s) ---"
	local Text2 = "Mass: %s kg total | %s kg physical (%s%%) | %s kg parented"
	local Text3 = "Mobility: %s hp/ton @ %s hp | %s liters of fuel"
	local Text4 = "Entities: %s (%s physical, %s parented, %s other entities) | %s constraints"

	-- Emulates the stuff done by ACF_CalcMassRatio except with a given set of entities
	local function ProcessList(Entities)
		local Constraints = {}

		local Owners = {}
		local Lookup = {}
		local Count  = 0

		local Power     = 0
		local Fuel      = 0
		local PhysNum   = 0
		local ParNum    = 0
		local ConNum    = 0
		local OtherNum  = 0
		local Total     = 0
		local PhysTotal = 0

		for _, Ent in ipairs(Entities) do
			if not ACF.Check(Ent) then
				if not Ent:IsWeapon() then -- We don't want to count weapon entities
					OtherNum = OtherNum + 1
				end
			elseif not (Ent:IsPlayer() or Ent:IsNPC()) then -- These will pass the ACF check, but we don't want them either
				local Owner = Ent:CPPIGetOwner()
				local PhysObj = Ent.ACF.PhysObj
				local Class = Ent:GetClass()
				local Mass = PhysObj:GetMass()
				local IsPhys = false

				if (IsValid(Owner) or Owner:IsWorld()) and not Lookup[Owner] then
					local Name = Owner:GetName()

					Count = Count + 1

					Owners[Count] = Name ~= "" and Name or "World"
					Lookup[Owner] = true
				end

				if Class == "acf_engine" then
					Power = Power + Ent.PeakPower * 1.34
				elseif Class == "acf_fueltank" then
					Fuel = Fuel + Ent.Capacity
				end

				-- If it has any valid constraint then it's a physical entity
				if Ent.Constraints and next(Ent.Constraints) then
					for _, Con in pairs(Ent.Constraints) do
						if IsValid(Con) and Con.Type ~= "NoCollide" then -- Nocollides don't count
							IsPhys = true

							if not Constraints[Con] then
								Constraints[Con] = true
								ConNum = ConNum + 1
							end
						end
					end
				end

				-- If it has no valid constraints but also no valid parent, then it's a physical entity
				if not (IsPhys or IsValid(Ent:GetParent())) then
					IsPhys = true
				end

				if IsPhys then
					PhysTotal = PhysTotal + Mass
					PhysNum = PhysNum + 1
				else
					ParNum = ParNum + 1
				end

				Total = Total + Mass
			end
		end

		local Name = next(Owners) and table.concat(Owners, ", ") or "None"

		return Power, Fuel, PhysNum, ParNum, ConNum, Name, OtherNum, Total, PhysTotal
	end

	local Modes = {
		Default = {
			CanCheck = function(_, Trace)
				local Ent = Trace.Entity

				if not IsValid(Ent) then return false end
				if Ent:IsPlayer() or Ent:IsNPC() then return false end

				return true
			end,
			GetResult = function(_, Trace)
				local Ent = Trace.Entity
				local Power, Fuel, PhysNum, ParNum, ConNum, Name, OtherNum = ACF_CalcMassRatio(Ent, true)

				return Power, Fuel, PhysNum, ParNum, ConNum, Name, OtherNum, Ent.acftotal, Ent.acfphystotal
			end
		},
		Sphere = {
			CanCheck = function(Tool)
				return Tool:GetClientNumber("sphere_radius") > 0
			end,
			GetResult = function(Tool, Trace)
				local Ents = ents.FindInSphere(Trace.HitPos, Tool:GetClientNumber("sphere_radius"))

				return ProcessList(Ents)
			end
		}
	}

	local function GetReadoutMode(Tool)
		if tobool(Tool:GetClientInfo("sphere_search")) then return Modes.Sphere end

		return Modes.Default
	end

	-- Total up mass of constrained ents
	function TOOL:Reload(Trace)
		local Mode = GetReadoutMode(self)

		if not Mode.CanCheck(self, Trace) then return false end
		if tobool(self:GetClientNumber("scanswitch",0)) then -- TODO: Fix for hitting clipped props first and then returning nil on second prop (back up trace?)
			if SERVER then return true end

			--debugoverlay.Cross(Trace.HitPos,3,5)
			local stop = false
			local iter = 0

			local dir = LocalPlayer():EyeAngles():Forward()
			local filter = {LocalPlayer()}
			local startPos = Trace.HitPos - (dir * 32)
			local endPos = Trace.HitPos

			local ScanArmor = 0
			local TotalArmor = 0

			while stop ~= true do
				--print(startPos,endPos,dir)
				local t = util.TraceLine({start = startPos,endpos = endPos + (dir * 1024),filter = filter})

				debugoverlay.Line(t.StartPos,t.HitPos,15,ColorRand(),true)
				debugoverlay.Cross(t.StartPos,3,15,Color(0,255,0),true)

				if not IsValid(t.Entity) then
					stop = true
					MsgN("[ArmorScan] Did not hit an entity!")
					break
				else
					local ent = t.Entity
					if not ent._Mesh and ent:GetNW2Bool("ACF.Volumetric",false) then MsgN("[ArmorScan] " .. tostring(ent) .. " does not have a mesh, repeat till you get full calculation!") ACF.Armor.BuildMesh(ent)
					elseif not (ent:IsPlayer() or ent:IsNPC()) then
						if ent:GetNW2Bool("ACF.Volumetric",false) then
							ScanArmor = ACF.Armor.GetArmor({StartPos = t.StartPos - (dir * 32),HitPos = t.HitPos,Filter = filter,Entity = ent},ent:GetNW2Float("ACF.Density",7.84))
							TotalArmor = TotalArmor + ScanArmor
							MsgN("[ArmorScan] [" .. math.Round(ScanArmor,1) .. "mm RHAe] - " .. tostring(ent))
						else
							stop = true
							MsgN("[ArmorScan] " .. tostring(ent) .. " was hit and stopped the calculation.")
							break
						end
					end
					table.insert(filter,ent)
				end

				iter = iter + 1
				if iter >= 30 then stop = true MsgN("[ArmorScan] Halted due to too many iterations") end
			end

			if stop then MsgN("[ArmorScan] Total armor before stopping: " .. math.Round(TotalArmor,1) .. "mm") end

			ACF.PrintToChat("Normal","Check console for results of armor scan!")
			return true
		end
		if CLIENT then return true end

		local Power, Fuel, PhysNum, ParNum, ConNum, Name, OtherNum, Total, PhysTotal = Mode.GetResult(self, Trace)
		local HorsePower = math.Round(Power / math.max(Total * 0.001, 0.001), 1)
		local PhysRatio = math.Round(100 * PhysTotal / math.max(Total, 0.001))
		local ParentTotal = Total - PhysTotal
		local Player = self:GetOwner()

		SendMessage(Player, nil, Text1:format(Name))
		SendMessage(Player, nil, Text2:format(math.Round(Total, 1), math.Round(PhysTotal, 1), PhysRatio, math.Round(ParentTotal, 1)))
		SendMessage(Player, nil, Text3:format(HorsePower, math.Round(Power), math.Round(Fuel)))
		SendMessage(Player, nil, Text4:format(PhysNum + ParNum + OtherNum, PhysNum, ParNum, OtherNum, ConNum))

		return true
	end
end

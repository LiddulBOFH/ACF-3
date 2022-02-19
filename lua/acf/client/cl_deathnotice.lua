-- Override the original AddDeathNotice so as to allow custom icons through ACF
-- Kinda hacky, but for about 2 years its been known and wanted to allow a more "modular" system in gmod itself, and still hasn't been done

local Deaths = {}
local NPC_Color = Color( 250, 50, 50, 255 )

-- If a corresponding ammo type doesn't fit in this list, then default to AP
local AmmoList = {}
AmmoList["AP"] = true
AmmoList["APCR"] = true
AmmoList["APDS"] = true
AmmoList["APFSDS"] = true
AmmoList["APHE"] = true -- missing, alternate texture
AmmoList["GLATGM"] = true
AmmoList["FL"] = true
AmmoList["HE"] = true
AmmoList["HEAT"] = true
AmmoList["HEATFS"] = true
AmmoList["HP"] = true -- missing, alternate texture
AmmoList["SM"] = true -- missing, alternate texture

-- Net funcs (overriding vanilla)
local function RecvPlayerKilledByPlayer()
	local Death = net.ReadTable()
	local victim = Death.victim
	if ( !IsValid( victim ) ) then return end
	local inflictor = Death.inflictor
	local attacker = Death.attacker

	if ( !IsValid( attacker ) ) then return end

	GAMEMODE:AddDeathNotice( attacker:Name(), attacker:Team(), inflictor, victim:Name(), victim:Team(), Death)
end
net.Receive( "PlayerKilledByPlayer", RecvPlayerKilledByPlayer )

local function RecvPlayerKilledSelf()
	local Death = net.ReadTable()
	local victim = Death.victim
	if ( !IsValid( victim ) ) then return end
	GAMEMODE:AddDeathNotice( nil, 0, "suicide", victim:Name(), victim:Team(), Death)
end
net.Receive( "PlayerKilledSelf", RecvPlayerKilledSelf )

local function RecvPlayerKilled()
	local Death = net.ReadTable()
	local victim = Death.victim
	if ( !IsValid( victim ) ) then return end
	local inflictor = Death.inflictor
	local attacker = "#" .. Death.attacker

	GAMEMODE:AddDeathNotice( attacker, -1, inflictor, victim:Name(), victim:Team(), Death)
end
net.Receive( "PlayerKilled", RecvPlayerKilled )

local function RecvPlayerKilledNPC()

	local Death = net.ReadTable()

	local victimtype = Death.victim
	local victim	= "#" .. Death.victim
	local inflictor	= Death.inflictor
	local attacker	= Death.attacker

	--
	-- For some reason the killer isn't known to us, so don't proceed.
	--
	if ( !IsValid( attacker ) ) then return end

	GAMEMODE:AddDeathNotice( attacker:Name(), attacker:Team(), inflictor, victim, -1,Death)

	local bIsLocalPlayer = ( IsValid(attacker) && attacker == LocalPlayer() )

	local bIsEnemy = IsEnemyEntityName( victimtype )
	local bIsFriend = IsFriendEntityName( victimtype )

	if ( bIsLocalPlayer && bIsEnemy ) then
		achievements.IncBaddies()
	end

	if ( bIsLocalPlayer && bIsFriend ) then
		achievements.IncGoodies()
	end

	if ( bIsLocalPlayer && ( !bIsFriend && !bIsEnemy ) ) then
		achievements.IncBystander()
	end
end
net.Receive( "PlayerKilledNPC", RecvPlayerKilledNPC )

local function RecvNPCKilledNPC()
	local Death = net.ReadTable()
	local victim	= "#" .. Death.victim
	local inflictor	= Death.inflictor
	local attacker	= "#" .. Death.attacker

	GAMEMODE:AddDeathNotice( attacker, -1, inflictor, victim, -1,Death)
end
net.Receive( "NPCKilledNPC", RecvNPCKilledNPC )

-- Notices

local function OverrideDeathNotice()
	function GAMEMODE:AddDeathNotice(Attacker, team1, Inflictor, Victim, team2, ExtraData)
		local Death = {}
		local IconStack = {}

		local BaseIcon = ""

		Death.time		= CurTime()

		Death.left		= Attacker
		Death.right		= Victim

		if type(Inflictor) == "string" then
			BaseIcon		= Inflictor
		else
			BaseIcon		= Inflictor:GetClass()
		end

		if (Death.left == Death.right) then
			--Death.left = nil
			BaseIcon = "suicide"
		end

		if Inflictor.IsACFEntity == true then
			local C = Inflictor:GetNWString("Class")

			if C != "" then BaseIcon = "acf_" .. C else BaseIcon = Inflictor:GetClass() end
		end

		if ( team1 == -1 ) then Death.color1 = table.Copy( NPC_Color )
		else Death.color1 = table.Copy( team.GetColor( team1 ) ) end

		if ( team2 == -1 ) then Death.color2 = table.Copy( NPC_Color )
		else Death.color2 = table.Copy( team.GetColor( team2 ) ) end

		if ExtraData then
			--PrintTable(ExtraData)
			if ExtraData.ACF_DamageType then
				local Fin = (AmmoList[ExtraData.ACF_DamageType] && ExtraData.ACF_DamageType) or "AP"
				Death.RoundIcon = "acf_ammo_" .. Fin
			end

			if ExtraData.IsSeated == true then
				Death.SeatIcon = "seated"

				if ExtraData.LastSeat == "models/buggy.mdl" then
					Death.SeatIcon = "seated_jeep"
				elseif ExtraData.LastSeat == "models/vehicle.mdl" then
					Death.SeatIcon = "seated_jalopy"
				elseif ExtraData.LastSeat == "models/airboat.mdl" then
					Death.SeatIcon = "seated_airboat"
				end --else
					-- Add finer logic for player dying in something armored
					--Death.SeatIcon = "seated_tank"
				--end

				print(Death.SeatIcon)

				--print(ExtraData.LastSeat)
			end
		end

		--Death.left = Death.right

		IconStack[#IconStack + 1] = BaseIcon
		if Death.RoundIcon then IconStack[#IconStack + 1] = Death.RoundIcon end
		if Death.SeatIcon then IconStack[#IconStack + 1] = Death.SeatIcon end
		Death.IconStack = table.Reverse(IconStack)

		table.insert( Deaths, Death )
	end

	local function DrawDeath( x, y, death, hud_deathnotice_time )

		local w,h = 0,0

		local endX = (x + ScrW()) * 0.49

		local fadeout = ( death.time + hud_deathnotice_time ) - CurTime()

		local alpha = math.Clamp( fadeout * 255, 0, 255 )
		death.color1.a = alpha
		death.color2.a = alpha

		-- Start with a fixed vertical size, and expand for any larger icons as needed
		h = 48

		for k,v in ipairs(death.IconStack) do
			local kx,ky = killicon.GetSize(v)
			kx = kx + 12
			if k == 1 then w = -kx / 2 end
			w = w + kx

			killicon.Draw( endX - w, y, v, alpha )

			h = math.max(h,ky)
			if k == #death.IconStack then w = w + (kx / 2) end
		end

		-- Draw KILLER
		if ( death.left ) then
			draw.SimpleText( death.left,"ChatFont", endX - w, y, death.color1, TEXT_ALIGN_RIGHT)
		end

		-- Draw VICTIM
		draw.SimpleText( death.right,"ChatFont", endX, y, death.color2, TEXT_ALIGN_LEFT)

		return math.max(y + h * 0.7,72)
	end

	local DeathNoticeTime = GetConVar("hud_deathnotice_time")
	local DrawHud = GetConVar("cl_drawhud")
	function GAMEMODE:DrawDeathNotice( x, y )
		if ( DrawHud:GetInt() == 0 ) then return end

		local hud_deathnotice_time = DeathNoticeTime:GetFloat()

		x = x * ScrW()
		y = y * ScrH()

		-- Draw
		for _, Death in pairs( Deaths ) do

			if ( Death.time + hud_deathnotice_time > CurTime() ) then

				if ( Death.lerp ) then
					x = x * 0.3 + Death.lerp.x * 0.7
					y = y * 0.3 + Death.lerp.y * 0.7
				end

				Death.lerp = Death.lerp or {}
				Death.lerp.x = x
				Death.lerp.y = y

				y = DrawDeath( x, y, Death, hud_deathnotice_time )

			end

		end

		-- We want to maintain the order of the table so instead of removing
		-- expired entries one by one we will just clear the entire table
		-- once everything is expired.
		for _, Death in pairs( Deaths ) do
			if ( Death.time + hud_deathnotice_time > CurTime() ) then
				return
			end
		end

		Deaths = {}

	end
end

hook.Add("Initialize","ACF_DeathNoticeOverrideDelay",function()
	OverrideDeathNotice()
end)

if GAMEMODE then
	OverrideDeathNotice()
end

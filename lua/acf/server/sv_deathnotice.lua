-- Overwriting the vanilla death functions to pass the inflictor entity all the way to the end, so any further processing can occur

local LastDamage = {}

hook.Add("DoPlayerDeath","PrePlayerDeath",function(ply,_,dmg)
	LastDamage[ply] = dmg
end)

local DamagedNPCs = {}
hook.Add("EntityTakeDamage","NPCTakeDamage",function(ent,dmg)
	if not ent:IsNPC() then return end
	DamagedNPCs[ent] = dmg
end)

local function OverrideDeathNoticeSV()
	function GAMEMODE:PlayerDeath( ply, inflictor, attacker )

		-- Don't spawn for at least 2 seconds
		ply.NextSpawnTime = CurTime() + 2
		ply.DeathTime = CurTime()

		local Death = {}

		if ply:InVehicle() then Death.IsSeated = true Death.LastSeat = ply:GetVehicle():GetModel() end
		if LastDamage[ply]:GetInflictor():GetTable().BulletData && (LastDamage[ply]:GetDamageType() == 0) then
			Death.ACF_DamageType = LastDamage[ply]:GetInflictor():GetTable().BulletData.Type
		end

		if ( IsValid( attacker ) && attacker:GetClass() == "trigger_hurt" ) then attacker = ply end

		if ( IsValid( attacker ) && attacker:IsVehicle() && IsValid( attacker:GetDriver() ) ) then
			attacker = attacker:GetDriver()
		end

		if ( !IsValid( inflictor ) && IsValid( attacker ) ) then
			inflictor = attacker
		end

		-- Convert the inflictor to the weapon that they're holding if we can.
		-- This can be right or wrong with NPCs since combine can be holding a
		-- pistol but kill you by hitting you with their arm.
		if ( IsValid( inflictor ) && inflictor == attacker && ( inflictor:IsPlayer() || inflictor:IsNPC() ) ) then
			inflictor = inflictor:GetActiveWeapon()
			if ( !IsValid( inflictor ) ) then inflictor = attacker end
		end

		player_manager.RunClass( ply, "Death", inflictor, attacker )

		if ( attacker == ply ) then

			Death.victim = ply
			net.Start( "PlayerKilledSelf" )
				net.WriteTable(Death)
			net.Broadcast()

			MsgAll( attacker:Nick() .. " suicided!\n" )

		return end

		if ( attacker:IsPlayer() ) then

			Death.victim = ply
			Death.inflictor = inflictor
			Death.attacker = attacker
			net.Start( "PlayerKilledByPlayer" )
				net.WriteTable(Death)
			net.Broadcast()

			MsgAll( attacker:Nick() .. " killed " .. ply:Nick() .. " using " .. inflictor:GetClass() .. "\n" )

		return end

		Death.victim = ply
		Death.inflictor = inflictor
		Death.attacker = attacker:GetClass()
		net.Start( "PlayerKilled" )
			net.WriteEntity( ply )
			net.WriteEntity( inflictor )
			net.WriteString( attacker:GetClass() )
		net.Broadcast()

		MsgAll( ply:Nick() .. " was killed by " .. attacker:GetClass() .. "\n" )
	end

	function GAMEMODE:OnNPCKilled( ent, attacker, inflictor )
		local Death = {}

		if DamagedNPCs[ent]:GetInflictor():GetTable().BulletData  && (DamagedNPCs[ent]:GetDamageType() == 0) then
			Death.ACF_DamageType = DamagedNPCs[ent]:GetInflictor():GetTable().BulletData.Type
		end

		-- Don't spam the killfeed with scripted stuff
		if ( ent:GetClass() == "npc_bullseye" || ent:GetClass() == "npc_launcher" ) then DamagedNPCs[ent] = nil return end

		if ( IsValid( attacker ) && attacker:GetClass() == "trigger_hurt" ) then attacker = ent end

		if ( IsValid( attacker ) && attacker:IsVehicle() && IsValid( attacker:GetDriver() ) ) then
			attacker = attacker:GetDriver()
		end

		if ( !IsValid( inflictor ) && IsValid( attacker ) ) then
			inflictor = attacker
		end

		-- Convert the inflictor to the weapon that they're holding if we can.
		if ( IsValid( inflictor ) && attacker == inflictor && ( inflictor:IsPlayer() || inflictor:IsNPC() ) ) then

			inflictor = inflictor:GetActiveWeapon()
			if ( !IsValid( attacker ) ) then inflictor = attacker end

		end

		local AttackerClass = "worldspawn"

		if ( IsValid( attacker ) ) then

			AttackerClass = attacker:GetClass()

			if ( attacker:IsPlayer() ) then

				Death.victim = ent:GetClass()
				Death.inflictor = inflictor
				Death.attacker = attacker

				net.Start( "PlayerKilledNPC" )
					net.WriteTable(Death)
				net.Broadcast()

				return
			end

		end

		if ( ent:GetClass() == "npc_turret_floor" ) then AttackerClass = ent:GetClass() end

		Death.victim = ent:GetClass()
		Death.inflictor = inflictor
		Death.attacker = AttackerClass

		net.Start( "NPCKilledNPC" )
			net.WriteTable(Death)
		net.Broadcast()

		DamagedNPCs[ent] = nil

	end
end

hook.Add("Initialize","ACF_svDeathNoticeOverrideDelay",function()
	OverrideDeathNoticeSV()
end)

if GAMEMODE then
	OverrideDeathNoticeSV()
end

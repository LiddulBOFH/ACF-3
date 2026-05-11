local ACF = ACF
do
    local function DamageFn(Victim, Attacker, Inflictor)
        local DmgInfo = DamageInfo()
        DmgInfo:SetDamage(math.huge)
        DmgInfo:SetDamageType(DMG_GENERIC)
        if IsValid(Attacker) then DmgInfo:SetAttacker(Attacker) end
        if IsValid(Inflictor) then DmgInfo:SetInflictor(Inflictor) end
        Victim:TakeDamageInfo(DmgInfo)
    end

    function ACF.KillPlayer(Victim, Attacker, Inflictor)
        if not IsValid(Victim) then return end
        if not Victim:IsPlayer() then return end

        -- The damage hook must be trapped to avoid a potential recursive loop
        -- (in theory, I never tested if it could happen, but better safe than sorry...)
        ACF.RunFunctionWhileBlockingBPSeatDamage(DamageFn, Victim, Attacker, Inflictor)

        -- Last chance... if DmgInfo didn't work, just ensure the player died.
        if Victim:Alive() then Victim:Kill() end
    end
end

local ThermalEntities = {}
local ThermalClockTime = CurTime()
local ThermalBase = {
    heat = 0,
    capacity = 0,
    dissipation = 0,
}

function ACF_AddThermalEntity(ent,data)
    if not data then data = {} end
    local id = ent:EntIndex()
    data.id = id
    data.ent = Entity(id)
    table.Inherit( data, ThermalBase )



    ThermalEntities[id] = data

    data.ent:CallOnRemove("Remove_ACFThermal",function() ThermalEntities[id] = nil end)
    --PrintTable(ThermalEntities)

    ACF_ThermalClock()
end

function ACF_ThermalCalc(ent)


    ent.ACF_Temperature = math.Rand(0,1) --(heat / capacity)
end

-- This will go across all of the entities stored in ThermalEntities and update the entry
-- First it will check if the entity is stil valid, removing the entry if it is not
-- After that it will update the heat value in the entry
-- From there it will have the heat decay via radiation, based on the surface area of the object (or 1/3rds radius if surface area returns nil)
function ACF_ThermalClock()
    if CurTime() < ThermalClockTime then return end -- ignore overcalling
    for k,v in pairs(ThermalEntities) do
        if not IsValid(v.ent) then return end
        ACF_ThermalCalc(v.ent)

        -- the final ACF_Temperature is a scale of 0-1 for how "hot" an entity is
        -- primarily used for alterring entity performance and to be pushed to the color proxy on the acf_thermal material
        v.ent:SetNWFloat("ACF_Temperature",v.ent.ACF_Temperature)
    end

    ThermalClockTime = CurTime() + 1
    timer.Simple(1,function() ACF_ThermalClock() end)
end

if CLIENT then
    local ThermalEntFilter = {}
    ThermalEntFilter["prop_physics"] = true
    ThermalEntFilter["acf_engine"] = true
    ThermalEntFilter["acf_gun"] = true
    ThermalEntFilter["acf_gearbox"] = true
    ThermalEntFilter["player"] = true

    hook.Add("NetworkEntityCreated","ACF_ThermalCheck",function(ent)
        if ThermalEntFilter[ent:GetClass()] ~= true then return end
        ent:SetNWVarProxy("ACF_Temperature",function(e,_,_,temp) e.ACF_Temperature = temp end)
    end)
end

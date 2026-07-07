--[[ Shootable / destroyable gadgets for gadget aimbot + silent gadget aim.
    Sources: dump/scripts — StateObject Breakable (cameras, placeables) and Drone Humanoid health.
    Excludes round objectives (Bomb/Defuser) and throwables (grenades).
]]

local M = {}

-- Workspace model names that bullets can destroy or damage
M.SHOOTABLE_MODELS = {
    Drone = true,
    Claymore = true,
    RemoteC4 = true,
    BreachCharge = true,
    HardBreachCharge = true,
    SignalDisruptor = true,
    ProximityAlarm = true,
    StickyCamera = true,
    BulletproofCamera = true,
    DefaultCamera = true,
    BarbedWire = true,
    DeployableShield = true,
    ThermiteCharge = true,
    ShockBattery = true,
    IncendiaryCanister = true,
    NeedleMine = true,
    ToxicCharge = true,
}

M.SHOOTABLE_LABELS = {
    DRONE = true,
    CLAYMORE = true,
    C4 = true,
    BREACH = true,
    ["HARD BREACH"] = true,
    JAMMER = true,
    ["PROX ALARM"] = true,
    ["STICKY CAM"] = true,
    ["BP CAM"] = true,
    ["MAP CAM"] = true,
    ["BARBED WIRE"] = true,
    SHIELD = true,
    THERMITE = true,
    ["SHOCK BAT"] = true,
    ["INC CANISTER"] = true,
    ["NEEDLE MINE"] = true,
    TOXIC = true,
}

local function get_attr(inst, name)
    if not inst or type(inst.GetAttribute) ~= "function" then
        return nil
    end
    return inst:GetAttribute(name)
end

function M.base_label(label)
    if not label then
        return nil
    end
    return label:match("^(.-) %(") or label
end

function M.is_shootable_model(name)
    return name and M.SHOOTABLE_MODELS[name] == true
end

function M.is_shootable_label(label)
    if not label then
        return false
    end
    if M.SHOOTABLE_LABELS[label] then
        return true
    end
    local base = M.base_label(label)
    return base and M.SHOOTABLE_LABELS[base] == true
end

function M.is_shootable_item(item)
    if not item then
        return false
    end
    if M.is_shootable_model(item.name) or M.is_shootable_model(item.model_name) then
        return true
    end
    return M.is_shootable_label(item.label)
end

function M.is_shootable_entry(w)
    if not w or w.is_broken then
        return false
    end

    local model_name = w.kind or (w.item and (w.item.name or w.item.model_name)) or (w.obj and w.obj.Name)
    if M.is_shootable_model(model_name) then
        -- fall through
    elseif not M.is_shootable_label(w.label) then
        return false
    end

    local obj = w.obj
    if obj and get_attr(obj, "BulletImmune") == true then
        return false
    end

    return true
end

return M

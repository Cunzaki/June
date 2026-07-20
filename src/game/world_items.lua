local M = {}

M.world_items = {
    {name = "Bomb", enabled = "bomb_enabled", label = "BOMB", static = true},
    {name = "Defuser", enabled = "defuser_enabled", label = "DEFUSER", static = true},
    {name = "Claymore", enabled = "claymore_enabled", label = "CLAYMORE", priority_part = "Root", dynamic = true},
    {name = "Drone", enabled = "drone_enabled", label = "DRONE", priority_part = "Root", dynamic = true},
    {name = "StunGrenade", enabled = "stun_grenade_enabled", label = "FLASH", priority_part = "Root", dynamic = true},
    {name = "SmokeGrenade", enabled = "smoke_grenade_enabled", label = "SMOKE", priority_part = "Root", dynamic = true},
    {name = "EMPGrenade", enabled = "emp_grenade_enabled", label = "EMP", priority_part = "Root", dynamic = true},
    {name = "ImpactGrenade", enabled = "impact_grenade_enabled", label = "IMPACT", priority_part = "Root", dynamic = true},
    {name = "BreachCharge", enabled = "breach_charge_enabled", label = "BREACH", priority_part = "Root", dynamic = true},
    {name = "RemoteC4", enabled = "remotec4_enabled", label = "C4", priority_part = "Root", dynamic = true},
    {name = "FragGrenade", enabled = "fraggrenade_enabled", label = "FRAG", priority_part = "Root", dynamic = true},
    {name = "StickyCamera", enabled = "stickycamera_enabled", label = "STICKY CAM", anchor_part = "Cam", priority_part = "Root", camera_type = true, dynamic = true},
    {name = "SignalDisruptor", enabled = "signaldisruptor_enabled", label = "JAMMER", priority_part = "Root", dynamic = true},
    {name = "HardBreachCharge", enabled = "hardbreachcharge_enabled", label = "HARD BREACH", priority_part = "Root", dynamic = true},
    {name = "ProximityAlarm", enabled = "proximityalarm_enabled", label = "PROX ALARM", priority_part = "Root", dynamic = true},
    {name = "BarbedWire", enabled = "barbedwire_enabled", label = "BARBED WIRE", priority_part = "Root", dynamic = true},
    {name = "IncendiaryGrenade", enabled = "incendiarygrenade_enabled", label = "INCENDIARY", priority_part = "Root", dynamic = true},
    {name = "IncendiaryCanister", enabled = "incendiary_canister_enabled", label = "INC CANISTER", priority_part = "Root", dynamic = true},
    {name = "BulletproofCamera", enabled = "bulletproofcamera_enabled", label = "BP CAM", anchor_part = "Cam", priority_part = "Root", camera_type = true, dynamic = true},
    {name = "DeployableShield", enabled = "deployableshield_enabled", label = "SHIELD", priority_part = "Root", dynamic = true},
    {name = "ThermiteCharge", enabled = "thermite_charge_enabled", label = "THERMITE", priority_part = "Root", dynamic = true},
    {name = "ShockBattery", enabled = "shock_battery_enabled", label = "SHOCK BAT", priority_part = "Root", dynamic = true},
    {name = "NeedleMine", enabled = "needle_mine_enabled", label = "NEEDLE MINE", priority_part = "Root", dynamic = true},
    {name = "ToxicCharge", enabled = "toxic_charge_enabled", label = "TOXIC", priority_part = "Root", dynamic = true},
    {name = "MetalBarricade", enabled = "metal_barricade_enabled", label = "BARRICADE", priority_part = "Root", dynamic = true},
}

M.camera_items = {
    {
        model_name = "DefaultCamera",
        enabled = "default_camera_enabled",
        label = "MAP CAM",
        color_key = "default_camera_enabled",
        anchor_part = "Cam",
        map_only = true,
        static = true,
    },
}

M.world_items_by_name = {}
for _, item in ipairs(M.world_items) do
    M.world_items_by_name[item.name] = item
    if item.names then
        for _, alias in ipairs(item.names) do
            M.world_items_by_name[alias] = item
        end
    end
end

M.camera_items_by_name = {}
for _, item in ipairs(M.camera_items) do
    M.camera_items_by_name[item.model_name] = item
end

return M

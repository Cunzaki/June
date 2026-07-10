local menu_util = June.require("core.menu_util")

local M = {}

M.TAB = menu_util.TAB
M.menu_items = {
    {g = "Combat", t = "checkbox", id = "aimbot_enabled", n = "Enable Aimbot", v = false, k = 0x72},
    {
        g = "Combat",
        t = "hotkey",
        id = "aimbot_key",
        n = "Aimbot Keybind",
        k = 0x02,
        p = "aimbot_enabled",
        show_mode = false
    },
    {
        g = "Combat",
        t = "combo",
        id = "aimbot_target_type",
        n = "Aimbot Target Type",
        o = {"Crosshair", "Distance"},
        v = 0,
        p = "aimbot_enabled"
    },
    {g = "Combat", t = "checkbox", id = "utilities_aimbot", n = "Utilities Aimbot", v = false, p = "aimbot_enabled"},
    {g = "Combat", t = "checkbox", id = "aimbot_players_priority", n = "Players Over Gadgets", v = false, p = "utilities_aimbot"},
    {
        g = "Combat",
        t = "slider_int",
        id = "utilities_max_distance",
        n = "Utilities Max Distance",
        min = 1,
        max = 250,
        v = 75,
        p = "aimbot_enabled"
    },
    {
        g = "Combat",
        t = "checkbox",
        id = "aimbot_fov_visible",
        n = "Field Of View Circle",
        v = false,
        p = "aimbot_enabled",
        c = {1, 1, 1, 1}
    },
    {
        g = "Combat",
        t = "checkbox",
        id = "aimbot_fov_fill",
        n = "FOV Fill",
        v = false,
        p = "aimbot_fov_visible",
        c = {1, 1, 1, 0.08}
    },
    {
        g = "Combat",
        t = "combo",
        id = "aimbot_fov_style",
        n = "Field Of View Style",
        o = {"Circle", "Filled Circle", "Dotted", "Square", "Filled Square", "Dashed"},
        v = 0,
        p = "aimbot_fov_visible"
    },
    {
        g = "Combat",
        t = "slider_int",
        id = "aimbot_fov",
        n = "Aimbot Field Of View",
        min = 1,
        max = 500,
        v = 125,
        p = "aimbot_enabled"
    },
    {
        g = "Combat",
        t = "slider_int",
        id = "aimbot_smooth",
        n = "Aimbot Smoothing",
        min = 1,
        max = 20,
        v = 5,
        p = "aimbot_enabled"
    },
    {g = "Combat", t = "checkbox", id = "aimbot_prediction", n = "Aimbot Prediction", v = false, p = "aimbot_enabled"},
    {
        g = "Combat",
        t = "slider_int",
        id = "aimbot_prediction_val",
        n = "Prediction Strength",
        min = 0,
        max = 500,
        v = 50,
        p = "aimbot_prediction"
    },
    {
        g = "Combat",
        t = "combo",
        id = "aimbot_bone",
        n = "Aimbot Hitbox",
        o = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Closest"},
        v = 0,
        p = "aimbot_enabled"
    },
    {g = "Combat", t = "checkbox", id = "aimbot_sticky", n = "Sticky Aim", v = false, p = "aimbot_enabled"},
    {g = "Combat", t = "checkbox", id = "aimbot_flick", n = "Flick Mode", v = false, p = "aimbot_enabled"},
    {g = "Combat", t = "checkbox", id = "aimbot_vischeck", n = "Visibility Check", v = false, p = "aimbot_enabled"},
    {
        g = "Combat",
        t = "combo",
        id = "vis_check_priority",
        n = "Vis Check Priority",
        o = {"Distance", "Crosshair"},
        v = 0,
        p = "aimbot_vischeck"
    },
    {g = "Combat", t = "checkbox", id = "aimbot_team_check", n = "Team Check", v = false, p = "aimbot_enabled"},
    {
        g = "Combat",
        t = "checkbox",
        id = "aimbot_target_line",
        n = "Target Line",
        v = false,
        p = "aimbot_enabled",
        c = {1, 0, 0, 1}
    },
    {
        g = "Combat",
        t = "combo",
        id = "target_line_style",
        n = "Target Line Style",
        o = {"Solid", "Dashed", "Dotted"},
        v = 0,
        p = "aimbot_target_line"
    },
    {
        g = "Combat",
        t = "combo",
        id = "target_line_endpoint",
        n = "Target Line Endpoint",
        o = {"Filled Circle", "Outline Circle", "Dot", "Square", "Cross", "None"},
        v = 5,
        p = "aimbot_target_line"
    },
    {
        g = "Combat",
        t = "slider_int",
        id = "aimbot_max_distance",
        n = "Max Distance",
        min = 1,
        max = 500,
        v = 500,
        p = "aimbot_enabled"
    },
    {g = "Combat", t = "separator"},
    {g = "Combat", t = "label", n = "Silent Aim"},
    {g = "Combat", t = "checkbox", id = "silent_aim_enabled", n = "Enable Silent Aim", v = false, k = 0x71},
    {
        g = "Combat",
        t = "combo",
        id = "silent_target_type",
        n = "Silent Target Type",
        o = {"Crosshair", "Distance"},
        v = 0,
        p = "silent_aim_enabled"
    },
    {
        g = "Combat",
        t = "combo",
        id = "silent_bone",
        n = "Silent Hitbox",
        o = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Closest"},
        v = 0,
        p = "silent_aim_enabled"
    },
    {g = "Combat", t = "checkbox", id = "silent_filter_health", n = "Silent Health Check", v = false, p = "silent_aim_enabled"},
    {g = "Combat", t = "checkbox", id = "silent_filter_visible", n = "Silent Visible Only", v = false, p = "silent_aim_enabled"},
    {g = "Combat", t = "checkbox", id = "silent_gadget_aim", n = "Silent Gadget Aim", v = false, p = "silent_aim_enabled"},
    {g = "Combat", t = "checkbox", id = "silent_gadget_team_check", n = "Silent Gadget Team Check", v = false, p = "silent_gadget_aim"},
    {g = "Combat", t = "checkbox", id = "silent_filter_team", n = "Silent Team Check", v = false, p = "silent_aim_enabled"},
    {
        g = "Combat",
        t = "slider_int",
        id = "silent_max_dist",
        n = "Silent Max Distance",
        min = 1,
        max = 500,
        v = 250,
        p = "silent_aim_enabled"
    },
    {
        g = "Combat",
        t = "slider_int",
        id = "silent_fov",
        n = "Silent FOV Radius",
        min = 1,
        max = 500,
        v = 150,
        p = "silent_aim_enabled"
    },
    {g = "Combat", t = "checkbox", id = "silent_sticky", n = "Silent Sticky Target", v = false, p = "silent_aim_enabled"},
    {g = "Combat", t = "checkbox", id = "silent_prediction", n = "Silent Prediction", v = false, p = "silent_aim_enabled"},
    {
        g = "Combat",
        t = "slider_int",
        id = "silent_prediction_val",
        n = "Silent Prediction Strength",
        min = 0,
        max = 500,
        v = 50,
        p = "silent_prediction"
    },
    {
        g = "Combat",
        t = "checkbox",
        id = "silent_draw_fov",
        n = "Silent Draw FOV",
        v = false,
        p = "silent_aim_enabled",
        c = {0.55, 0.2, 1, 1}
    },
    {
        g = "Combat",
        t = "combo",
        id = "silent_fov_style",
        n = "Silent FOV Style",
        o = {"Outline", "Filled Circle"},
        v = 0,
        p = "silent_draw_fov"
    },
    {
        g = "Combat",
        t = "checkbox",
        id = "silent_fov_fill",
        n = "Silent FOV Fill",
        v = false,
        p = "silent_draw_fov",
        c = {0.55, 0.2, 1, 0.08}
    },
    {
        g = "Combat",
        t = "checkbox",
        id = "silent_target_line",
        n = "Silent Target Line",
        v = false,
        p = "silent_aim_enabled",
        c = {1, 0.25, 0.25, 1}
    },
    {g = "Players", t = "checkbox", id = "players_enabled", n = "Enable Player Visuals", v = false, k = 0x73, c = {1, 1, 1, 1}},
    {g = "Players", t = "checkbox", id = "players_box", n = "Player Box", v = true, p = "players_enabled"},
    {
        g = "Players",
        t = "combo",
        id = "box_type",
        n = "Box Type",
        o = {"2D", "Corner", "3D"},
        v = 0,
        p = "players_box"
    },
    {g = "Players", t = "checkbox", id = "box_fill", n = "Box Fill", v = false, p = "players_box"},
    {
        g = "Players",
        t = "slider_int",
        id = "box_fill_opacity",
        n = "Fill Opacity",
        min = 0,
        max = 100,
        v = 25,
        p = "box_fill"
    },
    {
        g = "Players",
        t = "colorpicker",
        id = "box_fill_color",
        n = "Fill Color",
        v = {1, 1, 1, 0.3},
        p = "box_fill"
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_name",
        n = "Player Name",
        v = false,
        p = "players_enabled",
        c = {1, 1, 1, 1}
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_weapon",
        n = "Player Weapon",
        v = false,
        p = "players_enabled",
        c = {1, 0.5, 0.2, 1}
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_distance",
        n = "Player Distance",
        v = false,
        p = "players_enabled",
        c = {0.7, 0.7, 0.7, 1}
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_skeleton",
        n = "Player Skeleton",
        v = false,
        p = "players_enabled",
        c = {1, 0.8, 0.2, 1}
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_head_dot",
        n = "Player Head Dot",
        v = false,
        p = "players_enabled",
        c = {1, 0.8, 0.2, 1}
    },
    {g = "Players", t = "checkbox", id = "players_healthbar", n = "Player Health Bar", v = false, p = "players_enabled"},
    {
        g = "Players",
        t = "checkbox",
        id = "players_view_line",
        n = "Player View Line",
        v = false,
        p = "players_enabled",
        c = {1, 0.8, 0.2, 1}
    },
    {
        g = "Players",
        t = "slider_int",
        id = "view_line_length",
        n = "View Line Length",
        min = 1,
        max = 10,
        v = 5,
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "combo",
        id = "view_line_style",
        n = "View Line Style",
        o = {"Solid", "Dashed", "Fade"},
        v = 0,
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_tracers",
        n = "Player Tracers",
        v = false,
        p = "players_enabled",
        c = {1, 1, 1, 1}
    },
    {
        g = "Players",
        t = "combo",
        id = "tracer_origin",
        n = "Tracer Origin",
        o = {"Bottom", "Center", "Mouse"},
        v = 0,
        p = "players_tracers"
    },
    {
        g = "Players",
        t = "combo",
        id = "tracer_style",
        n = "Tracer Style",
        o = {"Solid", "Dashed", "Dotted"},
        v = 0,
        p = "players_tracers"
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_visible_override",
        n = "Visible Color Override",
        v = false,
        p = "players_enabled",
        c = {0, 1, 0.3, 1}
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_target_override",
        n = "Target Color Override",
        v = false,
        p = "players_enabled",
        c = {1, 0.2, 0.2, 1}
    },
    {g = "Players", t = "checkbox", id = "players_team", n = "Show Teammates", v = false, p = "players_enabled"},
    {g = "Players", t = "separator"},
    {g = "Players", t = "label", n = "Engine Chams"},
    {
        g = "Players",
        t = "multicombo",
        id = "players_engine_chams",
        n = "Player Engine Chams",
        o = {
            "Head",
            "Torso",
            "Left Arm",
            "Right Arm",
            "Left Leg",
            "Right Leg",
            "Left Shoulder",
            "Right Shoulder",
            "Left Hip",
            "Right Hip",
        },
        v = {false, false, false, false, false, false, false, false, false, false},
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "combo",
        id = "players_engine_chams_mode",
        n = "Player Chams Mode",
        o = {"Fill", "Wireframe", "Fill Glow", "Wireframe Glow"},
        v = 0,
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "combo",
        id = "players_engine_chams_color",
        n = "Player Chams Color",
        o = {"Default", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"},
        v = 0,
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "slider_int",
        id = "players_engine_chams_range",
        n = "Player Chams Range",
        min = 1,
        max = 500,
        v = 250,
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_engine_chams_team_check",
        n = "Chams Team Check",
        v = true,
        p = "players_enabled"
    },
    {
        g = "Players",
        t = "checkbox",
        id = "players_engine_chams_vischeck",
        n = "Chams Visibility Check",
        v = false,
        p = "players_enabled"
    },
    {g = "World", t = "checkbox", id = "world_enabled", n = "Enable World Visuals", v = false, k = 0x74},
    {g = "World", t = "checkbox", id = "world_team_check", n = "Gadget Team Check", v = false, p = "world_enabled"},
    {
        g = "World",
        t = "multicombo",
        id = "world_display_options",
        n = "Display Options",
        o = {"Text", "Distance", "3D Box"},
        v = {false, false, false},
        p = "world_enabled"
    },
    {g = "World", t = "separator"},
    {g = "World", t = "label", n = "Engine Chams"},
    {
        g = "World",
        t = "multicombo",
        id = "world_engine_chams",
        n = "World Engine Chams",
        o = {
            "Bomb",
            "Defuser",
            "Claymore",
            "Drone",
            "StunGrenade",
            "SmokeGrenade",
            "EMPGrenade",
            "ImpactGrenade",
            "BreachCharge",
            "RemoteC4",
            "FragGrenade",
            "StickyCamera",
            "SignalDisruptor",
            "HardBreachCharge",
            "ProximityAlarm",
            "BarbedWire",
            "IncendiaryGrenade",
            "IncendiaryCanister",
            "BulletproofCamera",
            "DeployableShield",
            "ThermiteCharge",
            "ShockBattery",
            "NeedleMine",
            "ToxicCharge",
            "MetalBarricade",
            "Map Cam",
        },
        v = {
            false, false, false, false, false, false, false, false, false, false,
            false, false, false, false, false, false, false, false, false, false,
            false, false, false, false, false, false,
        },
        p = "world_enabled"
    },
    {
        g = "World",
        t = "combo",
        id = "world_engine_chams_mode",
        n = "World Chams Mode",
        o = {"Fill", "Wireframe", "Fill Glow", "Wireframe Glow"},
        v = 0,
        p = "world_enabled"
    },
    {
        g = "World",
        t = "combo",
        id = "world_engine_chams_color",
        n = "World Chams Color",
        o = {"Default", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"},
        v = 0,
        p = "world_enabled"
    },
    {
        g = "World",
        t = "slider_int",
        id = "world_engine_chams_range",
        n = "World Chams Range",
        min = 1,
        max = 500,
        v = 250,
        p = "world_enabled"
    },
    {
        g = "World",
        t = "multicombo",
        id = "gadget_aim_blacklist",
        n = "Aimbot Gadget Blacklist",
        o = {"Drone", "Claymore", "C4", "Jammer", "Sticky Cam", "BP Cam", "Map Cam", "Breach", "Hard Breach", "Prox Alarm", "Barbed Wire", "Shield", "Thermite", "Shock Bat", "Inc Canister", "Needle Mine", "Toxic"},
        v = {false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false},
        p = "utilities_aimbot"
    },
    {g = "World", t = "checkbox", id = "bomb_enabled", n = "Bomb", v = false, p = "world_enabled", c = {1, 0.2, 0.2, 1}},
    {
        g = "World",
        t = "checkbox",
        id = "defuser_enabled",
        n = "Defuser",
        v = false,
        p = "world_enabled",
        c = {0.2, 0.8, 1, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "claymore_enabled",
        n = "Claymore",
        v = false,
        p = "world_enabled",
        c = {1, 0.5, 0, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "drone_enabled",
        n = "Drone",
        v = false,
        p = "world_enabled",
        c = {0.5, 1, 0.5, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "default_camera_enabled",
        n = "Map Cameras",
        v = false,
        p = "world_enabled",
        c = {0.8, 0.8, 1, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "stun_grenade_enabled",
        n = "Flash / Stun Grenade",
        v = false,
        p = "world_enabled",
        c = {1, 1, 0, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "breach_charge_enabled",
        n = "Breach Charge",
        v = false,
        p = "world_enabled",
        c = {1, 0.4, 0.4, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "remotec4_enabled",
        n = "Remote C4",
        v = false,
        p = "world_enabled",
        c = {1, 0.2, 0.2, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "fraggrenade_enabled",
        n = "Frag Grenade",
        v = false,
        p = "world_enabled",
        c = {1, 0.6, 0.2, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "stickycamera_enabled",
        n = "Sticky Cameras",
        v = false,
        p = "world_enabled",
        c = {0.5, 0.5, 1, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "signaldisruptor_enabled",
        n = "Signal Disruptor",
        v = false,
        p = "world_enabled",
        c = {0.6, 0.3, 0.9, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "hardbreachcharge_enabled",
        n = "Hard Breach Charge",
        v = false,
        p = "world_enabled",
        c = {1, 0.3, 0.1, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "proximityalarm_enabled",
        n = "Proximity Alarm",
        v = false,
        p = "world_enabled",
        c = {1, 0.8, 0, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "barbedwire_enabled",
        n = "Barbed Wire",
        v = false,
        p = "world_enabled",
        c = {0.6, 0.6, 0.6, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "incendiarygrenade_enabled",
        n = "Incendiary Grenade",
        v = false,
        p = "world_enabled",
        c = {1, 0.4, 0, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "bulletproofcamera_enabled",
        n = "Bulletproof Cameras",
        v = false,
        p = "world_enabled",
        c = {0.3, 0.7, 1, 1}
    },
    {
        g = "World",
        t = "checkbox",
        id = "deployableshield_enabled",
        n = "Deployable Shield",
        v = false,
        p = "world_enabled",
        c = {0.4, 0.4, 0.8, 1}
    },
    {g = "World", t = "checkbox", id = "smoke_grenade_enabled", n = "Smoke Grenade", v = false, p = "world_enabled", c = {0.7, 0.7, 0.7, 1}},
    {g = "World", t = "checkbox", id = "emp_grenade_enabled", n = "EMP Grenade", v = false, p = "world_enabled", c = {0.4, 0.8, 1, 1}},
    {g = "World", t = "checkbox", id = "impact_grenade_enabled", n = "Impact Grenade", v = false, p = "world_enabled", c = {1, 0.5, 0.3, 1}},
    {g = "World", t = "checkbox", id = "thermite_charge_enabled", n = "Thermite Charge", v = false, p = "world_enabled", c = {1, 0.35, 0.1, 1}},
    {g = "World", t = "checkbox", id = "incendiary_canister_enabled", n = "Incendiary Canister", v = false, p = "world_enabled", c = {1, 0.45, 0.1, 1}},
    {g = "World", t = "checkbox", id = "shock_battery_enabled", n = "Shock Battery", v = false, p = "world_enabled", c = {0.3, 0.9, 1, 1}},
    {g = "World", t = "checkbox", id = "needle_mine_enabled", n = "Needle Mine", v = false, p = "world_enabled", c = {0.9, 0.2, 0.9, 1}},
    {g = "World", t = "checkbox", id = "toxic_charge_enabled", n = "Toxic Charge", v = false, p = "world_enabled", c = {0.2, 0.9, 0.3, 1}},
    {g = "World", t = "checkbox", id = "metal_barricade_enabled", n = "Metal Barricade", v = false, p = "world_enabled", c = {0.55, 0.55, 0.55, 1}},
    {
        g = "World",
        t = "slider_int",
        id = "world_max_distance",
        n = "World Max Distance",
        min = 1,
        max = 500,
        v = 250,
        p = "world_enabled"
    },
    {g = "Settings", t = "separator"},
    {g = "Settings", t = "label", n = "Overlay"},
    {g = "Settings", t = "slider_int", id = "font_size_name", n = "Name Font Size", min = 8, max = 24, v = 14},
    {g = "Settings", t = "slider_int", id = "font_size_weapon", n = "Weapon Font Size", min = 8, max = 24, v = 12},
    {g = "Settings", t = "slider_int", id = "font_size_distance", n = "Distance Font Size", min = 8, max = 24, v = 12},
    {g = "Settings", t = "slider_int", id = "font_size_world", n = "World Item Font Size", min = 8, max = 24, v = 14},
    {g = "Settings", t = "checkbox", id = "keybind_window_enabled", n = "Enable Keybind List", v = false},
    {
        g = "Settings",
        t = "checkbox",
        id = "crosshair_enabled",
        n = "Crosshair",
        v = false,
        c = {1, 1, 1, 1}
    },
    {
        g = "Settings",
        t = "combo",
        id = "crosshair_style",
        n = "Crosshair Style",
        o = {"Cross", "Dot", "Circle", "Plus"},
        v = 0,
        p = "crosshair_enabled"
    },
    {
        g = "Settings",
        t = "slider_int",
        id = "crosshair_size",
        n = "Crosshair Size",
        min = 2,
        max = 30,
        v = 8,
        p = "crosshair_enabled"
    },
    {
        g = "Settings",
        t = "slider_int",
        id = "crosshair_gap",
        n = "Crosshair Gap",
        min = 0,
        max = 20,
        v = 3,
        p = "crosshair_enabled"
    },
}

function M.register_all()
    if M._registered then return end
    M._registered = true

    menu_util.ensure_groups()

    local menu_items = M.menu_items

    for _, m in ipairs(menu_items) do
        local opts = {}
        if m.p then
            opts.parent = m.p
        end
        if m.c then
            opts.colorpicker = m.c
        end
        if m.show_mode ~= nil then
            opts.show_mode = m.show_mode
        end
        if m.t == "checkbox" then
            if m.k then
                opts.key = m.k
            end
            menu.add_checkbox(M.TAB, m.g, m.id, m.n, m.v, opts)
        elseif m.t == "combo" then
            menu.add_combo(M.TAB, m.g, m.id, m.n, m.o, m.v, opts)
        elseif m.t == "slider_int" then
            menu.add_slider_int(M.TAB, m.g, m.id, m.n, m.min, m.max, m.v, opts)
        elseif m.t == "slider_float" then
            menu.add_slider_float(M.TAB, m.g, m.id, m.n, m.min, m.max, m.v, opts)
        elseif m.t == "hotkey" then
            menu.add_hotkey(M.TAB, m.g, m.id, m.n, m.k, opts)
        elseif m.t == "multicombo" then
            menu.add_multicombo(M.TAB, m.g, m.id, m.n, m.o, m.v, next(opts) and opts or nil)
        elseif m.t == "colorpicker" then
            menu.add_colorpicker(M.TAB, m.g, m.id, m.n, m.v, opts)
        elseif m.t == "separator" then
            menu.add_separator(M.TAB, m.g)
        elseif m.t == "label" then
            menu.add_label(M.TAB, m.g, m.n)
        end
    end
end

return M

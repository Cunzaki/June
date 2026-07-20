--[[
    June — Project Vector script
    Built: 2026-07-20T05:43:11.332Z
    UI: custom June menu (INSERT) — Vector menu tabs disabled
]]

June = {
    version = "1.1.8",
    debug = false,
    _mods = {},
    bundled = true,
    custom_ui = true,
}

June._menu_tab_ready = true

function June.require(path)
    local mod = June._mods[path]
    if mod == nil then
        error("[June] bundled module missing: " .. path)
    end
    return mod
end


-- ── core/constants.lua ──
June._mods["core.constants"] = (function()
local M = {}

local sqrt, floor, min, max = math.sqrt, math.floor, math.min, math.max
M.sqrt = sqrt
M.floor = floor
M.min = min
M.max = max
M.clamp = function(v, minimum, maximum)
    return v < minimum and minimum or v > maximum and maximum or v
end

local BOX_TYPE = {STANDARD = 0, CORNER = 1, THREE_D = 2}
local AIM_TARGET = {CROSSHAIR = 0, DISTANCE = 1}
local AIM_BONE = {HEAD = 0, TORSO = 1, LEFT_ARM = 2, RIGHT_ARM = 3, LEFT_LEG = 4, RIGHT_LEG = 5, CLOSEST = 6}
local VIEW_LINE_STYLE = {SOLID = 0, DASHED = 1, FADE = 2}
local TARGET_LINE_STYLE = {SOLID = 0, DASHED = 1, DOTTED = 2}
local FOV_STYLE = {CIRCLE = 0, FILLED_CIRCLE = 1, DOTTED = 2, SQUARE = 3, FILLED_SQUARE = 4, DASHED = 5}
local TRACER_ORIGIN = {BOTTOM = 0, CENTER = 1, MOUSE = 2}
local TRACER_STYLE = {SOLID = 0, DASHED = 1, DOTTED = 2}
local DIST = {MIN_PLAYER = 0, MAX_PLAYER_SQ = 250000, HEALTH_CHECK_SQ = 10000, NAME_MATCH_SQ = 400, ESP_HIDE_SQ = 9}
local MIN_BONES_REQUIRED = 5
local HEALTH_CACHE_TIMEOUT = 1.0

M.BOX_TYPE = BOX_TYPE
M.AIM_TARGET = AIM_TARGET
M.AIM_BONE = AIM_BONE
M.VIEW_LINE_STYLE = VIEW_LINE_STYLE
M.TARGET_LINE_STYLE = TARGET_LINE_STYLE
M.FOV_STYLE = FOV_STYLE
M.TRACER_ORIGIN = TRACER_ORIGIN
M.TRACER_STYLE = TRACER_STYLE
M.DIST = DIST
M.MIN_BONES_REQUIRED = MIN_BONES_REQUIRED
M.HEALTH_CACHE_TIMEOUT = HEALTH_CACHE_TIMEOUT

return M

end)()

-- ── core/env.lua ──
June._mods["core.env"] = (function()
local M = {}

function M.has_api(name)
    return _G[name] ~= nil
end

function M.require_apis(names)
    for _, name in ipairs(names) do
        if not M.has_api(name) then
            return false, name
        end
    end
    return true
end

function M.safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

function M.is_valid(inst)
    if not inst or not utility then return false end
    return utility.is_valid(inst)
end

function M.get_workspace()
    if game and game.workspace then return game.workspace end
    if game and game.Workspace then return game.Workspace end
    return M.safe_call(function() return workspace end)
end

function M.get_local_player()
    if entity and entity.get_local_player then
        return entity.get_local_player()
    end
    if game and game.local_player then return game.local_player end
    return nil
end

function M.get_replicated_storage()
    return M.safe_call(function() return game.get_service("ReplicatedStorage") end)
end

return M

end)()

-- ── core/debug.lua ──
June._mods["core.debug"] = (function()
--[[ June debug — off by default. Set June.debug = true for logs. ]]

local M = {}

local seen_errors = {}
local frame_count = 0

function M.enabled()
    return June and June.debug == true
end

function M.verbose()
    return June and June.debug_verbose == true
end

function M.log(msg)
    if not M.enabled() then return end
    print("[June] " .. tostring(msg))
end

function M.warn(msg)
    if not M.enabled() then return end
    print("[June WARN] " .. tostring(msg))
end

function M.warn_once(key, msg)
    M.error_once(key, msg)
end

function M.error_once(key, err)
    key = tostring(key)
    if seen_errors[key] and not M.verbose() then return end
    seen_errors[key] = (seen_errors[key] or 0) + 1
    local count = seen_errors[key]
    local suffix = count > 1 and (" (x" .. count .. ")") or ""
    print("[June ERROR][" .. key .. "] " .. tostring(err) .. suffix)
    if debug and debug.traceback then
        print(debug.traceback(err, 2))
    end
end

function M.guard(key, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        M.error_once(key, a)
        return nil
    end
    return a, b, c
end

function M.tick_frame()
    frame_count = frame_count + 1
end

function M.traceback(err, level)
    if debug and debug.traceback then
        return debug.traceback(err, level or 2)
    end
    return tostring(err)
end

function M.register_frame_hook(fn)
    if type(fn) ~= "function" then
        M.error_once("frame_hook", "on_frame handler is not a function")
        return false
    end

    -- Vector only invokes global on_frame.
    -- callbacks.add / draw.callback stack on reload and draw everything twice.
    _G.on_frame = fn

    if draw then
        draw.callback = nil
    end

    return true
end

return M

end)()

-- ── core/cache.lua ──
June._mods["core.cache"] = (function()
local M = {
    players = {},
    world = {},
    world_lookup = {},
    health_cache = {},
    char_models = {},
    cam_x = 0,
    cam_y = 0,
    cam_z = 0,
    screen_w = 0,
    screen_h = 0,
    ws = nil,
    last_cleanup = 0,
    aim = {current_target = nil, locked_target = nil, last_key_state = false, last_main_key_state = false, last_lmb_state = false},
    toggles = {player = {last = false}, world = {last = false}},
    bone_list = {"head", "torso", "arm1", "arm2", "leg1", "leg2", "shoulder1", "shoulder2", "hip1", "hip2"},
    cham_bone_list = {"head", "torso", "arm1", "arm2", "leg1", "leg2"},
    skeleton_bones = {
        {"head", "torso"},
        {"torso", "shoulder1"},
        {"torso", "shoulder2"},
        {"shoulder1", "arm1"},
        {"shoulder2", "arm2"},
        {"torso", "hip1"},
        {"torso", "hip2"},
        {"hip1", "leg1"},
        {"hip2", "leg2"}
    },
    body_part_names = {
        head = true,
        torso = true,
        arm1 = true,
        arm2 = true,
        leg1 = true,
        leg2 = true,
        shoulder1 = true,
        shoulder2 = true,
        hip1 = true,
        hip2 = true,
        Humanoid = true,
        PlayerHighlight = true,
        Model = true,
        Viewmodel = true,
        LocalViewmodel = true,
        TeammateHighlight = true
    },
    player_history = {},
    draw_frame = 0,
    stats = {
        last_world_scan = 0,
    },
    WORKSPACE_SCAN_MS = 1000,
    WORLD_DYNAMIC_MS = 50,
    WORLD_STATIC_MS = 2500,
    POS_CACHE_MS = 100,
    _last_pos_cache = 0,
}

function M.should_refresh_positions()
    local now = utility and utility.get_tick_count and utility.get_tick_count() or 0
    if now - M._last_pos_cache >= M.POS_CACHE_MS then
        M._last_pos_cache = now
        return true
    end
    return false
end

return M

end)()

-- ── core/vk_names.lua ──
June._mods["core.vk_names"] = (function()
-- Shared VK -> label map (matches custom UI keybind chips).
local M = {}

M.NAMES = {
    [0x01] = "M1", [0x02] = "M2", [0x04] = "M3",
    [0x08] = "BS", [0x09] = "TAB", [0x0D] = "ENT",
    [0x10] = "SHI", [0x11] = "CTL", [0x12] = "ALT",
    [0x14] = "CAP", [0x1B] = "ESC", [0x20] = "SPC",
    [0x25] = "LEFT", [0x26] = "UP", [0x27] = "RIGHT", [0x28] = "DOWN",
    [0x2D] = "INS", [0x2E] = "DEL",
    [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
    [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
    [0x41] = "A", [0x42] = "B", [0x43] = "C", [0x44] = "D", [0x45] = "E",
    [0x46] = "F", [0x47] = "G", [0x48] = "H", [0x49] = "I", [0x4A] = "J",
    [0x4B] = "K", [0x4C] = "L", [0x4D] = "M", [0x4E] = "N", [0x4F] = "O",
    [0x50] = "P", [0x51] = "Q", [0x52] = "R", [0x53] = "S", [0x54] = "T",
    [0x55] = "U", [0x56] = "V", [0x57] = "W", [0x58] = "X", [0x59] = "Y",
    [0x5A] = "Z",
    [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4",
    [0x74] = "F5", [0x75] = "F6", [0x76] = "F7", [0x77] = "F8",
    [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",
}

function M.label(vk)
    vk = tonumber(vk) or 0
    if vk <= 0 then return "none" end
    return M.NAMES[vk] or string.format("%02X", vk)
end

function M.chip(vk)
    return "[" .. M.label(vk) .. "]"
end

return M

end)()

-- ── core/menu_util.lua ──
June._mods["core.menu_util"] = (function()
--[[
    Vector full-mode grid:
      menu.add_group(tab, name)           -> left column, new row
      menu.add_group(tab, name, 0, true) -> right column, same row as previous left
]]

local M = {}

M.TAB = "June"

M.G = {
    COMBAT = "Combat",
    PLAYERS = "Players",
    WORLD = "World",
    SETTINGS = "Settings",
}

M._tab_ready = false
M._groups_ready = false
M._groups = {}

function M.ensure_tab()
    if M._tab_ready then
        return
    end
    if not (June and June._menu_tab_ready) and menu and menu.add_tab then
        menu.add_tab(M.TAB, "J", "full")
    end
    M._tab_ready = true
end

function M.ensure_groups()
    if M._groups_ready then
        return
    end
    M.ensure_tab()

    local rows = {
        { M.G.COMBAT, M.G.PLAYERS },
        { M.G.WORLD, M.G.SETTINGS },
    }

    for _, row in ipairs(rows) do
        menu.add_group(M.TAB, row[1])
        M._groups[row[1]] = true
        if row[2] then
            menu.add_group(M.TAB, row[2], 0, true)
            M._groups[row[2]] = true
        end
    end

    M._groups_ready = true
end

return M

end)()

-- ── core/incremental_scan.lua ──
June._mods["core.incremental_scan"] = (function()
--[[ Time-budgeted scans — spread heavy workspace work across frames. ]]

local debug = June.require("core.debug")

local M = {}

local jobs = {}
local BUDGET_MS = 6
local ITEMS_PER_STEP = 18
local MAX_STARTS_PER_TICK = 1
local starts_this_tick = 0

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

function M.register(id, interval_ms, when_fn, create_state_fn, step_fn, complete_fn, phase_ms)
    jobs[id] = {
        id = id,
        interval = interval_ms,
        last_done = tick_ms() - (interval_ms - (phase_ms or 0)),
        when = when_fn,
        create_state = create_state_fn,
        step = step_fn,
        complete = complete_fn,
        active = false,
        state = nil,
    }
end

function M.force(id)
    local job = jobs[id]
    if not job then
        return
    end
    job.last_done = 0
    job.active = false
    job.state = nil
end

function M.tick()
    starts_this_tick = 0
    local budget_left = BUDGET_MS
    local now = tick_ms()

    for id, job in pairs(jobs) do
        if budget_left <= 0 then
            break
        end

        if job.when then
            local ok, pass = pcall(job.when)
            if not ok or not pass then
                job.active = false
                job.state = nil
                goto continue
            end
        end

        if job.active and job.state then
            while budget_left > 0 do
                local t0 = tick_ms()
                local ok, done = pcall(job.step, job.state, ITEMS_PER_STEP)
                if not ok then
                    debug.warn_once("iscan:" .. id, tostring(done))
                    job.active = false
                    job.state = nil
                    job.last_done = now
                    break
                end

                budget_left = budget_left - (tick_ms() - t0)

                if done then
                    pcall(job.complete, job.state)
                    job.active = false
                    job.state = nil
                    job.last_done = now
                    break
                end

                if budget_left <= 0 then
                    break
                end
            end
        elseif now - job.last_done >= job.interval and starts_this_tick < MAX_STARTS_PER_TICK then
            job.state = job.create_state and job.create_state() or {}
            job.active = true
            starts_this_tick = starts_this_tick + 1
        end

        ::continue::
    end
end

return M

end)()

-- ── game/world_items.lua ──
June._mods["game.world_items"] = (function()
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

end)()

-- ── menu/menu_defs.lua ──
June._mods["menu.menu_defs"] = (function()
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
    {g = "Combat", t = "checkbox", id = "aimbot_vischeck", n = "Visibility Check", v = false, p = "aimbot_enabled"},
    {g = "Combat", t = "checkbox", id = "aimbot_filter_health", n = "Health Check", v = false, p = "aimbot_enabled"},
    {g = "Combat", t = "checkbox", id = "aimbot_gadget_team_check", n = "Gadget Team Check", v = false, p = "utilities_aimbot"},
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
    {g = "Combat", t = "checkbox", id = "silent_players_priority", n = "Silent Players Over Gadgets", v = false, p = "silent_gadget_aim"},
    {
        g = "Combat",
        t = "slider_int",
        id = "silent_gadget_max_distance",
        n = "Silent Gadget Max Distance",
        min = 1,
        max = 250,
        v = 75,
        p = "silent_gadget_aim"
    },
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
        o = {"Circle", "Filled Circle", "Dotted", "Square", "Filled Square", "Dashed"},
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
    {
        g = "Combat",
        t = "combo",
        id = "silent_target_line_style",
        n = "Silent Line Style",
        o = {"Solid", "Dashed", "Dotted"},
        v = 0,
        p = "silent_target_line"
    },
    {
        g = "Combat",
        t = "combo",
        id = "silent_target_line_endpoint",
        n = "Silent Line Endpoint",
        o = {"Filled Circle", "Outline Circle", "Dot", "Square", "Cross", "None"},
        v = 5,
        p = "silent_target_line"
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

end)()

-- ── core/settings.lua ──
June._mods["core.settings"] = (function()
local menu_defs = June.require("menu.menu_defs")
local world_items = June.require("game.world_items")

local M = {}
M.s = {}

local _callbacks = {}

function M.get(id, default)
    if menu and menu.get then
        local v = menu.get(id)
        if v ~= nil then return v end
    end
    return default
end

function M.bool(id, default)
    local v = M.get(id, default)
    if v == false or v == 0 or v == "false" then return false end
    if v == nil then return default == true end
    return v == true or v == 1
end

function M.num(id, default)
    return tonumber(M.get(id, default)) or default or 0
end

local function as_bool(v, default)
    if v == nil then
        return default == true
    end
    if v == true or v == 1 or v == "1" or v == "true" then
        return true
    end
    if v == false or v == 0 or v == "0" or v == "false" then
        return false
    end
    return default == true
end

function M.multi(id, index, default)
    local t = M.get(id)
    if type(t) ~= "table" then
        return default == true
    end
    if t[index] ~= nil then
        return as_bool(t[index], default)
    end
    if index >= 1 and t[index - 1] ~= nil then
        return as_bool(t[index - 1], default)
    end
    return default == true
end

function M.combo_index(id, labels, default)
    default = default or 0
    local v = M.get(id, default)
    if type(v) == "string" then
        local lower = v:lower()
        for i, label in ipairs(labels or {}) do
            if label:lower() == lower then return i - 1 end
        end
        return default
    end
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

function M.color(id, default)
    if menu and menu.get_color then
        local c = menu.get_color(id)
        if c then return c end
    end
    return default or { 1, 1, 1, 1 }
end

function M.on_change(id, fn)
    if not id or not fn then
        return
    end
    _callbacks[id] = _callbacks[id] or {}
    _callbacks[id][#_callbacks[id] + 1] = fn
    if menu and menu.set_callback then
        menu.set_callback(id, function(new_val)
            for _, cb in ipairs(_callbacks[id] or {}) do
                pcall(cb, new_val)
            end
        end)
    end
end

function M.sync_settings()
    local s = M.s
    local menu_items = menu_defs.menu_items
    for _, m in ipairs(menu_items) do
        if not m.id then
            goto continue
        end
        if m.t == "colorpicker" then
            s[m.id] = menu.get(m.id)
        else
            s[m.id] = menu.get(m.id)
            if m.c then
                s[m.id .. "_color"] = menu.get_color(m.id)
            end
        end
        ::continue::
    end
    for _, item in ipairs(world_items.world_items) do
        s[item.enabled .. "_color"] = menu.get_color(item.enabled)
    end
end

return M

end)()

-- ── core/feature_bind.lua ──
June._mods["core.feature_bind"] = (function()
-- Always / Hold / Toggle for feature master checkboxes with attached keys.
local settings = June.require("core.settings")

local M = {}

M.MODES = { "Always", "Hold", "Toggle" }

local registry = {}
local last_down = {}

function M.register(spec)
    if not spec or not spec.id then return end
    local mode_id = spec.mode_id or (spec.id .. "_mode")
    registry[spec.id] = {
        id = spec.id,
        label = spec.label or spec.id,
        mode_id = mode_id,
        key_id = spec.key_id or spec.id,
    }
    if menu and menu.set then
        -- ensure mode value exists
        local cur = settings.get(mode_id, nil)
        if cur == nil then
            pcall(menu.set, mode_id, 2) -- default Toggle
        end
    end
end

function M.is_registered(id)
    return registry[id] ~= nil
end

function M.get_key(id)
    local e = registry[id]
    local key_id = e and e.key_id or id
    if menu and menu.get_key then
        local k = menu.get_key(key_id)
        if k and k > 0 then return k end
    end
    local ok, gs = pcall(function()
        return June.require("ui.gs_state")
    end)
    if ok and gs then
        local k = gs.get_key(key_id)
        if k and k > 0 then return k end
    end
    return 0
end

function M.mode_index(id)
    local e = registry[id]
    if not e then return 2 end
    return settings.combo_index(e.mode_id, M.MODES, 2)
end

function M.armed(id)
    return settings.bool(id, false)
end

function M.active(id)
    if not registry[id] then
        return settings.bool(id, false)
    end
    local mode = M.mode_index(id)
    if mode == 1 then -- Hold
        if not M.armed(id) then return false end
        local key = M.get_key(id)
        if key <= 0 then return false end
        return input and input.is_key_down and input.is_key_down(key)
    end
    return M.armed(id)
end

function M.tick()
    if not input or not input.is_key_down then return end

    for id in pairs(registry) do
        local mode = M.mode_index(id)
        local key = M.get_key(id)

        if mode == 0 or mode == 1 then
            if key > 0 then
                last_down[id] = input.is_key_down(key)
            end
        elseif key > 0 then
            local down = input.is_key_down(key)
            if down and not last_down[id] then
                local cur = settings.bool(id, false)
                if menu and menu.set then
                    pcall(menu.set, id, not cur)
                end
            end
            last_down[id] = down
        end
    end
end

return M

end)()

-- ── core/aim_key.lua ──
June._mods["core.aim_key"] = (function()
-- Aim-key state (Always / Hold / Toggle) separate from feature master toggle.
local settings = June.require("core.settings")

local M = {}

M.MODES = { "Always", "Hold", "Toggle" }

local toggled = {}
local last_down = {}

local function key_store()
    return June.require("ui.gs_state")
end

function M.mode_index(mode_id)
    return settings.combo_index(mode_id, M.MODES, 1) -- default Hold
end

function M.tick(key_id, mode_id)
    if not input or not input.is_key_down then return end
    local mode = M.mode_index(mode_id)
    local vk = key_store().get_key(key_id)
    if mode == 0 then
        if vk > 0 then last_down[key_id] = input.is_key_down(vk) end
        return
    end
    if vk <= 0 then return end
    local down = input.is_key_down(vk)
    if mode == 1 then
        last_down[key_id] = down
        return
    end
    if down and not last_down[key_id] then
        toggled[key_id] = not (toggled[key_id] == true)
    end
    last_down[key_id] = down
end

function M.active(key_id, mode_id)
    local mode = M.mode_index(mode_id)
    if mode == 0 then return true end
    local vk = key_store().get_key(key_id)
    if vk <= 0 then return mode == 0 end
    if mode == 1 then
        return input and input.is_key_down and input.is_key_down(vk)
    end
    return toggled[key_id] == true
end

function M.reset(key_id)
    toggled[key_id] = false
    last_down[key_id] = false
end

return M

end)()

-- ── game/gadget_team.lua ──
June._mods["game.gadget_team"] = (function()
--[[ Gadget ownership — mirrors Util.ownership from game scripts (UserId / Team attributes). ]]

local env = June.require("core.env")

local M = {}

local cached_identity = nil
local cached_identity_at = 0
local IDENTITY_MS = 500

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function get_attr(inst, name)
    if not inst or type(inst.GetAttribute) ~= "function" then
        return nil
    end
    return inst:GetAttribute(name)
end

local function local_identity()
    local now = tick_ms()
    if cached_identity and now - cached_identity_at < IDENTITY_MS then
        return cached_identity
    end

    local lp = env.get_local_player()
    if not lp then
        cached_identity = nil
        cached_identity_at = now
        return nil
    end

    local user_id = lp.user_id or lp.UserId or lp.userid
    local team = lp.team or lp.Team
    local spectator = nil

    if type(lp.GetAttribute) == "function" then
        team = team or lp:GetAttribute("Team")
        spectator = lp:GetAttribute("Spectator")
    end

    local char = lp.character or lp.Character
    if char and type(char.GetAttribute) == "function" then
        team = team or char:GetAttribute("Team")
        if spectator == nil then
            spectator = char:GetAttribute("Spectator")
        end
    end

    cached_identity = {
        user_id = user_id,
        team = team,
        spectator = spectator == true,
    }
    cached_identity_at = now
    return cached_identity
end

function M.ownership_level(obj)
    if not obj then
        return nil
    end

    local gadget_uid = get_attr(obj, "UserId")
    local gadget_team = get_attr(obj, "Team")
    if gadget_uid == nil and gadget_team == nil then
        return nil
    end

    local me = local_identity()
    if not me then
        return nil
    end

    if gadget_uid ~= nil and me.user_id ~= nil and gadget_uid == me.user_id then
        return 3
    end
    if me.spectator then
        return 2
    end
    if gadget_team and me.team and gadget_team == me.team then
        return 2
    end
    return 0
end

function M.is_friendly_gadget(obj)
    local level = M.ownership_level(obj)
    return level == 2 or level == 3
end

return M

end)()

-- ── game/gadget_lifecycle.lua ──
June._mods["game.gadget_lifecycle"] = (function()
--[[ Gadget alive/broken rules derived from game decompiled scripts.
    Cameras: Disabled attribute, Cam/Dot transparency (Breakable/Electronic states).
    Placeables/throwables: leave Workspace when destroyed (Garbage pool).
]]

local env = June.require("core.env")

local M = {}

local CAMERA_MODELS = {
    DefaultCamera = true,
    BulletproofCamera = true,
    StickyCamera = true,
}

local garbage_parent = nil
local objects_parent = nil
local pooled_refs_ready = false

local function is_valid(inst)
    if not inst then
        return false
    end
    if utility and utility.is_valid then
        return utility.is_valid(inst)
    end
    return true
end

local function get_attr(inst, name)
    if not inst or type(inst.GetAttribute) ~= "function" then
        return nil
    end
    return inst:GetAttribute(name)
end

local function part_visible(part)
    if not part or not is_valid(part) then
        return false
    end
    local pos = part.Position or part.position
    if not pos then
        return false
    end
    local tr = part.Transparency
    if tr ~= nil and tr >= 1 then
        return false
    end
    return true
end

local function ensure_pooled_refs()
    if pooled_refs_ready then
        return
    end
    pooled_refs_ready = true
    if game and game.ReplicatedStorage then
        garbage_parent = game.ReplicatedStorage:FindFirstChild("Garbage")
        objects_parent = game.ReplicatedStorage:FindFirstChild("Objects")
    end
end

local function is_pooled(obj)
    local parent = obj and (obj.Parent or obj.parent)
    if not parent then
        return false
    end
    local pname = parent.Name or parent.name or ""
    if pname == "Garbage" or pname == "Objects" then
        return true
    end
    ensure_pooled_refs()
    if garbage_parent and parent == garbage_parent then
        return true
    end
    if objects_parent and parent == objects_parent then
        return true
    end
    return false
end

function M.is_camera_model(name)
    return CAMERA_MODELS[name] == true
end

function M.is_camera_broken(obj, cam_part, dot_part)
    if not is_valid(obj) then
        return true
    end
    if get_attr(obj, "Disabled") == true then
        return true
    end

    local dot = dot_part
    if dot == nil then
        dot = obj:FindFirstChild("Dot")
    end
    if dot and dot.Transparency ~= nil and dot.Transparency >= 1 then
        return true
    end

    local cam = cam_part
    if cam == nil then
        cam = obj:FindFirstChild("Cam")
    end
    if not part_visible(cam) then
        return true
    end

    return false
end

function M.is_map_camera_placed(obj, ws)
    if not is_valid(obj) or is_pooled(obj) then
        return false
    end
    local parent = obj.Parent or obj.parent
    while parent and parent ~= ws do
        if parent.Name == "DefaultCameras" then
            return true
        end
        parent = parent.Parent or parent.parent
    end
    return false
end

function M.is_workspace_placed(obj, ws)
    if not is_valid(obj) or is_pooled(obj) then
        return false
    end
    local parent = obj.Parent or obj.parent
    if ws then
        return parent == ws
    end
    local ws_ref = ws or env.get_workspace()
    return parent and (parent.ClassName == "Workspace" or parent == ws_ref)
end

function M.is_broken(obj, item, anchor_part)
    if not obj then
        return true
    end

    local kind = (item and item.name) or obj.Name
    if M.is_camera_model(kind) then
        local cam = anchor_part
        local dot = nil
        if cam and cam.Name == "Cam" then
            dot = obj:FindFirstChild("Dot")
        end
        return M.is_camera_broken(obj, cam, dot)
    end

    if get_attr(obj, "Disabled") == true then
        return true
    end

    local anchor = anchor_part
    if not anchor or not is_valid(anchor) then
        local anchor_name = (item and (item.anchor_part or item.priority_part)) or "Root"
        anchor = obj:FindFirstChild(anchor_name)
    end
    if anchor and not part_visible(anchor) then
        return true
    end

    return false
end

function M.is_trackable(obj, item, ws, anchor_part)
    if not obj or not item then
        return false
    end
    if item.map_only then
        if not is_valid(obj) or is_pooled(obj) then
            return false
        end
        return not M.is_camera_broken(obj, anchor_part, nil)
    end
    if not M.is_workspace_placed(obj, ws) then
        return false
    end
    return not M.is_broken(obj, item, anchor_part)
end

function M.find_anchor(obj, item)
    if not is_valid(obj) then
        return nil
    end

    local names = {}
    if item then
        if item.anchor_part then
            names[#names + 1] = item.anchor_part
        end
        if item.priority_part and item.priority_part ~= item.anchor_part then
            names[#names + 1] = item.priority_part
        end
    end

    local kind = (item and item.name) or obj.Name
    if M.is_camera_model(kind) then
        names[#names + 1] = "Cam"
        names[#names + 1] = "Dot"
    else
        names[#names + 1] = "Root"
        names[#names + 1] = "Cam"
        names[#names + 1] = "Base"
        names[#names + 1] = "Handle"
        names[#names + 1] = "Primary"
    end

    local seen = {}
    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            local part = obj:FindFirstChild(name)
            if part_visible(part) then
                return part
            end
        end
    end

    if obj.PrimaryPart and part_visible(obj.PrimaryPart) then
        return obj.PrimaryPart
    end

    if obj.GetChildren then
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Part" or cn == "MeshPart" or cn == "UnionOperation" then
                if part_visible(child) then
                    return child
                end
            end
        end
    end

    return nil
end

function M.camera_status_label(obj, base_label, cam_part)
    if not is_valid(obj) then
        return base_label
    end
    if get_attr(obj, "Disabled") == true then
        return base_label .. " (OFF)"
    end
    if M.is_camera_broken(obj, cam_part, nil) then
        return base_label .. " (BROKEN)"
    end
    return base_label
end

return M

end)()

-- ── game/shootable_gadgets.lua ──
June._mods["game.shootable_gadgets"] = (function()
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

end)()

-- ── ui/gs_theme.lua ──
June._mods["ui.gs_theme"] = (function()
-- Neverlose-inspired palette for the draw-only June UI.
local M = {}

M.BG = { 0.039, 0.043, 0.051, 0.99 }
M.BG_INNER = { 0.051, 0.055, 0.067, 1 }
M.PANEL = { 0.067, 0.071, 0.086, 0.99 }
M.PANEL_ALT = { 0.078, 0.084, 0.102, 1 }
M.PANEL_RAISED = { 0.094, 0.102, 0.125, 1 }
M.OVERLAY = { 0.067, 0.071, 0.090, 0.995 }
M.SHADOW = { 0, 0, 0, 0.40 }
M.BORDER = { 0.145, 0.165, 0.205, 1 }
M.BORDER_SOFT = { 0.110, 0.125, 0.155, 1 }
M.BORDER_HOT = { 0.22, 0.42, 0.72, 1 }
M.SIDEBAR = { 0.047, 0.051, 0.063, 1 }
M.SIDEBAR_ACTIVE = { 0.090, 0.145, 0.230, 1 }

M.TEXT = { 0.78, 0.80, 0.86, 1 }
M.TEXT_DIM = { 0.42, 0.46, 0.54, 1 }
M.TEXT_ACTIVE = { 0.96, 0.97, 1.0, 1 }
M.TEXT_TITLE = { 0.70, 0.74, 0.82, 1 }
M.TEXT_SECTION = { 0.38, 0.42, 0.50, 1 }

-- Neverlose sky / royal blue accent
M.ACCENT = { 0.294, 0.549, 0.957, 1 }
M.ACCENT_DIM = { 0.16, 0.30, 0.52, 1 }
M.CHECK_OFF = { 0.14, 0.155, 0.19, 1 }
M.SLIDER_BG = { 0.12, 0.135, 0.165, 1 }
M.BUTTON = { 0.105, 0.115, 0.145, 1 }
M.BUTTON_HOVER = { 0.145, 0.175, 0.230, 1 }
M.HOVER = { 0.12, 0.16, 0.22, 0.85 }
M.FOCUS = { 0.294, 0.549, 0.957, 0.72 }

M.RAINBOW = {
    { 0.294, 0.549, 0.957, 1 },
    { 0.35, 0.75, 0.95, 1 },
    { 0.55, 0.45, 0.95, 1 },
    { 0.95, 0.45, 0.55, 1 },
    { 0.35, 0.90, 0.55, 1 },
}

M.FONT = 13
M.FONT_SMALL = 12
M.FONT_TITLE = 13
M.FONT_CAPTION = 11
M.FONT_BRAND = 16
M.FONT_SECTION = 11

M.WINDOW_W = 900
M.WINDOW_H = 580
M.SIDEBAR_W = 178
M.TAB_H = 34
M.SECTION_GAP = 14
M.SECTION_LABEL_H = 18
M.BRAND_H = 48
M.GROUP_PAD = 12
M.GROUP_GAP = 12
M.GROUP_HEADER_H = 28
M.ROW_H = 28
M.ITEM_GAP = 8
M.LABEL_H = 16
M.LABEL_GAP = 8
M.CTRL_H = 20
M.CTRL_PAD = 4
M.CHECK_SIZE = 13
M.TOGGLE_W = 34
M.TOGGLE_H = 18
M.SLIDER_H = 4
M.STACKED_ROW_H = M.LABEL_H + M.LABEL_GAP + M.CTRL_H + M.CTRL_PAD
M.SLIDER_ROW_H = M.LABEL_H + M.LABEL_GAP + M.SLIDER_H + 12 + M.CTRL_PAD
M.CORNER = 6
M.CORNER_SMALL = 4
M.CORNER_PILL = 9

function M.alpha(col, a)
    return { col[1], col[2], col[3], a }
end

function M.lerp_color(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        a[4] + (b[4] - a[4]) * t,
    }
end

function M.rainbow_at(t)
    local n = #M.RAINBOW
    local x = (t % 1) * n
    local i = math.floor(x) + 1
    local j = (i % n) + 1
    local f = x - math.floor(x)
    return M.lerp_color(M.RAINBOW[i], M.RAINBOW[j], f)
end

return M

end)()

-- ── ui/gs_input.lua ──
June._mods["ui.gs_input"] = (function()
-- Mouse / key helpers. Raw cursor only - no windowed offset correction.
--
-- Wheel: Vector docs only expose utility.mouse_scroll() (inject). There is no
-- documented reader. We probe every known path and accumulate into M.wheel;
-- if none work, the menu keeps edge-hover scroll as fallback.

local M = {}

local prev_keys = {}
local prev_lmb = false
local prev_rmb = false
local prev_mmb = false

M.mx = 0
M.my = 0
M.raw_mx = 0
M.raw_my = 0
M.lmb = false
M.rmb = false
M.mmb = false
M.lmb_click = false
M.rmb_click = false
M.mmb_click = false
M.lmb_release = false
M.wheel = 0
M.wheel_source = nil -- "api" | "uis" | "mouse" | nil
M._wheel_accum = 0
M._scroll_ready = false
M._scroll_hook_tries = 0
M._api_readers = nil
M._game_cursor_hidden = false
M._menu_open = false
M.ui_x, M.ui_y, M.ui_w, M.ui_h = 0, 0, 0, 0

function M.set_ui_rect(x, y, w, h)
    M.ui_x, M.ui_y, M.ui_w, M.ui_h = x, y, w, h
end

function M.set_menu_open(open)
    M._menu_open = open == true
    M.set_game_cursor_visible(not M._menu_open)
end

local function pcall_get_service(name)
    local svc = nil
    if not game then return nil end
    pcall(function()
        if game.GetService then svc = game:GetService(name) end
    end)
    if not svc then
        pcall(function()
            if game.get_service then svc = game:get_service(name) end
        end)
    end
    return svc
end

local function on_wheel(dir, source)
    dir = tonumber(dir) or 0
    if dir == 0 then return end
    -- Normalize to ±1 notches (UIS Position.Z is often ±1).
    if dir > 0 then dir = 1 elseif dir < 0 then dir = -1 end
    M._wheel_accum = (M._wheel_accum or 0) + dir
    if source then M.wheel_source = source end
end

local function connect_signal(signal, fn)
    if not signal then return false end
    local connect = signal.Connect or signal.connect
    if type(connect) ~= "function" then return false end
    local ok = pcall(function()
        connect(signal, fn)
    end)
    return ok == true
end

local function collect_api_readers()
    if M._api_readers then return M._api_readers end
    local readers = {}
    local skip = {
        mouse_scroll = true,
        MouseScroll = true,
        mouseScroll = true,
    }
    local function scan(tbl, label)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "function" and type(k) == "string" then
                local name = k:lower()
                if (name:find("wheel", 1, true) or name:find("scroll", 1, true))
                    and not skip[k]
                    and not name:find("set", 1, true)
                    and not name:find("mouse_scroll", 1, true)
                then
                    readers[#readers + 1] = { fn = v, label = label .. "." .. k }
                end
            end
        end
    end
    pcall(scan, input, "input")
    pcall(scan, utility, "utility")
    M._api_readers = readers
    return readers
end

local function poll_api_readers()
    local readers = collect_api_readers()
    for i = 1, #readers do
        local ok, a, b = pcall(readers[i].fn)
        if ok then
            local v = tonumber(a)
            if (not v or v == 0) and b ~= nil then v = tonumber(b) end
            if v and v ~= 0 then
                on_wheel(v, "api")
                return
            end
        end
    end
end

local function try_hook_uis()
    local uis = pcall_get_service("UserInputService")
    if not uis then return false end

    local function handle(input_obj, _game_processed)
        if not input_obj then return end
        local type_name = nil
        pcall(function()
            local t = input_obj.UserInputType or input_obj.user_input_type
            if type(t) == "userdata" or type(t) == "table" then
                type_name = tostring(t.Name or t.name or t)
            else
                type_name = tostring(t)
            end
        end)
        if not type_name then return end
        local lower = type_name:lower()
        if not lower:find("mousewheel", 1, true) and lower ~= "mousewheel" then
            return
        end
        local z = 0
        pcall(function()
            local pos = input_obj.Position or input_obj.position
            if pos then z = pos.Z or pos.z or 0 end
        end)
        if z == 0 then
            pcall(function()
                z = input_obj.Delta and (input_obj.Delta.Z or input_obj.Delta.z) or 0
            end)
        end
        if z == 0 then z = 1 end
        on_wheel(z, "uis")
    end

    local hooked = false
    if connect_signal(uis.InputChanged or uis.input_changed, handle) then
        hooked = true
    end
    if connect_signal(uis.InputBegan or uis.input_began, handle) then
        hooked = true
    end
    return hooked
end

local function try_hook_player_mouse()
    local lp = nil
    pcall(function()
        if entity and entity.get_local_player then
            lp = entity.get_local_player()
        end
    end)
    if not lp then
        pcall(function()
            lp = game and (game.LocalPlayer or game.local_player)
        end)
    end
    if not lp then return false end

    local mouse = nil
    pcall(function()
        if lp.GetMouse then mouse = lp:GetMouse()
        elseif lp.get_mouse then mouse = lp:get_mouse()
        else mouse = lp.Mouse or lp.mouse
        end
    end)
    if not mouse then return false end

    local hooked = false
    if connect_signal(mouse.WheelForward or mouse.wheel_forward, function()
        on_wheel(1, "mouse")
    end) then
        hooked = true
    end
    if connect_signal(mouse.WheelBackward or mouse.wheel_backward, function()
        on_wheel(-1, "mouse")
    end) then
        hooked = true
    end
    return hooked
end

local function ensure_scroll_hooks()
    if M._scroll_ready then return end
    -- Retry a few frames - LocalPlayer / services may not exist at load.
    M._scroll_hook_tries = (M._scroll_hook_tries or 0) + 1
    if M._scroll_hook_tries > 120 then
        M._scroll_ready = true
        return
    end

    local ok_uis = try_hook_uis()
    local ok_mouse = try_hook_player_mouse()
    collect_api_readers()
    if ok_uis or ok_mouse or M._scroll_hook_tries >= 30 then
        M._scroll_ready = true
    end
end

function M.set_game_cursor_visible(visible)
    local sg = pcall_get_service("StarterGui")
    if sg then
        pcall(function()
            if sg.SetCore then sg:SetCore("MouseIconEnabled", visible) end
        end)
        pcall(function()
            if sg.set_core then sg:set_core("MouseIconEnabled", visible) end
        end)
    end

    local uis = pcall_get_service("UserInputService")
    if uis then
        pcall(function() uis.MouseIconEnabled = visible end)
        pcall(function() uis.mouse_icon_enabled = visible end)
    end

    pcall(function()
        local lp = game and game.local_player
        if not lp then return end
        local mouse = lp.GetMouse and lp:GetMouse() or (lp.get_mouse and lp:get_mouse())
        if not mouse then return end
        if not visible then
            mouse.Icon = "rbxassetid://0"
            if mouse.icon ~= nil then mouse.icon = "rbxassetid://0" end
        else
            mouse.Icon = ""
        end
    end)

    M._game_cursor_hidden = not visible
end

function M.mouse()
    return M.mx, M.my
end

function M.key_down(vk)
    return input and input.is_key_down and input.is_key_down(vk) or false
end

function M.key_pressed(vk)
    local down = M.key_down(vk)
    local was = prev_keys[vk] == true
    prev_keys[vk] = down
    return down and not was
end

function M.begin_frame()
    ensure_scroll_hooks()

    local amx, amy = 0, 0
    if utility and utility.get_mouse_pos then
        amx, amy = utility.get_mouse_pos()
    elseif input and input.get_mouse_pos then
        amx, amy = input.get_mouse_pos()
    elseif input and input.get_mouse_position then
        amx, amy = input.get_mouse_position()
    end
    amx = tonumber(amx) or 0
    amy = tonumber(amy) or 0
    M.raw_mx, M.raw_my = amx, amy
    M.mx, M.my = amx, amy

    M.lmb = M.key_down(0x01)
    M.rmb = M.key_down(0x02)
    M.mmb = M.key_down(0x04)
    M.lmb_click = M.lmb and not prev_lmb
    M.rmb_click = M.rmb and not prev_rmb
    M.mmb_click = M.mmb and not prev_mmb
    M.lmb_release = (not M.lmb) and prev_lmb
    prev_lmb = M.lmb
    prev_rmb = M.rmb
    prev_mmb = M.mmb

    -- Poll any getter-style APIs each frame, then drain event accumulators.
    poll_api_readers()
    M.wheel = M._wheel_accum or 0
    M._wheel_accum = 0
end

function M.hover(x, y, w, h)
    return M.mx >= x and M.my >= y and M.mx <= x + w and M.my <= y + h
end

function M.clicked(x, y, w, h)
    return M.lmb_click and M.hover(x, y, w, h)
end

function M.draw_cursor()
    if not draw then return end
    local show = true
    pcall(function()
        show = June.require("core.settings").bool("june_ui_show_cursor_dot", true)
    end)
    if not show then return end
    local x, y = M.mx, M.my
    local col = { 0.75, 0.15, 0.83, 1 }
    if draw.circle_filled then
        draw.circle_filled(x, y, 4.5, col, 14)
    end
    if draw.circle then
        draw.circle(x, y, 5.5, { 1, 1, 1, 0.9 }, 16, 1.4)
    end
end

return M

end)()

-- ── ui/gs_state.lua ──
June._mods["ui.gs_state"] = (function()
-- Shared settings store for the custom UI (backs menu shim + settings reads).
local M = {}

M.values = {}
M.defaults = {}
M.colors = {}
M.keys = {}
M.callbacks = {}
M.menu_callback = {} -- id -> single fn (menu.set_callback replaces)
M.buttons = {}
M.visible = {} -- id -> bool (parent gating); nil means visible

local function copy_table(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

function M.define(id, default)
    if id == nil then return end
    if M.defaults[id] == nil then
        M.defaults[id] = copy_table(default)
    end
    if M.values[id] == nil then
        M.values[id] = copy_table(default)
    end
end

function M.get(id, fallback)
    local v = M.values[id]
    if v == nil then
        return fallback
    end
    return v
end

local function fire_change(id, value)
    local menu_cb = M.menu_callback[id]
    if menu_cb then
        pcall(menu_cb, value)
    end
    local cbs = M.callbacks[id]
    if cbs then
        for i = 1, #cbs do
            pcall(cbs[i], value)
        end
    end
end

function M.set(id, value)
    if id == nil then return end
    M.values[id] = value
    fire_change(id, value)
end

function M.toggle(id)
    local v = not M.get(id, false)
    M.set(id, v)
    return v
end

function M.define_color(id, color)
    if id == nil then return end
    if M.colors[id] == nil then
        M.colors[id] = copy_table(color or { 1, 1, 1, 1 })
    end
end

function M.get_color(id, fallback)
    return M.colors[id] or fallback or { 1, 1, 1, 1 }
end

function M.set_color(id, color)
    if id == nil or type(color) ~= "table" then return end
    M.colors[id] = copy_table(color)
    fire_change(id, color)
end

function M.get_key(id)
    return tonumber(M.keys[id]) or 0
end

function M.set_key(id, vk)
    if id == nil then return end
    M.keys[id] = tonumber(vk) or 0
end

function M.on_change(id, fn)
    if not id or not fn then return end
    M.callbacks[id] = M.callbacks[id] or {}
    M.callbacks[id][#M.callbacks[id] + 1] = fn
end

function M.set_menu_callback(id, fn)
    if id then
        M.menu_callback[id] = fn
    end
end

function M.set_button(id, fn)
    if id then
        M.buttons[id] = fn
    end
end

function M.fire_button(id)
    local fn = M.buttons[id]
    if fn then
        pcall(fn)
        return true
    end
    return false
end

function M.set_visible(id, show)
    if id then
        M.visible[id] = show and true or false
    end
end

function M.is_visible(id)
    local v = M.visible[id]
    if v == nil then return true end
    return v
end

function M.reset(id)
    local d = M.defaults[id]
    if d == nil then return end
    M.set(id, copy_table(d))
end

return M

end)()

-- ── ui/gs_anim.lua ──
June._mods["ui.gs_anim"] = (function()
-- Animated accent bars + per-element theme sync for the custom UI.
local theme = June.require("ui.gs_theme")

local M = {}

M.MODES = { "Static", "Rainbow", "Pulse", "Wave", "Flow" }
M.MODES_UI = { "Default", "Static", "Rainbow", "Pulse", "Wave", "Flow" }

M.TARGET_TITLE = 1
M.TARGET_SECTION = 2
M.TARGET_SLIDER = 3
M.TARGET_SCROLL = 4
M.TARGET_SIDEBAR = 5
M.TARGET_CHECKBOX = 6
M.TARGET_HOVER = 7
M.TARGET_OVERLAY = 8

M.STYLE_TITLE = "june_ui_style_title"
M.STYLE_SECTION = "june_ui_style_section"
M.STYLE_SLIDER = "june_ui_style_slider"
M.STYLE_SCROLL = "june_ui_style_scroll"
M.STYLE_SIDEBAR = "june_ui_style_sidebar"
M.STYLE_CHECKBOX = "june_ui_style_checkbox"
M.STYLE_OVERLAY = "june_ui_style_overlay"

M.COL_TITLE = "june_ui_col_title"
M.COL_SECTION = "june_ui_col_section"
M.COL_SLIDER = "june_ui_col_slider"
M.COL_SCROLL = "june_ui_col_scroll"
M.COL_SIDEBAR = "june_ui_col_sidebar"
M.COL_CHECKBOX = "june_ui_col_checkbox"
M.COL_OVERLAY = "june_ui_col_overlay"

local DEFAULT_ACCENT = { 0.294, 0.549, 0.957, 1 }
local transitions = {}

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

function M.lerp(a, b, t)
    t = clamp(t or 0, 0, 1)
    return a + (b - a) * t
end

function M.ease_out_cubic(t)
    t = clamp(t or 0, 0, 1)
    local q = 1 - t
    return 1 - q * q * q
end

-- Persistent transition value for hover/active UI elements.
function M.transition(id, target, rate)
    local now = M.now()
    local entry = transitions[id]
    if not entry then
        entry = { value = target and 1 or 0, at = now }
        transitions[id] = entry
        return entry.value
    end
    local dt = math.min(math.max(now - (entry.at or now), 0), 0.1)
    entry.at = now
    local goal = target and 1 or 0
    local speed = rate or 12
    local alpha = 1 - math.exp(-speed * dt)
    entry.value = M.lerp(entry.value or 0, goal, alpha)
    return entry.value
end

function M.mix(a, b, t)
    return theme.lerp_color(a, b, clamp(t or 0, 0, 1))
end

local function settings()
    return June.require("core.settings")
end

local function hsv_to_rgb(h, s, v)
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

function M.now()
    if utility and utility.get_time then
        return utility.get_time()
    end
    return 0
end

function M.speed()
    local n = settings().num("june_ui_anim_speed", 40)
    return clamp(n, 1, 100) * 0.028
end

function M.phase()
    return M.now() * M.speed()
end

function M.colors_enabled()
    return settings().bool("june_ui_custom_colors", false)
end

function M.anim_enabled()
    return settings().bool("june_ui_custom_anim", false)
end

function M.global_mode()
    local n = tonumber(settings().get("june_ui_accent_anim", 1)) or 1
    return clamp(math.floor(n + 0.5), 0, #M.MODES - 1)
end

function M.resolve_mode(style_id)
    if not M.anim_enabled() then
        return 0
    end
    local pick = settings().combo_index(style_id, M.MODES_UI, 0)
    if pick == 0 then
        return M.global_mode()
    end
    return pick - 1
end

function M.base_accent()
    if not M.colors_enabled() then
        return DEFAULT_ACCENT
    end
    return settings().color("june_ui_accent", DEFAULT_ACCENT)
end

function M.color_override_enabled(target_index)
    if not M.colors_enabled() then
        return false
    end
    return settings().multi("june_ui_color_overrides", target_index, false)
end

function M.element_color(target_index, color_id)
    if M.color_override_enabled(target_index) then
        return settings().color(color_id, M.base_accent())
    end
    return M.base_accent()
end

function M.anim_target_enabled(target_index)
    if not M.anim_enabled() then
        return false
    end
    return settings().multi("june_ui_anim_targets", target_index, true)
end

function M.sync_theme()
    local col = M.base_accent()
    theme.ACCENT = { col[1], col[2], col[3], col[4] or 1 }
    local pulse = 0.62 + 0.38 * math.sin(M.phase() * 2.2)
    theme.ACCENT_DIM = {
        col[1] * pulse * 0.55,
        col[2] * pulse * 0.55,
        col[3] * pulse * 0.55,
        1,
    }
end

function M.accent_at_mode(mode, base, t, alpha)
    alpha = alpha or 1
    local phase = M.phase()
    t = (t or 0) % 1

    if mode == 0 then
        return { base[1], base[2], base[3], alpha }
    end
    if mode == 1 then
        local hue = (t + phase * 0.14) % 1
        local r, g, b = hsv_to_rgb(hue, 1, 1)
        return { r, g, b, alpha }
    end
    if mode == 2 then
        local p = 0.5 + 0.5 * math.sin(phase * 2.4 + t * 6.28318)
        return { base[1] * p, base[2] * p, base[3] * p, alpha }
    end
    if mode == 3 then
        local w = 0.45 + 0.55 * math.sin((t * 10 - phase * 2.8) * 6.28318)
        return {
            base[1] * (0.55 + 0.45 * w),
            base[2] * (0.55 + 0.45 * w),
            base[3] * (0.55 + 0.45 * w),
            alpha,
        }
    end
    local sweep_h = (t + phase * 0.18) % 1
    local sr, sg, sb = hsv_to_rgb(sweep_h, 1, 1)
    local mix = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 6.28318 + phase * 1.6))
    local c = theme.lerp_color(base, { sr, sg, sb, 1 }, mix)
    return { c[1], c[2], c[3], alpha }
end

function M.accent_at(t, alpha)
    return M.accent_at_mode(M.global_mode(), M.base_accent(), t, alpha)
end

local function widget_clip()
    local clip = nil
    pcall(function()
        clip = June.require("ui.gs_widgets").clip
    end)
    return clip
end

function M.rect(x, y, w, h, col, filled)
    if not draw then return end
    local c = widget_clip()
    if c then
        local x2, y2 = x + w, y + h
        local cx, cy = c.x, c.y
        local cx2, cy2 = c.x + c.w, c.y + c.h
        if x2 <= cx or y2 <= cy or x >= cx2 or y >= cy2 then return end
        if x < cx then w = w - (cx - x); x = cx end
        if y < cy then h = h - (cy - y); y = cy end
        if x + w > cx2 then w = cx2 - x end
        if y + h > cy2 then h = cy2 - y end
        if w <= 0 or h <= 0 then return end
    end
    if filled then
        draw.rect_filled(x, y, w, h, col, 0)
    else
        draw.rect(x, y, w, h, col, 0, 1)
    end
end

function M.draw_bar_h(x, y, w, h, scroll_t, style_id, color_id, color_target)
    if w <= 0 or h <= 0 then return end
    scroll_t = scroll_t or 0
    local base = M.element_color(color_target, color_id)
    local mode = M.resolve_mode(style_id)
    if mode == 0 then
        M.rect(x, y, w, h, base, true)
        return
    end
    local segs = math.max(16, math.floor(w / 4))
    local sw = w / segs
    for i = 0, segs - 1 do
        local t = (i / segs + scroll_t) % 1
        M.rect(x + i * sw, y, sw + 0.75, h, M.accent_at_mode(mode, base, t, 1), true)
    end
end

function M.draw_bar_v(x, y, w, h, scroll_t, style_id, color_id, color_target)
    if w <= 0 or h <= 0 then return end
    scroll_t = scroll_t or 0
    local base = M.element_color(color_target, color_id)
    local mode = M.resolve_mode(style_id)
    if mode == 0 then
        M.rect(x, y, w, h, base, true)
        return
    end
    local segs = math.max(8, math.floor(h / 4))
    local sh = h / segs
    for i = 0, segs - 1 do
        local t = (i / segs + scroll_t) % 1
        M.rect(x, y + i * sh, w, sh + 0.75, M.accent_at_mode(mode, base, t, 1), true)
    end
end

function M.draw_flat(x, y, w, h, style_id, color_id, color_target)
    local base = M.element_color(color_target, color_id)
    M.rect(x, y, w, h, base, true)
end

function M.section_scroll()
    return M.phase() * 0.09
end

function M.draw_section_top(x, y, w)
    if not M.anim_target_enabled(M.TARGET_SECTION) then
        M.draw_flat(x, y, w, 2, M.STYLE_SECTION, M.COL_SECTION, M.TARGET_SECTION)
        return
    end
    M.draw_bar_h(x, y, w, 2, M.section_scroll(), M.STYLE_SECTION, M.COL_SECTION, M.TARGET_SECTION)
end

function M.draw_title_bar(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_TITLE) then
        M.draw_flat(x, y, w, h, M.STYLE_TITLE, M.COL_TITLE, M.TARGET_TITLE)
        return
    end
    M.draw_bar_h(x, y, w, h, M.phase() * 0.12, M.STYLE_TITLE, M.COL_TITLE, M.TARGET_TITLE)
end

function M.draw_slider_fill(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_SLIDER) then
        M.draw_flat(x, y, w, h, M.STYLE_SLIDER, M.COL_SLIDER, M.TARGET_SLIDER)
        return
    end
    M.draw_bar_h(x, y, w, h, M.phase() * 0.06, M.STYLE_SLIDER, M.COL_SLIDER, M.TARGET_SLIDER)
end

function M.draw_scroll_thumb(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_SCROLL) then
        M.draw_flat(x, y, w, h, M.STYLE_SCROLL, M.COL_SCROLL, M.TARGET_SCROLL)
        return
    end
    M.draw_bar_v(x, y, w, h, M.phase() * 0.05, M.STYLE_SCROLL, M.COL_SCROLL, M.TARGET_SCROLL)
end

function M.draw_tab_indicator(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_SIDEBAR) then
        M.draw_flat(x, y, w, h, M.STYLE_SIDEBAR, M.COL_SIDEBAR, M.TARGET_SIDEBAR)
        return
    end
    M.draw_bar_v(x, y, w, h, M.phase() * 0.07, M.STYLE_SIDEBAR, M.COL_SIDEBAR, M.TARGET_SIDEBAR)
end

function M.tab_icon_color()
    local base = M.element_color(M.TARGET_SIDEBAR, M.COL_SIDEBAR)
    if not M.anim_target_enabled(M.TARGET_SIDEBAR) then
        return base
    end
    return M.accent_at_mode(M.resolve_mode(M.STYLE_SIDEBAR), base, M.phase() * 0.03, 1)
end

function M.hover_tint(base, hot)
    if not hot then return base end
    if not M.anim_target_enabled(M.TARGET_HOVER) then
        return base
    end
    local pulse = 0.88 + 0.12 * math.sin(M.phase() * 6)
    return {
        base[1] * pulse,
        base[2] * pulse,
        base[3] * pulse,
        base[4] or 1,
    }
end

function M.interactive_fill(id, base, hover, active)
    local h = M.transition("hover:" .. tostring(id), hover, 15)
    local a = M.transition("active:" .. tostring(id), active, 20)
    local col = M.mix(base, hover and theme.BUTTON_HOVER or theme.HOVER, M.ease_out_cubic(h))
    return M.mix(col, M.element_color(M.TARGET_CHECKBOX, M.COL_CHECKBOX), a * 0.16)
end

function M.checkbox_fill()
    local base = M.element_color(M.TARGET_CHECKBOX, M.COL_CHECKBOX)
    if not M.anim_target_enabled(M.TARGET_CHECKBOX) then
        return base
    end
    return M.accent_at_mode(M.resolve_mode(M.STYLE_CHECKBOX), base, M.phase() * 0.04, 1)
end

function M.menu_fade()
    if not M.colors_enabled() or not settings().bool("june_ui_menu_fade", false) then
        return 1
    end
    return clamp(0.86 + math.sin(M.now() * 0.001) * 0.02, 0.86, 1)
end

function M.panel_bg()
    if not M.colors_enabled() then
        return theme.BG
    end
    local dim = settings().num("june_ui_bg_dim", 0)
    dim = clamp(dim, 0, 40) * 0.01
    local bg = theme.BG
    return {
        bg[1] - dim * 0.04,
        bg[2] - dim * 0.04,
        bg[3] - dim * 0.04,
        bg[4] or 1,
    }
end

return M

end)()

-- ── ui/menu_shim.lua ──
June._mods["ui.menu_shim"] = (function()
--[[
  Replaces Vector's menu.* API with a store backed by ui.gs_state.
  Feature register_menu() code keeps working; nothing is added to the Vector UI.
]]

local state = June.require("ui.gs_state")

local M = {}
M.installed = false
M._real = nil

local function as_bool_default(default)
    return default == true
end

local shim = {}

function shim.add_tab() end
function shim.add_group() end
function shim.add_separator() end
function shim.add_label() end

function shim.add_checkbox(_T, _G, id, _label, default, opts)
    state.define(id, as_bool_default(default))
    opts = opts or {}
    if opts.colorpicker then
        state.define_color(id, opts.colorpicker)
    end
    if opts.key and opts.key ~= 0 then
        if state.get_key(id) == 0 then
            state.set_key(id, opts.key)
        end
    end
end

function shim.add_slider_int(_T, _G, id, _label, _min, _max, default, _opts)
    -- Some call sites pass format string as 8th arg then opts
    state.define(id, tonumber(default) or 0)
end

function shim.add_slider_float(_T, _G, id, _label, _min, _max, default, _fmt, _opts)
    state.define(id, tonumber(default) or 0)
end

function shim.add_combo(_T, _G, id, _label, _options, default, _opts)
    state.define(id, tonumber(default) or 0)
end

function shim.add_multicombo(_T, _G, id, _label, options, defaults, _opts)
    local def = {}
    local n = type(options) == "table" and #options or 0
    for i = 1, n do
        def[i] = defaults and defaults[i] == true
    end
    state.define(id, def)
end

function shim.add_colorpicker(_T, _G, id, _label, default, _opts)
    state.define_color(id, default or { 1, 1, 1, 1 })
    -- Also mirror as value for config dumps that read get()
    state.define(id, default or { 1, 1, 1, 1 })
end

function shim.add_input(_T, _G, id, _label, default)
    state.define(id, default or "")
end

function shim.add_button(_T, _G, id, _label, callback)
    if type(callback) == "function" then
        state.set_button(id, callback)
    end
end

function shim.add_hotkey(_T, _G, id, _label, default_vk, opts)
    opts = opts or {}
    if default_vk and default_vk ~= 0 and state.get_key(id) == 0 then
        state.set_key(id, default_vk)
    end
    local mode_id = id .. "_mode"
    state.define(mode_id, opts.default_mode or opts.mode_default or 1)
end

function shim.get(id)
    return state.get(id, nil)
end

function shim.set(id, value)
    state.set(id, value)
end

function shim.get_color(id)
    return state.get_color(id, nil)
end

function shim.set_color(id, color)
    state.set_color(id, color)
end

function shim.get_key(id)
    return state.get_key(id)
end

function shim.set_key(id, vk)
    state.set_key(id, vk)
end

function shim.set_callback(id, fn)
    state.set_menu_callback(id, fn)
end

function shim.set_visible(id, show)
    state.set_visible(id, show)
end

-- PascalCase / camelCase aliases (Vector registers all three styles)
local aliases = {
    AddTab = "add_tab",
    AddGroup = "add_group",
    AddSeparator = "add_separator",
    AddLabel = "add_label",
    AddCheckbox = "add_checkbox",
    AddSliderInt = "add_slider_int",
    AddSliderFloat = "add_slider_float",
    AddCombo = "add_combo",
    AddMulticombo = "add_multicombo",
    AddColorpicker = "add_colorpicker",
    AddInput = "add_input",
    AddButton = "add_button",
    AddHotkey = "add_hotkey",
    Get = "get",
    Set = "set",
    GetColor = "get_color",
    SetColor = "set_color",
    GetKey = "get_key",
    SetKey = "set_key",
    SetCallback = "set_callback",
    SetVisible = "set_visible",
    addTab = "add_tab",
    addGroup = "add_group",
    addCheckbox = "add_checkbox",
    addSliderInt = "add_slider_int",
    addSliderFloat = "add_slider_float",
    addCombo = "add_combo",
    addMulticombo = "add_multicombo",
    addColorpicker = "add_colorpicker",
    addInput = "add_input",
    addButton = "add_button",
    addHotkey = "add_hotkey",
    getColor = "get_color",
    setColor = "set_color",
    getKey = "get_key",
    setKey = "set_key",
    setCallback = "set_callback",
    setVisible = "set_visible",
}

for alias, real in pairs(aliases) do
    shim[alias] = shim[real]
end

function M.install()
    if M.installed then return true end
    -- Vector sandbox has no rawget; keep a reference then replace the global.
    M._real = menu
    if June then
        June._vector_menu = M._real
        June.custom_ui = true
    end
    menu = shim
    M.installed = true
    return true
end

function M.api()
    return shim
end

return M

end)()

-- ── ui/gs_icons.lua ──
June._mods["ui.gs_icons"] = (function()
-- Clean Neverlose-style monoline sidebar icons.
local theme = June.require("ui.gs_theme")

local M = {}

local function line(x1, y1, x2, y2, col, t)
    if draw and draw.line then
        draw.line(x1, y1, x2, y2, col, t or 1.8)
    end
end

local function circle(x, y, r, col, filled, segs)
    if not draw then return end
    segs = segs or 22
    if filled and draw.circle_filled then
        draw.circle_filled(x, y, r, col, segs)
    elseif draw.circle then
        draw.circle(x, y, r, col, segs, 1.8)
    end
end

local function rect(x, y, w, h, col, filled, round)
    if not draw then return end
    if filled then
        draw.rect_filled(x, y, w, h, col, round or 0)
    else
        draw.rect(x, y, w, h, col, round or 0, 1.6)
    end
end

function M.draw(name, cx, cy, col)
    col = col or theme.TEXT
    local t = 1.85

    if name == "aim" then
        -- Compact crosshair (Neverlose-like)
        circle(cx, cy, 6.2, col, false, 24)
        circle(cx, cy, 1.35, col, true, 10)
        line(cx - 10, cy, cx - 5.2, cy, col, t)
        line(cx + 5.2, cy, cx + 10, cy, col, t)
        line(cx, cy - 10, cx, cy - 5.2, col, t)
        line(cx, cy + 5.2, cx, cy + 10, col, t)

    elseif name == "visuals" then
        -- Eye with pupil
        circle(cx, cy, 3.2, col, false, 16)
        circle(cx + 0.7, cy - 0.5, 1.15, col, true, 10)
        -- lids as gentle arcs via short polylines
        local top, bot = {}, {}
        for i = 0, 10 do
            local a = -math.pi + (math.pi * i / 10)
            top[#top + 1] = { cx + math.cos(a) * 8.2, cy + math.sin(a) * 4.0 }
            bot[#bot + 1] = { cx + math.cos(a) * 8.2, cy - math.sin(a) * 4.0 }
        end
        if draw and draw.poly then
            draw.poly(top, col, t)
            draw.poly(bot, col, t)
        else
            for i = 1, #top - 1 do
                line(top[i][1], top[i][2], top[i + 1][1], top[i + 1][2], col, t)
                line(bot[i][1], bot[i][2], bot[i + 1][1], bot[i + 1][2], col, t)
            end
        end

    elseif name == "world" then
        -- Globe
        circle(cx, cy, 7.2, col, false, 26)
        -- equator
        local eq = {}
        for i = 0, 16 do
            local a = (i / 16) * math.pi * 2
            eq[#eq + 1] = { cx + math.cos(a) * 7.2, cy + math.sin(a) * 2.6 }
        end
        if draw and draw.poly then
            draw.poly(eq, col, 1.55)
        end
        -- meridian
        local mer = {}
        for i = 0, 16 do
            local a = (i / 16) * math.pi * 2
            mer[#mer + 1] = { cx + math.sin(a) * 2.6, cy + math.cos(a) * 7.2 }
        end
        if draw and draw.poly then
            draw.poly(mer, col, 1.55)
        else
            line(cx, cy - 7.2, cx, cy + 7.2, col, 1.5)
        end

    elseif name == "misc" then
        -- Three horizontal sliders (settings)
        for i = 0, 2 do
            local yy = cy - 6.5 + i * 6.5
            line(cx - 8, yy, cx + 8, yy, col, 1.55)
            local knob = ({ -3.5, 3.2, -0.5 })[i + 1]
            circle(cx + knob, yy, 2.35, col, true, 12)
        end

    elseif name == "config" then
        -- Clean gear
        local teeth = 8
        for i = 0, teeth - 1 do
            local a = (i / teeth) * math.pi * 2 + 0.2
            local c, s = math.cos(a), math.sin(a)
            local x1, y1 = cx + c * 3.4, cy + s * 3.4
            local x2, y2 = cx + c * 7.4, cy + s * 7.4
            local px, py = -s * 1.35, c * 1.35
            if draw and draw.poly then
                draw.poly({
                    { x1 + px, y1 + py },
                    { x2 + px * 0.65, y2 + py * 0.65 },
                    { x2 - px * 0.65, y2 - py * 0.65 },
                    { x1 - px, y1 - py },
                }, col, 1.45)
            else
                line(x1, y1, x2, y2, col, 1.6)
            end
        end
        circle(cx, cy, 3.6, col, false, 18)
        circle(cx, cy, 1.55, col, true, 10)

    else
        circle(cx, cy, 4, col, false)
    end
end

return M

end)()

-- ── ui/gs_widgets.lua ──
June._mods["ui.gs_widgets"] = (function()
-- Gamesense-style widgets (draw API) backed by ui.gs_state.
local theme = June.require("ui.gs_theme")
local input = June.require("ui.gs_input")
local state = June.require("ui.gs_state")
local anim = June.require("ui.gs_anim")

local M = {}

M.active_slider = nil
M.active_input = nil
M.open_combo = nil
M.open_multi = nil
M.open_color = nil
M.listening_key = nil
M.drag_offset_x = 0
M.drag_offset_y = 0
M.dragging_window = false
M.clip = nil -- { x, y, w, h }
M.popup_used_click = false -- set when a popup consumes this frame's click
M.interacted = false -- any widget captured LMB this frame
M._hue_cache = {} -- id -> hue 0..1 for color picker
M._list_scroll = {} -- id -> first visible option index (0-based)
M.LIST_MAX_VISIBLE = 8
M.wheel_consumed = false -- set when a dropdown/list eats the wheel this frame
M.block_under = false -- true while pointer is over a floating popup (prior frame rect)
-- Floating color picker (drawn after the menu so it doesn't expand sections)
M._color_anchor = nil -- { id, x, y, w }
M._color_hit = nil -- { x, y, w, h } last drawn picker rect
M.open_bind_mode = nil -- keybind id whose Always/Hold/Toggle menu is open
M._bind_mode_anchor = nil -- { id, x, y, w }
M._bind_mode_hit = nil
M._active_input_rect = nil -- { x, y, w, h } for click-outside blur
M._input_repeat_at = 0
M._input_repeat_vk = nil

local LISTEN_SKIP = {
    [0x01] = true, -- LMB used for UI
}

local function listen_skip_vk(vk)
    if LISTEN_SKIP[vk] then return true end
    local menu_vk = state.get_key("june_ui_menu_key")
    if not menu_vk or menu_vk == 0 then menu_vk = 0x2D end
    return vk == menu_vk
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function text_w(str, size)
    if draw and draw.get_text_size then
        local w = draw.get_text_size(str, size or theme.FONT)
        if type(w) == "number" then return w end
    end
    return #(tostring(str or "")) * 7
end

local function in_clip(y, h)
    local c = M.clip
    if not c then return true end
    return y >= c.y and y + h <= c.y + c.h
end

local function stacked_metrics(y)
    local label_y = y + 3
    local ctrl_y = y + theme.LABEL_H + theme.LABEL_GAP
    return label_y, ctrl_y, theme.CTRL_H, theme.STACKED_ROW_H
end

local function interactive(x, y, w, h)
    if M.block_under then return false end
    if not in_clip(y, h) then return false end
    local c = M.clip
    if c and not input.hover(c.x, c.y, c.w, c.h) then
        return false
    end
    return true
end

local function ui_clicked(x, y, w, h)
    if M.block_under then return false end
    return input.clicked(x, y, w, h)
end

local function ui_rmb_clicked(x, y, w, h)
    if M.block_under then return false end
    return input.rmb_click and input.hover(x, y, w, h)
end

local function rgb_to_hsv(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local d = max - min
    local h = 0
    if d > 1e-6 then
        if max == r then
            h = ((g - b) / d) % 6
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
        if h < 0 then h = h + 1 end
    end
    local s = max <= 1e-6 and 0 or (d / max)
    return h, s, max
end

local function hsv_to_rgb(h, s, v)
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

function M.begin_popups()
    M.popup_used_click = false
    M.interacted = false
    M.wheel_consumed = false
    M._color_anchor = nil
    M._bind_mode_anchor = nil
    M._active_input_rect = nil

    -- Block underlay widgets when the cursor is over last frame's popup rect
    M.block_under = false
    if M.open_color and M._color_hit then
        local r = M._color_hit
        if input.hover(r.x, r.y, r.w, r.h) then
            M.block_under = true
            if input.lmb or input.lmb_click or input.rmb or input.rmb_click then
                M.interacted = true
                M.popup_used_click = true
            end
        end
    end
    if M.open_bind_mode and M._bind_mode_hit then
        local r = M._bind_mode_hit
        if input.hover(r.x, r.y, r.w, r.h) then
            M.block_under = true
            if input.lmb or input.lmb_click or input.rmb or input.rmb_click then
                M.interacted = true
                M.popup_used_click = true
            end
        end
    end
end

local function mark_interacted()
    M.interacted = true
    M.popup_used_click = true
end

local function open_color_popup(id, anchor_x, anchor_y, row_w)
    if M.open_color == id then
        M.open_color = nil
        M._color_anchor = nil
        M._color_hit = nil
    else
        M.open_color = id
        M.open_combo = nil
        M.open_multi = nil
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M._color_anchor = { id = id, x = anchor_x, y = anchor_y, w = row_w or 160 }
    end
end

local function open_bind_mode_popup(id, anchor_x, anchor_y, chip_w)
    if M.open_bind_mode == id then
        M.open_bind_mode = nil
        M._bind_mode_anchor = nil
        M._bind_mode_hit = nil
    else
        M.open_bind_mode = id
        M.open_combo = nil
        M.open_multi = nil
        M.open_color = nil
        M._color_hit = nil
        M._bind_mode_anchor = { id = id, x = anchor_x, y = anchor_y, w = chip_w or 56 }
    end
end

local function list_scroll_for(id, count, max_vis)
    max_vis = max_vis or M.LIST_MAX_VISIBLE
    local max_off = math.max(0, count - max_vis)
    local off = M._list_scroll[id] or 0
    if off < 0 then off = 0 end
    if off > max_off then off = max_off end
    M._list_scroll[id] = off
    return off, max_off, math.min(count, max_vis)
end

local LIST_SCROLL_EDGE = 22

local function apply_list_edge_scroll(id, count, max_vis, list_x, list_y, list_w, list_h)
    max_vis = max_vis or M.LIST_MAX_VISIBLE
    local max_off = math.max(0, count - max_vis)
    if max_off <= 0 then return end
    if not input.hover(list_x, list_y, list_w, list_h) then return end

    local off = M._list_scroll[id] or 0
    if input.wheel ~= 0 and not M.wheel_consumed then
        off = off - input.wheel
        M.wheel_consumed = true
    elseif input.my < list_y + LIST_SCROLL_EDGE then
        off = off - 1
    elseif input.my > list_y + list_h - LIST_SCROLL_EDGE then
        off = off + 1
    end
    if off < 0 then off = 0 end
    if off > max_off then off = max_off end
    M._list_scroll[id] = off
end

function M.end_popups()
    if input.lmb_click and M.active_input and M._active_input_rect then
        local r = M._active_input_rect
        if not input.hover(r.x, r.y, r.w, r.h) then
            M.active_input = nil
        end
    end

    if (input.lmb_click or input.rmb_click) and not M.popup_used_click then
        if M.open_combo or M.open_multi or M.open_color or M.open_bind_mode then
            M.open_combo = nil
            M.open_multi = nil
            M.open_color = nil
            M.open_bind_mode = nil
            M._color_anchor = nil
            M._color_hit = nil
            M._bind_mode_anchor = nil
            M._bind_mode_hit = nil
        end
    end
end

--- Draw floating color picker on top of the whole menu (call after columns).
function M.draw_color_overlay()
    if not M.open_color then
        M._color_hit = nil
        return
    end
    local id = M.open_color
    local col = state.get_color(id, { 1, 1, 1, 1 })
    local pw, ph = 168, 138
    local ax = M._color_anchor
    local px, py
    if ax and ax.id == id then
        px = ax.x + (ax.w or 160) - pw
        py = ax.y + theme.ROW_H + 2
    else
        px = input.mx + 12
        py = input.my + 12
    end
    -- Keep on screen
    local sw, sh = 1920, 1080
    if draw and draw.get_screen_size then
        sw, sh = draw.get_screen_size()
    end
    if px < 4 then px = 4 end
    if py < 4 then py = 4 end
    if px + pw > sw - 4 then px = sw - pw - 4 end
    if py + ph > sh - 4 then py = sh - ph - 4 end

    M._color_hit = { x = px, y = py, w = pw, h = ph }

    -- Soft shadow / backdrop
    M.rect(px + 3, py + 4, pw, ph, theme.SHADOW, true, theme.CORNER)
    M.draw_color_picker(px, py, pw, ph, id, col)

    if input.hover(px, py, pw, ph) then
        if input.lmb or input.lmb_click or input.rmb or input.rmb_click then
            mark_interacted()
        end
    end
end

--- Right-click keybind mode menu (Always / Hold / Toggle).
function M.draw_bind_mode_overlay()
    if not M.open_bind_mode then
        M._bind_mode_hit = nil
        return
    end
    local id = M.open_bind_mode
    local modes = { "Always", "Hold", "Toggle" }
    local mode_id = id .. "_mode"
    local cur = tonumber(state.get(mode_id, 2)) or 2
    local pw = 78
    local row_h = 18
    local ph = 4 + #modes * row_h
    local ax = M._bind_mode_anchor
    local px, py
    if ax and ax.id == id then
        px = ax.x + (ax.w or 56) - pw
        py = ax.y + 18
    else
        px = input.mx
        py = input.my + 8
    end
    local sw, sh = 1920, 1080
    if draw and draw.get_screen_size then
        sw, sh = draw.get_screen_size()
    end
    if px < 4 then px = 4 end
    if py < 4 then py = 4 end
    if px + pw > sw - 4 then px = sw - pw - 4 end
    if py + ph > sh - 4 then py = sh - ph - 4 end

    M._bind_mode_hit = { x = px, y = py, w = pw, h = ph }

    M.rect(px + 3, py + 4, pw, ph, theme.SHADOW, true, theme.CORNER)
    M.rect(px, py, pw, ph, theme.OVERLAY, true, theme.CORNER)
    M.rect(px, py, pw, ph, theme.BORDER_HOT, false, theme.CORNER)

    for i, name in ipairs(modes) do
        local iy = py + 2 + (i - 1) * row_h
        local selected = (cur == i - 1)
        if input.hover(px, iy, pw, row_h) then
            M.rect(px + 3, iy + 1, pw - 6, row_h - 2, theme.HOVER, true, theme.CORNER_SMALL)
        end
        if selected then
            anim.draw_tab_indicator(px + 2, iy + 4, 3, row_h - 8)
        end
        M.text(px + 10, iy + 2, name, selected and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
        if input.clicked(px, iy, pw, row_h) then
            mark_interacted()
            state.set(mode_id, i - 1)
            M.open_bind_mode = nil
            M._bind_mode_hit = nil
        end
    end

    if input.hover(px, py, pw, ph) and (input.lmb_click or input.rmb_click) then
        mark_interacted()
    end
end

function M.vk_name(vk)
    local ok, mod = pcall(June.require, "core.vk_names")
    if ok and mod and mod.label then
        return mod.label(vk)
    end
    vk = tonumber(vk) or 0
    if vk <= 0 then return "none" end
    return string.format("%02X", vk)
end

function M.rect(x, y, w, h, col, filled, rounding)
    if not draw then return end
    local c = M.clip
    if c then
        local x2 = x + w
        local y2 = y + h
        local cx = c.x
        local cy = c.y
        local cx2 = c.x + c.w
        local cy2 = c.y + c.h
        if x2 <= cx or y2 <= cy or x >= cx2 or y >= cy2 then return end
        if x < cx then
            w = w - (cx - x)
            x = cx
        end
        if y < cy then
            h = h - (cy - y)
            y = cy
        end
        if x + w > cx2 then w = cx2 - x end
        if y + h > cy2 then h = cy2 - y end
        if w <= 0 or h <= 0 then return end
    end
    if filled then
        draw.rect_filled(x, y, w, h, col, rounding or 0)
    else
        draw.rect(x, y, w, h, col, rounding or 0, 1)
    end
end

function M.text(x, y, str, col, size)
    if draw and draw.text then
        draw.text(x, y, tostring(str), col, size or theme.FONT)
    end
end

function M.rainbow_bar(x, y, w, h)
    anim.draw_title_bar(x, y, w, h)
end

function M.group_box(x, y, w, h, title)
    local c = M.clip
    if c then
        -- Only paint the portion inside the clip rect
        local top = math.max(y, c.y)
        local bot = math.min(y + h, c.y + c.h)
        if bot <= top then return end
        M.rect(x, top, w, bot - top, theme.PANEL, true)
        M.rect(x, top, w, bot - top, theme.BORDER, false)
        if y >= c.y - 2 and y < c.y + c.h then
            M.text(x + 12, y + 5, title, theme.TEXT_ACTIVE, theme.FONT_TITLE)
        end
        return
    end
    M.rect(x, y, w, h, theme.PANEL, true)
    M.rect(x, y, w, h, theme.BORDER, false)
    M.text(x + 12, y + 5, title, theme.TEXT_ACTIVE, theme.FONT_TITLE)
end

local LISTEN_VKS = {
    0x02, 0x04, 0x05, 0x06, 0x08, 0x09, 0x0D, 0x10, 0x11, 0x12, 0x14, 0x1B, 0x20,
    0x25, 0x26, 0x27, 0x28, 0x2E,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
    0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B,
    0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0,
}

function M.tick_key_listen()
    if not M.listening_key then return end
    if input.key_pressed(0x1B) then
        M.listening_key = nil
        return
    end
    for i = 1, #LISTEN_VKS do
        local vk = LISTEN_VKS[i]
        if not listen_skip_vk(vk) and input.key_pressed(vk) then
            state.set_key(M.listening_key, vk)
            M.listening_key = nil
            return
        end
    end
end

local INPUT_VKS = {
    0x20,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
    0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
    0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE,
}

local INPUT_SHIFT = {
    [0x30] = ")", [0x31] = "!", [0x32] = "@", [0x33] = "#", [0x34] = "$",
    [0x35] = "%", [0x36] = "^", [0x37] = "&", [0x38] = "*", [0x39] = "(",
    [0xBA] = ":", [0xBB] = "+", [0xBC] = "<", [0xBD] = "_", [0xBE] = ">",
    [0xBF] = "?", [0xC0] = "~", [0xDB] = "{", [0xDC] = "|", [0xDD] = "}",
    [0xDE] = "\"",
}

local INPUT_PLAIN = {
    [0x20] = " ",
    [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
    [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
    [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-", [0xBE] = ".",
    [0xBF] = "/", [0xC0] = "`", [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]",
    [0xDE] = "'",
}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function vk_to_char(vk)
    local shift = input.key_down(0x10)
    if vk >= 0x41 and vk <= 0x5A then
        local ch = string.char(vk)
        return shift and ch or string.lower(ch)
    end
    if shift then
        return INPUT_SHIFT[vk] or INPUT_PLAIN[vk]
    end
    return INPUT_PLAIN[vk]
end

local function input_key_repeat(vk)
    if input.key_pressed(vk) then
        M._input_repeat_vk = vk
        M._input_repeat_at = tick_ms() + 400
        return true
    end
    if M._input_repeat_vk ~= vk or not input.key_down(vk) then
        return false
    end
    local now = tick_ms()
    if now >= M._input_repeat_at then
        M._input_repeat_at = now + 35
        return true
    end
    return false
end

local function focus_input(id)
    M.active_input = id
    M.open_combo = nil
    M.open_multi = nil
    M.open_color = nil
    M.open_bind_mode = nil
    M.listening_key = nil
    M._input_repeat_vk = nil
end

function M.tick_text_input()
    if not M.active_input or M.listening_key then return end
    if input.key_down(0x11) or input.key_down(0x12) then return end

    local id = M.active_input
    local val = tostring(state.get(id, ""))

    if input.key_pressed(0x1B) or input.key_pressed(0x0D) then
        M.active_input = nil
        M._input_repeat_vk = nil
        return
    end

    if input_key_repeat(0x08) then
        if #val > 0 then
            state.set(id, val:sub(1, -2))
        end
        return
    end

    if input_key_repeat(0x2E) then
        if #val > 0 then
            state.set(id, val:sub(1, -2))
        end
        return
    end

    for i = 1, #INPUT_VKS do
        local vk = INPUT_VKS[i]
        if input.key_pressed(vk) then
            local ch = vk_to_char(vk)
            if ch then
                state.set(id, val .. ch)
            end
            M._input_repeat_vk = nil
            return
        end
    end
end

function M.checkbox(x, y, w, id, label, opts)
    opts = opts or {}
    if id and not state.is_visible(id) then
        return 0
    end
    state.define(id, opts.default == true)
    if opts.color then
        state.define_color(id, opts.color)
    end
    local on = state.get(id, false)
    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    local hovered = input.hover(x, y, w, h)
    local hover_fill = anim.transition("check-hover:" .. tostring(id), hovered, 16)
    if hover_fill > 0.01 then
        M.rect(x, y + 1, w, h - 2, theme.alpha(theme.HOVER, hover_fill), true, theme.CORNER_SMALL)
    end

    -- Neverlose-style pill toggle on the right
    local tw = theme.TOGGLE_W or 34
    local th = theme.TOGGLE_H or 18
    local has_color = opts.color or state.colors[id]
    local right_pad = has_color and 28 or 8
    local tx = x + w - right_pad - tw
    local ty = y + (h - th) * 0.5
    local fill = on and anim.checkbox_fill() or theme.CHECK_OFF
    M.rect(tx, ty, tw, th, fill, true, theme.CORNER_PILL or 9)
    M.rect(tx, ty, tw, th, on and theme.FOCUS or theme.BORDER_SOFT, false, theme.CORNER_PILL or 9)
    local knob_r = (th - 4) * 0.5
    local knob_x = on and (tx + tw - knob_r - 3) or (tx + knob_r + 3)
    local knob_y = ty + th * 0.5
    if draw and draw.circle_filled then
        draw.circle_filled(knob_x, knob_y, knob_r, { 1, 1, 1, 1 }, 14)
    else
        M.rect(knob_x - knob_r, knob_y - knob_r, knob_r * 2, knob_r * 2, { 1, 1, 1, 1 }, true, knob_r)
    end

    M.text(x + 6, y + 5, label, on and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT)

    local swatch_clicked = false
    if has_color then
        local col = state.get_color(id, opts.color or { 1, 1, 1, 1 })
        local cx = x + w - 18
        local cy = y + (h - 12) * 0.5
        M.rect(cx, cy, 12, 12, col, true, 2)
        M.rect(cx, cy, 12, 12, theme.BORDER, false, 2)
        if ui_clicked(cx - 2, cy - 2, 16, 16) then
            swatch_clicked = true
            mark_interacted()
            local hh = rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1)
            M._hue_cache[id] = hh
            open_color_popup(id, x, y, w)
        elseif M.open_color == id then
            M._color_anchor = { id = id, x = x, y = y, w = w }
        end
    end

    if not swatch_clicked and interactive(x, y, w, h) and ui_clicked(x, y, w - (has_color and 22 or 0), h) then
        mark_interacted()
        state.toggle(id)
    end
    return h
end

function M.slider(x, y, w, id, label, minv, maxv, default, opts)
    opts = opts or {}
    if id and not state.is_visible(id) then return 0 end
    local is_float = opts.float == true
    state.define(id, default)
    local val = tonumber(state.get(id, default)) or default
    local h = theme.SLIDER_ROW_H
    if not in_clip(y, h) then return h end

    local hovered = input.hover(x, y, w, h)
    local hover_fill = anim.transition("slider-hover:" .. tostring(id), hovered, 16)
    if hover_fill > 0.01 then
        M.rect(x, y + 1, w, h - 2, theme.alpha(theme.HOVER, hover_fill), true, theme.CORNER_SMALL)
    end

    local fmt = opts.fmt or (is_float and "%.2f" or "%d")
    local shown = string.format(fmt, val)
    M.text(x + 4, y + 3, label, theme.TEXT, theme.FONT)
    local vw = text_w(shown, theme.FONT_SMALL)
    M.text(x + w - vw - 6, y + 3, shown, theme.TEXT_DIM, theme.FONT_SMALL)

    local sx = x + 4
    local sy = y + theme.LABEL_H + theme.LABEL_GAP + 4
    local sw = w - 8
    M.rect(sx, sy, sw, theme.SLIDER_H, theme.SLIDER_BG, true, theme.SLIDER_H * 0.5)
    local t = 0
    if maxv > minv then
        t = clamp((val - minv) / (maxv - minv), 0, 1)
    end
    if t > 0 then
        anim.draw_slider_fill(sx, sy, math.max(2, sw * t), theme.SLIDER_H)
    end
    M.rect(sx, sy, sw, theme.SLIDER_H, theme.BORDER_SOFT, false, theme.SLIDER_H * 0.5)
    local thumb_x = sx + sw * t
    M.rect(thumb_x - 3, sy - 2, 6, theme.SLIDER_H + 4,
        M.active_slider == id and theme.TEXT_ACTIVE or anim.checkbox_fill(), true, 3)

    local hot = input.hover(sx, sy - 4, sw, theme.SLIDER_H + 8)
    if interactive(x, y, w, h) and ((input.lmb_click and hot) or (input.lmb and M.active_slider == id)) then
        M.active_slider = id
        mark_interacted()
        local nt = clamp((input.mx - sx) / sw, 0, 1)
        local nv = minv + (maxv - minv) * nt
        if not is_float then nv = math.floor(nv + 0.5) end
        state.set(id, nv)
    elseif M.active_slider == id and not input.lmb then
        M.active_slider = nil
    end
    return h
end

function M.combo(x, y, w, id, label, options, default_idx)
    if id and not state.is_visible(id) then return 0 end
    state.define(id, default_idx or 0)
    local idx = tonumber(state.get(id, default_idx or 0)) or 0
    local label_y, ctrl_y, ctrl_h, h = stacked_metrics(y)
    local open = M.open_combo == id
    if not in_clip(y, h) and not open then return h end

    M.text(x + 4, label_y, label, theme.TEXT, theme.FONT)
    local bx, by, bw, bh = x + 4, ctrl_y, w - 8, ctrl_h
    local hovered = input.hover(bx, by, bw, bh)
    local fill = anim.interactive_fill("combo:" .. tostring(id), theme.BUTTON, hovered, open)
    M.rect(bx, by, bw, bh, fill, true, theme.CORNER_SMALL)
    M.rect(bx, by, bw, bh, open and theme.FOCUS or theme.BORDER_SOFT, false, theme.CORNER_SMALL)
    local cur = options[idx + 1] or options[1] or "-"
    M.text(bx + 6, by + math.floor((bh - 12) * 0.5), tostring(cur), theme.TEXT_ACTIVE, theme.FONT_SMALL)
    M.text(bx + bw - 13, by + math.floor((bh - 12) * 0.5), open and "^" or "v", open and theme.TEXT_ACTIVE or theme.TEXT_DIM, theme.FONT_SMALL)

    -- Header toggles open/closed (do not require clip hover - fixes "can't close")
    if ui_clicked(bx, by, bw, bh) then
        mark_interacted()
        if open then
            M.open_combo = nil
        else
            M.open_combo = id
            M.open_multi = nil
            M.open_color = nil
            M.open_bind_mode = nil
            M._list_scroll[id] = 0
        end
        open = M.open_combo == id
    end

    if open then
        local n = #options
        local off, max_off, vis = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)
        local list_h = vis * 18
        local list_y = by + bh
        apply_list_edge_scroll(id, n, M.LIST_MAX_VISIBLE, bx, list_y, bw, list_h)
        off = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)

        M.rect(bx + 2, by + bh + 2, bw, list_h, theme.SHADOW, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.OVERLAY, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.BORDER_HOT, false, theme.CORNER_SMALL)
        for row = 0, vis - 1 do
            local i = off + row + 1
            local opt = options[i]
            if not opt then break end
            local iy = by + bh + row * 18
            if input.hover(bx, iy, bw, 18) then
                M.rect(bx + 2, iy + 1, bw - 4, 16, theme.HOVER, true, theme.CORNER_SMALL)
            end
            if i - 1 == idx then
                M.rect(bx + 3, iy + 4, 2, 10, anim.checkbox_fill(), true, 1)
            end
            M.text(bx + 10, iy + 2, tostring(opt), (i - 1 == idx) and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
            if ui_clicked(bx, iy, bw, 18) then
                mark_interacted()
                state.set(id, i - 1)
                M.open_combo = nil
            end
        end
        if max_off > 0 then
            local thumb_h = math.max(10, list_h * (vis / n))
            local ty = by + bh + (list_h - thumb_h) * (off / math.max(1, max_off))
            M.rect(bx + bw - 4, by + bh, 3, list_h, theme.SLIDER_BG, true)
            anim.draw_scroll_thumb(bx + bw - 4, ty, 3, thumb_h)
        end
        if input.hover(bx, by, bw, bh + list_h) and input.lmb_click and not M.block_under then
            mark_interacted()
        end
        return h + list_h
    end
    return h
end

function M.multi(x, y, w, id, label, options, defaults)
    if id and not state.is_visible(id) then return 0 end
    defaults = defaults or {}
    local def = {}
    for i = 1, #options do
        def[i] = defaults[i] == true
    end
    state.define(id, def)
    local vals = state.get(id, def)
    if type(vals) ~= "table" then
        vals = def
        state.set(id, vals)
    end

    local h = theme.STACKED_ROW_H
    local open = M.open_multi == id
    if not in_clip(y, h) and not open then return h end

    local label_y, ctrl_y, ctrl_h = stacked_metrics(y)
    M.text(x + 4, label_y, label, theme.TEXT, theme.FONT)
    local bx, by, bw, bh = x + 4, ctrl_y, w - 8, ctrl_h
    local hovered = input.hover(bx, by, bw, bh)
    local fill = anim.interactive_fill("multi:" .. tostring(id), theme.BUTTON, hovered, open)
    M.rect(bx, by, bw, bh, fill, true, theme.CORNER_SMALL)
    M.rect(bx, by, bw, bh, open and theme.FOCUS or theme.BORDER_SOFT, false, theme.CORNER_SMALL)

    local parts = {}
    for i, opt in ipairs(options) do
        if vals[i] then parts[#parts + 1] = opt end
    end
    local summary = (#parts > 0) and table.concat(parts, ", ") or "None"
    if #summary > 28 then summary = summary:sub(1, 26) .. ".." end
    M.text(bx + 6, by + math.floor((bh - 12) * 0.5), summary, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_clicked(bx, by, bw, bh) then
        mark_interacted()
        if open then
            M.open_multi = nil
        else
            M.open_multi = id
            M.open_combo = nil
            M.open_color = nil
            M.open_bind_mode = nil
            M._list_scroll[id] = 0
        end
        open = M.open_multi == id
    end

    if open then
        local n = #options
        local off, max_off, vis = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)
        local list_h = vis * 18
        local list_y = by + bh
        apply_list_edge_scroll(id, n, M.LIST_MAX_VISIBLE, bx, list_y, bw, list_h)
        off = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)

        M.rect(bx + 2, by + bh + 2, bw, list_h, theme.SHADOW, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.OVERLAY, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.BORDER_HOT, false, theme.CORNER_SMALL)
        for row = 0, vis - 1 do
            local i = off + row + 1
            local opt = options[i]
            if not opt then break end
            local iy = by + bh + row * 18
            local on = vals[i] == true
            if input.hover(bx, iy, bw, 18) then
                M.rect(bx + 2, iy + 1, bw - 4, 16, theme.HOVER, true, theme.CORNER_SMALL)
            end
            M.rect(bx + 5, iy + 3, 12, 12, theme.CHECK_OFF, true, 2)
            if on then
                M.rect(bx + 7, iy + 5, 8, 8, anim.checkbox_fill(), true, 2)
            end
            M.text(bx + 24, iy + 2, tostring(opt), on and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
            if ui_clicked(bx, iy, bw, 18) then
                mark_interacted()
                vals[i] = not on
                state.set(id, vals)
            end
        end
        if max_off > 0 then
            local thumb_h = math.max(10, list_h * (vis / n))
            local ty = by + bh + (list_h - thumb_h) * (off / math.max(1, max_off))
            M.rect(bx + bw - 4, by + bh, 3, list_h, theme.SLIDER_BG, true)
            anim.draw_scroll_thumb(bx + bw - 4, ty, 3, thumb_h)
        end
        if input.hover(bx, by, bw, bh + list_h) and input.lmb_click and not M.block_under then
            mark_interacted()
        end
        return h + list_h
    end
    return h
end

function M.button(x, y, w, id, label)
    if id and not state.is_visible(id) then return 0 end
    local h = 24
    if not in_clip(y, h) then return h end
    local hovered = input.hover(x, y, w, h)
    M.rect(x + 1, y + 2, w, h, theme.SHADOW, true, theme.CORNER_SMALL)
    M.rect(x, y, w, h, anim.interactive_fill("button:" .. tostring(id), theme.BUTTON, hovered, false), true, theme.CORNER_SMALL)
    M.rect(x, y, w, h, hovered and theme.BORDER_HOT or theme.BORDER_SOFT, false, theme.CORNER_SMALL)
    local tw = text_w(label, theme.FONT_SMALL)
    M.text(x + (w - tw) * 0.5, y + 6, label, theme.TEXT_ACTIVE, theme.FONT_SMALL)
    if interactive(x, y, w, h) and ui_clicked(x, y, w, h) then
        mark_interacted()
        state.fire_button(id)
    end
    return h
end

function M.label(x, y, w, text, dim)
    local h = theme.ROW_H - 4
    if not in_clip(y, h) then return h end
    M.text(x + 4, y + 3, text, dim and theme.TEXT_DIM or theme.TEXT_TITLE, theme.FONT_SMALL)
    return h
end

function M.separator(x, y, w)
    local h = 18
    if not in_clip(y, h) then return h end
    M.rect(x + 5, y + 9, w - 10, 1, theme.BORDER_SOFT, true)
    return h
end

function M.keybind(x, y, w, id, label, default_on, opts)
    opts = opts or {}
    if id and not state.is_visible(id) then return 0 end
    state.define(id, default_on == true)
    local mode_id = id .. "_mode"
    state.define(mode_id, 2) -- default Toggle (Always=0, Hold=1, Toggle=2)

    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    -- checkbox portion (leave room for key chip; mode is RMB popup)
    local chip_w = 56
    local cw = w - chip_w - 6
    local used = M.checkbox(x, y, cw, id, label, {
        default = default_on,
        color = opts.color or opts.colorpicker,
    })

    -- key chip: LMB bind, RMB mode (Always / Hold / Toggle)
    local kx = x + w - chip_w
    local ky = y + 3
    local listening = M.listening_key == id
    local vk = state.get_key(id)
    local klabel = listening and "..." or ("[" .. M.vk_name(vk) .. "]")
    local mode_open = M.open_bind_mode == id
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.ACCENT_DIM or theme.BUTTON, true, 8)
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.FOCUS or theme.BORDER_SOFT, false, 8)
    local tw = text_w(klabel, theme.FONT_SMALL)
    M.text(kx + (chip_w - tw) * 0.5, ky + 1, klabel, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_rmb_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.listening_key = nil
        open_bind_mode_popup(id, kx, ky, chip_w)
    elseif ui_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M.listening_key = listening and nil or id
    elseif mode_open then
        M._bind_mode_anchor = { id = id, x = kx, y = ky, w = chip_w }
    end

    return used
end

function M.aim_key_row(x, y, w, key_id, mode_id, label)
    if key_id and not state.is_visible(key_id) then return 0 end
    mode_id = mode_id or (key_id .. "_mode")
    state.define(mode_id, 1)

    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    local chip_w = 56
    M.text(x + 4, y + 3, label, theme.TEXT, theme.FONT)

    local kx = x + w - chip_w
    local ky = y + 3
    local listening = M.listening_key == key_id
    local vk = state.get_key(key_id)
    local klabel = listening and "..." or ("[" .. M.vk_name(vk) .. "]")
    local mode_open = M.open_bind_mode == key_id
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.ACCENT_DIM or theme.BUTTON, true, 8)
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.FOCUS or theme.BORDER_SOFT, false, 8)
    local tw = text_w(klabel, theme.FONT_SMALL)
    M.text(kx + (chip_w - tw) * 0.5, ky + 1, klabel, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_rmb_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.listening_key = nil
        open_bind_mode_popup(key_id, kx, ky, chip_w)
    elseif ui_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M.listening_key = listening and nil or key_id
    elseif mode_open then
        M._bind_mode_anchor = { id = key_id, x = kx, y = ky, w = chip_w }
    end

    return h
end

function M.hotkey_row(x, y, w, id, label, default_vk)
    if id and not state.is_visible(id) then return 0 end
    if state.get_key(id) == 0 and default_vk and default_vk ~= 0 then
        state.set_key(id, default_vk)
    end
    local mode_id = id .. "_mode"
    state.define(mode_id, 1) -- Always=0, Hold=1, Toggle=2

    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    local chip_w = 56
    M.text(x + 4, y + 4, label, theme.TEXT, theme.FONT)

    local kx = x + w - chip_w
    local ky = y + 4
    local listening = M.listening_key == id
    local vk = state.get_key(id)
    local klabel = listening and "..." or ("[" .. M.vk_name(vk) .. "]")
    local mode_open = M.open_bind_mode == id
    M.rect(kx, ky, chip_w, 18, (listening or mode_open) and theme.ACCENT_DIM or theme.BUTTON, true, 8)
    M.rect(kx, ky, chip_w, 18, (listening or mode_open) and theme.FOCUS or theme.BORDER_SOFT, false, 8)
    local tw = text_w(klabel, theme.FONT_SMALL)
    M.text(kx + (chip_w - tw) * 0.5, ky + 3, klabel, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_rmb_clicked(kx, ky, chip_w, 18) then
        mark_interacted()
        M.listening_key = nil
        open_bind_mode_popup(id, kx, ky, chip_w)
    elseif ui_clicked(kx, ky, chip_w, 18) then
        mark_interacted()
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M.listening_key = listening and nil or id
    elseif mode_open then
        M._bind_mode_anchor = { id = id, x = kx, y = ky, w = chip_w }
    end

    return h
end

function M.color_row(x, y, w, id, label, default_col)
    if id and not state.is_visible(id) then return 0 end
    state.define_color(id, default_col or { 1, 1, 1, 1 })
    local col = state.get_color(id, default_col)
    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    M.text(x + 4, y + 3, label, theme.TEXT, theme.FONT)
    local cx = x + w - 18
    M.rect(cx, y + 4, 12, 12, col, true, 3)
    M.rect(cx, y + 4, 12, 12, theme.BORDER, false, 3)

    if ui_clicked(cx - 2, y + 2, 16, 16) then
        mark_interacted()
        M._hue_cache[id] = select(1, rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1))
        open_color_popup(id, x, y, w)
    elseif M.open_color == id then
        M._color_anchor = { id = id, x = x, y = y, w = w }
    end
    return h
end

function M.draw_color_picker(px, py, pw, ph, id, col)
    M.rect(px, py, pw, ph, theme.OVERLAY, true, theme.CORNER)
    M.rect(px, py, pw, ph, theme.BORDER_HOT, false, theme.CORNER)

    local hue = M._hue_cache[id]
    if not hue then
        hue = select(1, rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1))
        M._hue_cache[id] = hue
    end
    local _, sat, val = rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1)
    local alpha = col[4] or 1

    local sq = 96
    local sx, sy = px + 8, py + 8
    -- Saturation / value square (sampled grid)
    local steps = 12
    local cell = sq / steps
    for iy = 0, steps - 1 do
        for ix = 0, steps - 1 do
            local s = ix / (steps - 1)
            local v = 1 - iy / (steps - 1)
            local r, g, b = hsv_to_rgb(hue, s, v)
            M.rect(sx + ix * cell, sy + iy * cell, cell + 0.5, cell + 0.5, { r, g, b, 1 }, true)
        end
    end
    M.rect(sx, sy, sq, sq, theme.BORDER, false, theme.CORNER_SMALL)

    -- Hue bar
    local hx, hy, hw, hh = sx + sq + 8, sy, 14, sq
    for i = 0, 23 do
        local t = i / 23
        local r, g, b = hsv_to_rgb(t, 1, 1)
        M.rect(hx, hy + i * (hh / 24), hw, hh / 24 + 0.5, { r, g, b, 1 }, true)
    end
    M.rect(hx, hy, hw, hh, theme.BORDER, false, theme.CORNER_SMALL)

    -- Alpha bar
    local ax, ay, aw, ah = sx, sy + sq + 8, sq + 22, 10
    M.rect(ax, ay, aw, ah, { 0.15, 0.15, 0.15, 1 }, true)
    M.rect(ax, ay, aw * clamp(alpha, 0, 1), ah, { col[1], col[2], col[3], 1 }, true)
    M.rect(ax, ay, aw, ah, theme.BORDER, false, theme.CORNER_SMALL)

    -- Preview
    local prx = ax + aw + 6
    M.rect(prx, ay - 2, 18, 14, { col[1], col[2], col[3], alpha }, true)
    M.rect(prx, ay - 2, 18, 14, theme.BORDER, false)

    local function apply(s, v, a, new_hue)
        if new_hue then
            M._hue_cache[id] = new_hue
            hue = new_hue
        end
        local r, g, b = hsv_to_rgb(hue, s, v)
        state.set_color(id, { r, g, b, a })
        if id == "june_ui_accent" then
            anim.sync_theme()
        end
    end

    if input.lmb and input.hover(sx, sy, sq, sq) then
        M.popup_used_click = true
        local ns = clamp((input.mx - sx) / sq, 0, 1)
        local nv = clamp(1 - (input.my - sy) / sq, 0, 1)
        apply(ns, nv, alpha, nil)
    elseif input.lmb and input.hover(hx, hy, hw, hh) then
        M.popup_used_click = true
        local nh = clamp((input.my - hy) / hh, 0, 1)
        apply(sat, val, alpha, nh)
    elseif input.lmb and input.hover(ax, ay, aw, ah) then
        M.popup_used_click = true
        local na = clamp((input.mx - ax) / aw, 0, 1)
        apply(sat, val, na, nil)
    end

    if input.hover(px, py, pw, ph) and input.lmb_click then
        M.popup_used_click = true
    end

    -- Cursor marks
    local mx = sx + sat * sq
    local my = sy + (1 - val) * sq
    M.rect(mx - 2, my - 2, 4, 4, { 1, 1, 1, 1 }, false)
    M.rect(hx - 1, hy + hue * hh - 1, hw + 2, 3, { 1, 1, 1, 1 }, false)
end

function M.input_row(x, y, w, id, label, default)
    if id and not state.is_visible(id) then return 0 end
    state.define(id, default or "")
    local val = tostring(state.get(id, default or ""))
    local label_y, ctrl_y, ctrl_h, h = stacked_metrics(y)
    if not in_clip(y, h) then return h end
    M.text(x + 4, label_y, label, theme.TEXT, theme.FONT)
    local bx, by, bw, bh = x + 4, ctrl_y, w - 8, ctrl_h
    local focused = M.active_input == id
    local hot = input.hover(bx, by, bw, bh)
    if focused then
        M._active_input_rect = { x = bx, y = by, w = bw, h = bh }
    end
    M.rect(bx, by, bw, bh, anim.interactive_fill("input:" .. tostring(id), theme.BUTTON, hot, focused), true, theme.CORNER_SMALL)
    M.rect(bx, by, bw, bh, focused and theme.FOCUS or (hot and theme.BORDER_HOT or theme.BORDER_SOFT), false, theme.CORNER_SMALL)

    local shown = val
    local text_x = bx + 6
    local max_w = bw - 12
    local text_y = by + math.floor((bh - 12) * 0.5)
    if shown == "" then
        M.text(text_x, text_y, "...", theme.TEXT_DIM, theme.FONT_SMALL)
    else
        while #shown > 0 and text_w(shown, theme.FONT_SMALL) > max_w do
            shown = shown:sub(2)
        end
        M.text(text_x, text_y, shown, focused and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
    end

    if focused then
        local caret_x = text_x + text_w(shown ~= "" and shown or "", theme.FONT_SMALL)
        local now = tick_ms()
        if math.floor(now / 500) % 2 == 0 then
            M.rect(caret_x, by + math.floor((bh - 10) * 0.5), 1, 10, theme.TEXT_ACTIVE, true)
        end
    end

    if interactive(bx, by, bw, bh) and ui_clicked(bx, by, bw, bh) then
        mark_interacted()
        focus_input(id)
    end
    return h
end

function M.estimate_height(item)
    local t = item.type
    local extra = 0
    -- Color pickers overlay - they do not expand layout height
    if item.id and M.open_combo == item.id and item.options then
        extra = math.min(#item.options, M.LIST_MAX_VISIBLE) * 18
    elseif item.id and M.open_multi == item.id and item.options then
        extra = math.min(#item.options, M.LIST_MAX_VISIBLE) * 18
    end
    if t == "slider" then
        return theme.SLIDER_ROW_H + extra
    elseif t == "combo" or t == "multi" or t == "input" then
        return theme.STACKED_ROW_H + extra
    elseif t == "separator" then
        return 18
    elseif t == "button" then
        return 24
    elseif t == "label" then
        return theme.ROW_H - 4
    elseif t == "color" then
        return theme.ROW_H
    elseif t == "checkbox" or t == "keybind" or t == "aim_key" or t == "hotkey" then
        return theme.ROW_H
    end
    return theme.ROW_H + extra
end

function M.draw_item(item, x, y, w)
    local t = item.type
    if t == "checkbox" then
        return M.checkbox(x, y, w, item.id, item.label, item)
    elseif t == "keybind" then
        return M.keybind(x, y, w, item.id, item.label, item.default, item)
    elseif t == "aim_key" then
        return M.aim_key_row(x, y, w, item.id, item.mode_id, item.label)
    elseif t == "hotkey" then
        return M.hotkey_row(x, y, w, item.id, item.label, item.default)
    elseif t == "slider" then
        return M.slider(x, y, w, item.id, item.label, item.min, item.max, item.default, item)
    elseif t == "combo" then
        return M.combo(x, y, w, item.id, item.label, item.options, item.default)
    elseif t == "multi" then
        return M.multi(x, y, w, item.id, item.label, item.options, item.defaults)
    elseif t == "button" then
        return M.button(x + 4, y, w - 8, item.id, item.label)
    elseif t == "label" then
        return M.label(x, y, w, item.label, item.dim)
    elseif t == "separator" then
        return M.separator(x, y, w)
    elseif t == "color" then
        return M.color_row(x, y, w, item.id, item.label, item.default)
    elseif t == "input" then
        return M.input_row(x, y, w, item.id, item.label, item.default)
    end
    return 0
end

return M

end)()

-- ── ui/catalog.lua ──
June._mods["ui.catalog"] = (function()
--[[
  Neverlose-layout catalog for June.
  Values / callbacks come from menu_defs + config via ui.menu_shim.

  Visibility:
    - group.master  → only that toggle shows until enabled; then children appear
    - item.gate     → nested child (also needs parent/master on)
    - item.gate2    → second required toggle
]]

local M = {}

local function cb(id, label, default, color, gate)
    return { type = "checkbox", id = id, label = label, default = default == true, color = color, gate = gate }
end

local function kb(id, label, default, gate, color)
    return { type = "keybind", id = id, label = label, default = default == true, gate = gate, color = color }
end

local function sl(id, label, minv, maxv, default, float, gate, extra)
    local item = {
        type = "slider",
        id = id,
        label = label,
        min = minv,
        max = maxv,
        default = default,
        float = float == true,
        fmt = float and "%.2f" or "%d",
        gate = gate,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do item[k] = v end
    end
    return item
end

local function combo(id, label, options, default, gate, gate2)
    return { type = "combo", id = id, label = label, options = options, default = default or 0, gate = gate, gate2 = gate2 }
end

local function multi(id, label, options, defaults, gate)
    return { type = "multi", id = id, label = label, options = options, defaults = defaults, gate = gate }
end

local function btn(id, label, gate)
    return { type = "button", id = id, label = label, gate = gate }
end

local function sep(gate)
    return { type = "separator", gate = gate }
end

local function label(text, dim, gate)
    return { type = "label", label = text, dim = dim, gate = gate }
end

local function hk(id, label, gate, default_vk)
    return { type = "hotkey", id = id, label = label, gate = gate, default = default_vk or 0x02 }
end

local function ak(key_id, label, gate)
    return { type = "aim_key", id = key_id, mode_id = key_id .. "_mode", label = label, gate = gate }
end

local function input(id, label_text, default, gate)
    return { type = "input", id = id, label = label_text, default = default or "", gate = gate }
end

local function color(id, label_text, default, gate, override_idx)
    return {
        type = "color",
        id = id,
        label = label_text,
        default = default,
        gate = gate,
        color_override_idx = override_idx,
    }
end

M.TABS = {
    { id = "aimbot", icon = "aim", title = "Aimbot", section = "Aimbot" },
    { id = "players", icon = "visuals", title = "Players", section = "Visuals" },
    { id = "world", icon = "world", title = "World", section = "Visuals" },
    { id = "main", icon = "misc", title = "Main", section = "Miscellaneous" },
    { id = "config", icon = "config", title = "Configs", section = "Miscellaneous" },
}

M.SECTIONS = { "Aimbot", "Visuals", "Miscellaneous" }

local BONE_OPTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Closest" }
local FOV_STYLES = { "Circle", "Filled Circle", "Dotted", "Square", "Filled Square", "Dashed" }
local LINE_STYLES = { "Solid", "Dashed", "Dotted" }
local ENDPOINTS = { "Filled Circle", "Outline Circle", "Dot", "Square", "Cross", "None" }
local BOX_TYPES = { "2D", "Corner", "3D" }
local VIEW_STYLES = { "Solid", "Dashed", "Fade" }
local TRACER_ORIGINS = { "Bottom", "Center", "Mouse" }
local TRACER_STYLES = { "Solid", "Dashed", "Dotted" }
local CROSS_STYLES = { "Cross", "Dot", "Circle", "Plus" }
local ANIM_MODES = { "Static", "Rainbow", "Pulse", "Wave", "Flow" }
local ELEM_MODES = { "Default", "Static", "Rainbow", "Pulse", "Wave", "Flow" }

local GADGET_BLACKLIST = {
    "Drone", "Claymore", "C4", "Jammer", "Sticky Cam", "BP Cam", "Map Cam",
    "Breach", "Hard Breach", "Prox Alarm", "Barbed Wire", "Shield", "Thermite",
    "Shock Bat", "Inc Canister", "Needle Mine", "Toxic",
}

local ACCENT = { 0.294, 0.549, 0.957, 1 }

local function build_aimbot()
    local AIM = "aimbot_enabled"
    local SIL = "silent_aim_enabled"

    local aim = {
        title = "Aimbot",
        master = AIM,
        items = {
            kb(AIM, "Enable Aimbot", false),
            ak("aimbot_key", "Aim Key"),
            sep(),
            label("Targeting", false),
            combo("aimbot_target_type", "Target Type", { "Crosshair", "Distance" }, 0),
            combo("aimbot_bone", "Hitbox", BONE_OPTS, 0),
            sl("aimbot_fov", "Field Of View", 1, 500, 125),
            sl("aimbot_smooth", "Smoothing", 1, 20, 5),
            sl("aimbot_max_distance", "Max Distance", 1, 500, 500),
            sep(),
            label("Options", false),
            cb("aimbot_sticky", "Sticky Aim", false),
            cb("aimbot_vischeck", "Visibility Check", false),
            combo("vis_check_priority", "Vis Priority", { "Distance", "Crosshair" }, 0, "aimbot_vischeck"),
            cb("aimbot_team_check", "Team Check", false),
            cb("aimbot_filter_health", "Health Check", false),
            cb("aimbot_prediction", "Prediction", false),
            sl("aimbot_prediction_val", "Prediction Strength", 0, 500, 50, false, "aimbot_prediction"),
            sep(),
            label("Gadget Aim", false),
            cb("utilities_aimbot", "Gadget Aim", false),
            cb("aimbot_players_priority", "Players Over Gadgets", false, nil, "utilities_aimbot"),
            sl("utilities_max_distance", "Gadget Max Distance", 1, 250, 75, false, "utilities_aimbot"),
            cb("aimbot_gadget_team_check", "Gadget Team Check", false, nil, "utilities_aimbot"),
            sep(),
            label("Visuals", false),
            cb("aimbot_fov_visible", "FOV Circle", false, { 1, 1, 1, 1 }),
            cb("aimbot_fov_fill", "FOV Fill", false, { 1, 1, 1, 0.08 }, "aimbot_fov_visible"),
            combo("aimbot_fov_style", "FOV Style", FOV_STYLES, 0, "aimbot_fov_visible"),
            cb("aimbot_target_line", "Target Line", false, { 1, 0, 0, 1 }),
            combo("target_line_style", "Line Style", LINE_STYLES, 0, "aimbot_target_line"),
            combo("target_line_endpoint", "Line Endpoint", ENDPOINTS, 5, "aimbot_target_line"),
        },
    }

    local silent = {
        title = "Silent Aim",
        master = SIL,
        items = {
            kb(SIL, "Enable Silent Aim", false),
            sep(),
            label("Targeting", false),
            combo("silent_target_type", "Target Type", { "Crosshair", "Distance" }, 0),
            combo("silent_bone", "Hitbox", BONE_OPTS, 0),
            sl("silent_fov", "Field Of View", 1, 500, 150),
            sl("silent_max_dist", "Max Distance", 1, 500, 250),
            sep(),
            label("Options", false),
            cb("silent_sticky", "Sticky Aim", false),
            cb("silent_filter_visible", "Visibility Check", false),
            combo("vis_check_priority", "Vis Priority", { "Distance", "Crosshair" }, 0, "silent_filter_visible"),
            cb("silent_filter_team", "Team Check", false),
            cb("silent_filter_health", "Health Check", false),
            sep(),
            label("Gadget Aim", false),
            cb("silent_gadget_aim", "Gadget Aim", false),
            cb("silent_players_priority", "Players Over Gadgets", false, nil, "silent_gadget_aim"),
            sl("silent_gadget_max_distance", "Gadget Max Distance", 1, 250, 75, false, "silent_gadget_aim"),
            cb("silent_gadget_team_check", "Gadget Team Check", false, nil, "silent_gadget_aim"),
            sep(),
            label("Visuals", false),
            cb("silent_draw_fov", "FOV Circle", false, { 0.55, 0.2, 1, 1 }),
            cb("silent_fov_fill", "FOV Fill", false, { 0.55, 0.2, 1, 0.08 }, "silent_draw_fov"),
            combo("silent_fov_style", "FOV Style", FOV_STYLES, 0, "silent_draw_fov"),
            cb("silent_target_line", "Target Line", false, { 1, 0.25, 0.25, 1 }),
            combo("silent_target_line_style", "Line Style", LINE_STYLES, 0, "silent_target_line"),
            combo("silent_target_line_endpoint", "Line Endpoint", ENDPOINTS, 5, "silent_target_line"),
        },
    }

    return { aim, silent }
end

local function build_players()
    local P = "players_enabled"
    return {
        {
            title = "ESP",
            master = P,
            items = {
                kb(P, "Enable Player Visuals", false, nil, { 1, 1, 1, 1 }),
                sep(),
                label("Box", false),
                cb("players_box", "Player Box", true),
                combo("box_type", "Box Type", BOX_TYPES, 0, "players_box"),
                cb("box_fill", "Box Fill", false, nil, "players_box"),
                sl("box_fill_opacity", "Fill Opacity", 0, 100, 25, false, "box_fill"),
                color("box_fill_color", "Fill Color", { 1, 1, 1, 0.3 }, "box_fill"),
                sep(),
                label("Info", false),
                cb("players_name", "Name", false, { 1, 1, 1, 1 }),
                cb("players_weapon", "Weapon", false, { 1, 0.5, 0.2, 1 }),
                cb("players_distance", "Distance", false, { 0.7, 0.7, 0.7, 1 }),
                cb("players_healthbar", "Health Bar", false),
                cb("players_team", "Show Teammates", false),
            },
        },
        {
            title = "Extras",
            master = P,
            items = {
                -- Master lives in ESP column; this column only appears when ESP is on.
                label("Extras", false),
                cb("players_skeleton", "Skeleton", false, { 1, 0.8, 0.2, 1 }),
                cb("players_head_dot", "Head Dot", false, { 1, 0.8, 0.2, 1 }),
                cb("players_view_line", "View Line", false, { 1, 0.8, 0.2, 1 }),
                sl("view_line_length", "View Line Length", 1, 10, 5, false, "players_view_line"),
                combo("view_line_style", "View Line Style", VIEW_STYLES, 0, "players_view_line"),
                cb("players_tracers", "Tracers", false, { 1, 1, 1, 1 }),
                combo("tracer_origin", "Tracer Origin", TRACER_ORIGINS, 0, "players_tracers"),
                combo("tracer_style", "Tracer Style", TRACER_STYLES, 0, "players_tracers"),
                sep(),
                label("Overrides", false),
                cb("players_visible_override", "Visible Color Override", false, { 0, 1, 0.3, 1 }),
                cb("players_target_override", "Target Color Override", false, { 1, 0.2, 0.2, 1 }),
            },
        },
    }
end

local function build_world()
    local W = "world_enabled"
    return {
        {
            title = "World",
            master = W,
            items = {
                kb(W, "Enable World Visuals", false),
                sep(),
                cb("world_team_check", "Gadget Team Check", false),
                multi("world_display_options", "Display Options", { "Text", "Distance", "3D Box" }, { false, false, false }),
                sl("world_max_distance", "Max Distance", 1, 500, 250),
                sep(),
                label("Gadget Aim Blacklist", false),
                multi("gadget_aim_blacklist", "Blacklist", GADGET_BLACKLIST, {
                    false, false, false, false, false, false, false, false, false, false,
                    false, false, false, false, false, false, false,
                }),
            },
        },
        {
            title = "Gadgets",
            master = W,
            items = {
                label("Show Gadgets", false),
                cb("bomb_enabled", "Bomb", false, { 1, 0.2, 0.2, 1 }),
                cb("defuser_enabled", "Defuser", false, { 0.2, 0.8, 1, 1 }),
                cb("claymore_enabled", "Claymore", false, { 1, 0.5, 0, 1 }),
                cb("drone_enabled", "Drone", false, { 0.5, 1, 0.5, 1 }),
                cb("default_camera_enabled", "Map Cameras", false, { 0.8, 0.8, 1, 1 }),
                cb("stun_grenade_enabled", "Flash / Stun", false, { 1, 1, 0, 1 }),
                cb("breach_charge_enabled", "Breach Charge", false, { 1, 0.4, 0.4, 1 }),
                cb("remotec4_enabled", "Remote C4", false, { 1, 0.2, 0.2, 1 }),
                cb("fraggrenade_enabled", "Frag Grenade", false, { 1, 0.6, 0.2, 1 }),
                cb("stickycamera_enabled", "Sticky Cameras", false, { 0.5, 0.5, 1, 1 }),
                cb("signaldisruptor_enabled", "Signal Disruptor", false, { 0.6, 0.3, 0.9, 1 }),
                cb("hardbreachcharge_enabled", "Hard Breach", false, { 1, 0.3, 0.1, 1 }),
                cb("proximityalarm_enabled", "Proximity Alarm", false, { 1, 0.8, 0, 1 }),
                cb("barbedwire_enabled", "Barbed Wire", false, { 0.6, 0.6, 0.6, 1 }),
                cb("incendiarygrenade_enabled", "Incendiary Grenade", false, { 1, 0.4, 0, 1 }),
                cb("bulletproofcamera_enabled", "BP Cameras", false, { 0.3, 0.7, 1, 1 }),
                cb("deployableshield_enabled", "Deployable Shield", false, { 0.4, 0.4, 0.8, 1 }),
                cb("smoke_grenade_enabled", "Smoke Grenade", false, { 0.7, 0.7, 0.7, 1 }),
                cb("emp_grenade_enabled", "EMP Grenade", false, { 0.4, 0.8, 1, 1 }),
                cb("impact_grenade_enabled", "Impact Grenade", false, { 1, 0.5, 0.3, 1 }),
                cb("thermite_charge_enabled", "Thermite Charge", false, { 1, 0.35, 0.1, 1 }),
                cb("incendiary_canister_enabled", "Incendiary Canister", false, { 1, 0.45, 0.1, 1 }),
                cb("shock_battery_enabled", "Shock Battery", false, { 0.3, 0.9, 1, 1 }),
                cb("needle_mine_enabled", "Needle Mine", false, { 0.9, 0.2, 0.9, 1 }),
                cb("toxic_charge_enabled", "Toxic Charge", false, { 0.2, 0.9, 0.3, 1 }),
                cb("metal_barricade_enabled", "Metal Barricade", false, { 0.55, 0.55, 0.55, 1 }),
            },
        },
    }
end

local function build_main()
    local COL = "june_ui_custom_colors"
    local ANM = "june_ui_custom_anim"
    local ELS = "june_ui_per_element"
    local XH = "crosshair_enabled"
    return {
        {
            title = "Overlay",
            items = {
                label("Fonts", false),
                sl("font_size_name", "Name Font Size", 8, 24, 14),
                sl("font_size_weapon", "Weapon Font Size", 8, 24, 12),
                sl("font_size_distance", "Distance Font Size", 8, 24, 12),
                sl("font_size_world", "World Item Font Size", 8, 24, 14),
                sep(),
                cb("keybind_window_enabled", "Enable Keybind List", false),
                sep(),
                cb(XH, "Crosshair", false, { 1, 1, 1, 1 }),
                combo("crosshair_style", "Crosshair Style", CROSS_STYLES, 0, XH),
                sl("crosshair_size", "Crosshair Size", 2, 30, 8, false, XH),
                sl("crosshair_gap", "Crosshair Gap", 0, 20, 3, false, XH),
            },
        },
        {
            title = "Menu",
            items = {
                hk("june_ui_menu_key", "Menu Toggle Key", nil, 0x2D),
                cb("june_ui_show_cursor_dot", "Show Cursor Dot", true),
                sep(),
                cb(COL, "Color Options", false),
                label("Colors", false, COL),
                color("june_ui_accent", "Accent", ACCENT, COL),
                sl("june_ui_bg_dim", "Background Dim", 0, 40, 0, false, COL),
                cb("june_ui_menu_fade", "Menu Fade Pulse", false, nil, COL),
                multi("june_ui_color_overrides", "Override Colors For", {
                    "Title Bar", "Section Tops", "Sliders", "Scrollbars", "Sidebar", "Checkboxes", "Overlay Panels",
                }, {}, COL),
                color("june_ui_col_title", "Title Bar Color", ACCENT, COL, 1),
                color("june_ui_col_section", "Section Top Color", ACCENT, COL, 2),
                color("june_ui_col_slider", "Slider Color", ACCENT, COL, 3),
                color("june_ui_col_scroll", "Scrollbar Color", ACCENT, COL, 4),
                color("june_ui_col_sidebar", "Sidebar Color", ACCENT, COL, 5),
                color("june_ui_col_checkbox", "Checkbox Color", ACCENT, COL, 6),
                color("june_ui_col_overlay", "Overlay Panel Color", ACCENT, COL, 7),
                sep(),
                cb(ANM, "Animation Options", false),
                label("Animation", false, ANM),
                combo("june_ui_accent_anim", "Style", ANIM_MODES, 1, ANM),
                sl("june_ui_anim_speed", "Speed", 1, 100, 40, false, ANM),
                multi("june_ui_anim_targets", "Animate", {
                    "Title Bar", "Section Tops", "Sliders", "Scrollbars", "Sidebar", "Checkboxes", "Hover", "Overlay Panels",
                }, { true, true, true, true, true, true, true, true }, ANM),
                cb(ELS, "Individual Styles", false, nil, ANM),
                combo("june_ui_style_title", "Title Bar", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_section", "Section Tops", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_slider", "Sliders", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_scroll", "Scrollbars", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_sidebar", "Sidebar", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_checkbox", "Checkboxes", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_overlay", "Overlay Panels", ELEM_MODES, 0, ANM, ELS),
            },
        },
    }
end

local function build_config()
    return {
        {
            title = "Config",
            items = {
                label("Profiles", false),
                input("config_name_input", "Config Name", "default"),
                btn("save_cfg_btn", "Save Config"),
                btn("load_cfg_btn", "Load Config"),
                sep(),
                cb("config_autoload_enabled", "Save as Autoload", false),
                label("Files: %LOCALAPPDATA%\\Project Vector\\Scripts", true),
            },
        },
    }
end

function M.groups_for(tab_id)
    if tab_id == "aimbot" then return build_aimbot() end
    if tab_id == "players" then return build_players() end
    if tab_id == "world" then return build_world() end
    if tab_id == "main" then return build_main() end
    if tab_id == "config" then return build_config() end
    return {}
end

return M

end)()

-- ── ui/custom_menu.lua ──
June._mods["ui.custom_menu"] = (function()
--[[
  Neverlose-style custom menu for June.
  INSERT toggles by default (rebindable in Main -> Menu).
  Scroll: mouse wheel when Vector exposes a reader; else edge-hover (top/bottom of column).
]]

local theme = June.require("ui.gs_theme")
local gin = June.require("ui.gs_input")
local widgets = June.require("ui.gs_widgets")
local anim = June.require("ui.gs_anim")
local icons = June.require("ui.gs_icons")
local catalog = June.require("ui.catalog")
local state = June.require("ui.gs_state")

local M = {}

local TOGGLE_VK_DEFAULT = 0x2D

local function menu_toggle_vk()
    local vk = state.get_key("june_ui_menu_key")
    if not vk or vk == 0 then
        vk = TOGGLE_VK_DEFAULT
    end
    return vk
end
local open = true
local tab_index = 1
local win_x, win_y = 80, 80
local scroll = { left = 0, right = 0 }

local SCROLL_EDGE = 36
local SCROLL_SPEED = 5
local WHEEL_STEP = 48
local PAGE_STEP = 90
local VK_PRIOR, VK_NEXT = 0x21, 0x22

local function screen_size()
    if draw and draw.get_screen_size then
        return draw.get_screen_size()
    end
    if utility and utility.get_screen_size then
        return utility.get_screen_size()
    end
    return 1920, 1080
end

local function clamp_window()
    local sw, sh = screen_size()
    win_x = math.max(0, math.min(win_x, sw - theme.WINDOW_W))
    win_y = math.max(0, math.min(win_y, sh - 40))
end

local function master_on(id)
    if not id then return true end
    return state.get(id, false) == true
end

local function combo_value(id)
    if not id then return nil end
    local v = state.get(id)
    if v == nil and menu and menu.get then
        v = menu.get(id)
    end
    return tonumber(v)
end

local function color_override_on(idx)
    if not idx then return true end
    local t = state.get("june_ui_color_overrides")
    if type(t) ~= "table" then return false end
    local v = t[idx]
    if v == nil and idx >= 1 then
        v = t[idx - 1]
    end
    return v == true or v == 1
end

local function item_visible(item, group)
    if group and group.master then
        if item.id == group.master then
            return true
        end
        if not master_on(group.master) then
            return false
        end
    end
    if item.gate and not master_on(item.gate) then
        return false
    end
    if item.gate2 and not master_on(item.gate2) then
        return false
    end
    if item.gate_combo then
        local cur = combo_value(item.gate_combo)
        local want = tonumber(item.gate_combo_value) or 0
        if cur ~= want then
            return false
        end
    end
    -- Show if ANY (combo_id, value) pair matches. pair = { id, value } or { id, {v1,v2} }
    if item.gate_any_combo then
        local ok = false
        for _, pair in ipairs(item.gate_any_combo) do
            local cid = pair[1] or pair.id
            local want = pair[2] or pair.value
            local cur = combo_value(cid)
            if type(want) == "table" then
                for _, w in ipairs(want) do
                    if cur == w then ok = true; break end
                end
            elseif cur == want then
                ok = true
            end
            if ok then break end
        end
        if not ok then return false end
    end
    if item.color_override_idx and not color_override_on(item.color_override_idx) then
        return false
    end
    if item.id and not state.is_visible(item.id) then
        return false
    end
    return true
end

local function content_height(items, group)
    local h = 0
    local count = 0
    for _, item in ipairs(items) do
        if item_visible(item, group) then
            h = h + widgets.estimate_height(item)
            count = count + 1
        end
    end
    if count > 1 then
        h = h + (count - 1) * theme.ITEM_GAP
    end
    return h + 20
end

local function group_visible(group)
    local items = group.items or {}
    for _, item in ipairs(items) do
        if item_visible(item, group) then
            return true
        end
    end
    return false
end

local function draw_sidebar(x, y, h)
    widgets.rect(x, y, theme.SIDEBAR_W, h, theme.SIDEBAR, true)
    widgets.rect(x + theme.SIDEBAR_W - 1, y, 1, h, theme.BORDER_SOFT, true)

    local tabs = catalog.TABS
    local cy = y + 10
    local last_section = nil

    for i, tab in ipairs(tabs) do
        local section = tab.section or ""
        if section ~= last_section then
            if last_section ~= nil then
                cy = cy + (theme.SECTION_GAP or 10)
            end
            widgets.text(x + 16, cy + 2, string.upper(section), theme.TEXT_SECTION or theme.TEXT_DIM, theme.FONT_SECTION or 11)
            cy = cy + (theme.SECTION_LABEL_H or 18)
            last_section = section
        end

        local row_h = theme.TAB_H
        local active = i == tab_index
        local hot = gin.hover(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4)
        local emphasis = anim.transition("tab:" .. tab.id, active or hot, 14)

        if active then
            widgets.rect(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4, theme.SIDEBAR_ACTIVE, true, theme.CORNER)
            widgets.rect(x + 8, cy, 3, row_h - 4, anim.tab_icon_color(), true, 2)
        elseif emphasis > 0.01 then
            widgets.rect(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4,
                theme.alpha(theme.HOVER, emphasis * 0.55), true, theme.CORNER)
        end

        local col = active and (anim.tab_icon_color and anim.tab_icon_color() or theme.ACCENT) or anim.mix(theme.TEXT_DIM, theme.TEXT, emphasis * 0.55)
        local icon_cx = x + 26
        local icon_cy = cy + (row_h - 4) * 0.5
        icons.draw(tab.icon or tab.id, icon_cx, icon_cy, col)
        widgets.text(x + 44, cy + 8, tab.title, col, theme.FONT)

        if gin.clicked(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4) then
            tab_index = i
            scroll.left = 0
            scroll.right = 0
            widgets.open_combo = nil
            widgets.open_multi = nil
        end

        cy = cy + row_h
    end
end

local function clamp_scroll(key, content_h, view_h)
    local max_scroll = math.max(0, content_h - view_h)
    if scroll[key] < 0 then scroll[key] = 0 end
    if scroll[key] > max_scroll then scroll[key] = max_scroll end
    return max_scroll
end

local function draw_scrollbar(x, y, h, content_h, scroll_key)
    local max_scroll = clamp_scroll(scroll_key, content_h, h)
    if max_scroll <= 0 then
        scroll[scroll_key] = 0
        return
    end

    local thumb_h = math.max(34, h * (h / content_h))
    local t = scroll[scroll_key] / max_scroll
    local thumb_y = y + t * (h - thumb_h)

    widgets.rect(x, y, 4, h, { 0, 0, 0, 0.26 }, true)
    widgets.rect(x + 1, y + 1, 2, h - 2, theme.SLIDER_BG, true)
    anim.draw_scroll_thumb(x, thumb_y, 4, thumb_h)
end

local function handle_column_scroll(x, y, w, h, scroll_key, content_h)
    local max_scroll = clamp_scroll(scroll_key, content_h, h)
    if max_scroll <= 0 then return end

    local hot = gin.hover(x, y, w + 14, h)
    if not hot and scroll_key == "left" then
        hot = gin.hover(gin.ui_x, y, theme.SIDEBAR_W + 8, h)
    end
    if not hot then return end

    -- Prefer real wheel when any probe delivers notches this frame.
    -- Open dropdowns consume the wheel first (see gs_widgets).
    if gin.wheel ~= 0 and not widgets.wheel_consumed then
        scroll[scroll_key] = scroll[scroll_key] - gin.wheel * WHEEL_STEP
        clamp_scroll(scroll_key, content_h, h)
        widgets.wheel_consumed = true
        return
    end

    -- Page Up / Page Down while hovering a column (documented IsKeyDown path).
    if gin.key_pressed(VK_PRIOR) then
        scroll[scroll_key] = scroll[scroll_key] - PAGE_STEP
        clamp_scroll(scroll_key, content_h, h)
        return
    end
    if gin.key_pressed(VK_NEXT) then
        scroll[scroll_key] = scroll[scroll_key] + PAGE_STEP
        clamp_scroll(scroll_key, content_h, h)
        return
    end

    -- Fallback: edge hover (only when wheel isn't available / not moving).
    if gin.my < y + SCROLL_EDGE then
        scroll[scroll_key] = scroll[scroll_key] - SCROLL_SPEED
        clamp_scroll(scroll_key, content_h, h)
    elseif gin.my > y + h - SCROLL_EDGE then
        scroll[scroll_key] = scroll[scroll_key] + SCROLL_SPEED
        clamp_scroll(scroll_key, content_h, h)
    end
end

local function draw_group_title(x, box_top, title)
    widgets.text(x + 12, box_top + 7, string.upper(tostring(title or "")), theme.TEXT_SECTION or theme.TEXT_DIM, theme.FONT_CAPTION or 11)
end

local function draw_group_column(groups, x, y, w, h, scroll_key)
    local pad = theme.GROUP_PAD
    local visible_groups = {}
    for _, group in ipairs(groups) do
        if group_visible(group) then
            visible_groups[#visible_groups + 1] = group
        end
    end

    local total = 0
    for _, group in ipairs(visible_groups) do
        total = total + content_height(group.items or {}, group) + theme.GROUP_HEADER_H + theme.GROUP_GAP
    end

    clamp_scroll(scroll_key, total, h)

    local gy = y + pad - scroll[scroll_key]
    widgets.clip = { x = x, y = y, w = w, h = h }

    for _, group in ipairs(visible_groups) do
        local items = group.items or {}
        local inner_h = content_height(items, group)
        local box_h = inner_h + theme.GROUP_HEADER_H

        local box_top = gy
        local box_bot = gy + box_h
        if box_bot > y and box_top < y + h then
            local vis_y = math.max(box_top, y)
            local vis_b = math.min(box_bot, y + h)
            local vis_h = vis_b - vis_y
            if vis_h > 1 then
                widgets.rect(x + 2, vis_y + 2, w, vis_h, theme.SHADOW, true)
                widgets.rect(x, vis_y, w, vis_h, theme.PANEL, true)
                widgets.rect(x, vis_y, w, vis_h, theme.BORDER_SOFT, false)
                if box_top >= y - 2 and box_top < y + h then
                    widgets.rect(x + 1, box_top + 2, w - 2, theme.GROUP_HEADER_H - 3, theme.PANEL_ALT, true)
                    anim.draw_section_top(x + 1, box_top, w - 2)
                    draw_group_title(x, box_top, group.title)
                end
            end

            local iy = gy + theme.GROUP_HEADER_H + 6
            local ix = x + 7
            local iw = w - 16
            for _, item in ipairs(items) do
                if item_visible(item, group) then
                    local est = widgets.estimate_height(item)
                    if iy >= y and iy + est <= y + h then
                        local ok, used = pcall(widgets.draw_item, item, ix, iy, iw)
                        if not ok then
                            used = est
                        elseif type(used) ~= "number" or used < 1 then
                            used = est
                        end
                        iy = iy + used + theme.ITEM_GAP
                    else
                        iy = iy + est + theme.ITEM_GAP
                    end
                end
            end
        end

        gy = gy + box_h + theme.GROUP_GAP
    end

    widgets.clip = nil
    handle_column_scroll(x, y, w, h, scroll_key, total)
    draw_scrollbar(x + w + 2, y, h, total, scroll_key)
end

local function split_groups(groups, tab_id)
    if (tab_id == "aimbot" or tab_id == "main" or tab_id == "players" or tab_id == "world") and #groups >= 2 then
        return { groups[1] }, { groups[2] }
    end
    if tab_id == "config" and #groups >= 2 then
        return { groups[1] }, { groups[2] }
    end
    if #groups == 2 then
        return { groups[1] }, { groups[2] }
    end
    if #groups == 1 then
        return { groups[1] }, {}
    end
    local left, right = {}, {}
    for i, g in ipairs(groups) do
        if i % 2 == 1 then
            left[#left + 1] = g
        else
            right[#right + 1] = g
        end
    end
    return left, right
end

function M.init()
    state.define("june_ui_custom_colors", false)
    state.define("june_ui_custom_anim", false)
    state.define("june_ui_per_element", false)
    state.define("june_ui_show_cursor_dot", true)
    state.define("june_ui_accent", theme.ACCENT)
    state.define_color("june_ui_accent", theme.ACCENT)
    state.define("june_ui_accent_anim", 1)
    state.define("june_ui_anim_speed", 40)
    state.define("june_ui_bg_dim", 0)
    state.define("june_ui_menu_fade", false)
    state.define("june_ui_anim_targets", {
        true, true, true, true, true, true, true, true,
    })
    state.define("june_ui_color_overrides", {})
    state.define("june_ui_style_title", 0)
    state.define("june_ui_style_section", 0)
    state.define("june_ui_style_slider", 0)
    state.define("june_ui_style_scroll", 0)
    state.define("june_ui_style_sidebar", 0)
    state.define("june_ui_style_checkbox", 0)
    state.define("june_ui_style_overlay", 0)
    state.define_color("june_ui_col_title", theme.ACCENT)
    state.define_color("june_ui_col_section", theme.ACCENT)
    state.define_color("june_ui_col_slider", theme.ACCENT)
    state.define_color("june_ui_col_scroll", theme.ACCENT)
    state.define_color("june_ui_col_sidebar", theme.ACCENT)
    state.define_color("june_ui_col_checkbox", theme.ACCENT)
    state.define_color("june_ui_col_overlay", theme.ACCENT)
    if state.get_key("june_ui_menu_key") == 0 then
        state.set_key("june_ui_menu_key", TOGGLE_VK_DEFAULT)
    end
    local sw, sh = screen_size()
    win_x = math.floor((sw - theme.WINDOW_W) * 0.5)
    win_y = math.floor((sh - theme.WINDOW_H) * 0.3)
end

function M.is_open()
    return open
end

function M.draw()
    if not draw then return end

    gin.begin_frame()
    anim.sync_theme()
    widgets.begin_popups()

    if gin.key_pressed(menu_toggle_vk()) and not widgets.listening_key and not widgets.active_input then
        open = not open
        gin.set_menu_open(open)
    end

    widgets.tick_key_listen()
    widgets.tick_text_input()

    if not open then
        if gin._menu_open or gin._game_cursor_hidden then
            gin.set_menu_open(false)
        end
        return
    end

    gin.set_menu_open(true)
    clamp_window()

    local x, y = win_x, win_y
    local w, h = theme.WINDOW_W, theme.WINDOW_H
    gin.set_ui_rect(x, y, w, h)

    -- Frame
    local fade = anim.menu_fade()
    widgets.rect(x, y, w, h, theme.alpha(anim.panel_bg(), fade), true)
    widgets.rect(x, y, w, h, theme.BORDER, false)
    widgets.rect(x + 1, y + 1, w - 2, 1, theme.BORDER_HOT, true)
    anim.draw_title_bar(x + 1, y + 1, w - 2, 2)

    local title_h = 28
    widgets.rect(x + 1, y + 3, w - 2, title_h, theme.BG_INNER, true)
    widgets.rect(x + 1, y + title_h + 3, w - 2, 1, theme.BORDER_SOFT, true)
    local tab = catalog.TABS[tab_index]
    -- Brand lives in the top bar so the page title doesn't look orphaned.
    widgets.text(x + 14, y + 9, "JUNE", theme.TEXT_ACTIVE, theme.FONT_BRAND or 15)
    local brand_w = 52
    if draw and draw.get_text_size then
        local tw = draw.get_text_size("JUNE", theme.FONT_BRAND or 15)
        if type(tw) == "number" then brand_w = tw + 10 end
    end
    widgets.text(x + 14 + brand_w, y + 11, "/  " .. (tab and tab.title or "Menu"), theme.TEXT_TITLE, theme.FONT_TITLE)

    if gin.lmb_click and gin.hover(x, y, w, title_h + 5)
        and not widgets.active_slider and not widgets.listening_key
        and not widgets.active_input
        and not widgets.block_under
        and not widgets.open_combo and not widgets.open_multi and not widgets.open_color
        and not widgets.open_bind_mode then
        widgets.dragging_window = true
        widgets.drag_offset_x = gin.mx - win_x
        widgets.drag_offset_y = gin.my - win_y
    end
    if widgets.dragging_window then
        if gin.lmb then
            win_x = gin.mx - widgets.drag_offset_x
            win_y = gin.my - widgets.drag_offset_y
            clamp_window()
        else
            widgets.dragging_window = false
        end
    end

    local body_y = y + title_h + 6
    local body_h = h - title_h - 10

    draw_sidebar(x + 1, body_y, body_h)

    local content_x = x + theme.SIDEBAR_W + 12
    local content_w = w - theme.SIDEBAR_W - 30
    local groups = catalog.groups_for(tab and tab.id or "aimbot")
    local left_groups, right_groups = split_groups(groups, tab and tab.id or "aimbot")
    local dual = #right_groups > 0
    local col_w = dual and math.floor((content_w - 16) * 0.5) or (content_w - 8)

    draw_group_column(left_groups, content_x, body_y + 2, col_w, body_h - 4, "left")
    if dual then
        draw_group_column(right_groups, content_x + col_w + 12, body_y + 2, col_w, body_h - 4, "right")
    end

    -- Floating popups above all sections
    widgets.draw_color_overlay()
    widgets.draw_bind_mode_overlay()
    widgets.end_popups()

    gin.draw_cursor()
end

return M

end)()

-- ── core/draw_util.lua ──
June._mods["core.draw_util"] = (function()
local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")

local sqrt, floor, min, max = constants.sqrt, constants.floor, constants.min, constants.max
local BOX_TYPE = constants.BOX_TYPE
local VIEW_LINE_STYLE = constants.VIEW_LINE_STYLE
local TRACER_STYLE = constants.TRACER_STYLE
local MIN_BONES_REQUIRED = constants.MIN_BONES_REQUIRED

local M = {}
local s = settings.s

function M.dist3d_sq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx * dx + dy * dy + dz * dz
end
function M.is_teammate(vm)
    local h = vm:FindFirstChild("head")
    return h and
        (h:FindFirstChild("Username") or vm:FindFirstChild("TeammateHighlight") or h:FindFirstChild("TeammateHighlight")) and
        true or
        false
end

function M.is_valid_viewmodel(vm)
    if not vm or vm.Name ~= "Viewmodel" then
        return false
    end
    local h, t = vm:FindFirstChild("head"), vm:FindFirstChild("torso")
    if not h or not h.Position or not t or not t.Position or (t.Transparency and t.Transparency >= 1) then
        return false
    end
    local tsz = t.Size
    if tsz and (tsz.X <= 0.1 or tsz.Y <= 0.1 or tsz.Z <= 0.1) then
        return false
    end
    local bc = 0
    for _, bn in ipairs(cache.bone_list) do
        local b = vm:FindFirstChild(bn)
        if b and b.Position and b.Size and (b.Size.X > 0.05 or b.Size.Y > 0.05 or b.Size.Z > 0.05) then
            bc = bc + 1
        end
    end
    return bc >= MIN_BONES_REQUIRED
end

function M.get_world_item_position(obj, cfg)
    if not obj or not cfg then
        return nil, nil
    end

    local function part_pos(part)
        if not part then
            return nil, nil
        end
        local pos = part.Position or part.position
        local sz = part.Size or part.size
        if not pos then
            return nil, nil
        end
        return pos, sz
    end

    if cfg.priority_part then
        local pp = obj:FindFirstChild(cfg.priority_part)
        if pp then
            local pos, sz = part_pos(pp)
            if pos then
                return pos, sz
            end
        end
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Model" or cn == "Folder" then
                pp = child:FindFirstChild(cfg.priority_part)
                if pp then
                    local pos, sz = part_pos(pp)
                    if pos then
                        return pos, sz
                    end
                end
            end
        end
    end

    if obj.PrimaryPart then
        local pos, sz = part_pos(obj.PrimaryPart)
        if pos then
            return pos, sz
        end
    end
    if obj.primary_part then
        local pos, sz = part_pos(obj.primary_part)
        if pos then
            return pos, sz
        end
    end

    for _, name in ipairs({"Root", "Cam", "Base", "Handle", "Primary"}) do
        local pp = obj:FindFirstChild(name)
        if pp then
            local pos, sz = part_pos(pp)
            if pos then
                return pos, sz
            end
        end
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Model" or cn == "Folder" then
                pp = child:FindFirstChild(name)
                if pp then
                    local pos, sz = part_pos(pp)
                    if pos then
                        return pos, sz
                    end
                end
            end
        end
    end

    if obj.FindFirstChildWhichIsA then
        local first_part = obj:FindFirstChildWhichIsA("BasePart")
        if first_part then
            return part_pos(first_part)
        end
    end
    if obj.find_first_child_which_is_a then
        local first_part = obj:find_first_child_which_is_a("BasePart")
        if first_part then
            return part_pos(first_part)
        end
    end

    if obj.GetChildren then
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Part" or cn == "MeshPart" or cn == "UnionOperation" then
                local pos, sz = part_pos(child)
                if pos then
                    return pos, sz
                end
            end
        end
    end

    return nil, nil
end
local PART_CLASSES = {
    Part = true,
    MeshPart = true,
    UnionOperation = true
}

local function is_part(inst)
    if not inst then
        return false
    end
    local cn = inst.ClassName or inst.class_name
    return PART_CLASSES[cn] == true
end

local function get_descendants(obj)
    if obj.get_descendants then
        return obj:get_descendants()
    end
    if obj.GetDescendants then
        return obj:GetDescendants()
    end
    return {}
end

function M.get_model_bbox(obj, max_parts)
    if not obj then
        return nil
    end
    max_parts = max_parts or 16
    local mnx, mny, mnz = math.huge, math.huge, math.huge
    local mxx, mxy, mxz = -math.huge, -math.huge, -math.huge
    local found = 0

    local function consider(part)
        if not is_part(part) then
            return
        end
        if part.Transparency and part.Transparency >= 1 then
            return
        end
        local pos = part.Position or part.position
        local sz = part.Size or part.size
        if not pos or not sz then
            return
        end
        local hx, hy, hz = sz.X * 0.5, sz.Y * 0.5, sz.Z * 0.5
        local rv = part.RightVector or part.right_vector
        local uv = part.UpVector or part.up_vector
        local lv = part.LookVector or part.look_vector
        if rv and uv and lv then
            local corners = {
                pos + rv * -hx + uv * -hy + lv * -hz,
                pos + rv *  hx + uv * -hy + lv * -hz,
                pos + rv * -hx + uv *  hy + lv * -hz,
                pos + rv *  hx + uv *  hy + lv * -hz,
                pos + rv * -hx + uv * -hy + lv *  hz,
                pos + rv *  hx + uv * -hy + lv *  hz,
                pos + rv * -hx + uv *  hy + lv *  hz,
                pos + rv *  hx + uv *  hy + lv *  hz
            }
            for _, cp in ipairs(corners) do
                mnx = min(mnx, cp.X)
                mny = min(mny, cp.Y)
                mnz = min(mnz, cp.Z)
                mxx = max(mxx, cp.X)
                mxy = max(mxy, cp.Y)
                mxz = max(mxz, cp.Z)
            end
            found = found + 1
        else
            mnx = min(mnx, pos.X - hx)
            mny = min(mny, pos.Y - hy)
            mnz = min(mnz, pos.Z - hz)
            mxx = max(mxx, pos.X + hx)
            mxy = max(mxy, pos.Y + hy)
            mxz = max(mxz, pos.Z + hz)
            found = found + 1
        end
    end

    if is_part(obj) then
        consider(obj)
    else
        for _, child in ipairs(get_descendants(obj)) do
            if found >= max_parts then
                break
            end
            consider(child)
        end
    end

    if found == 0 then
        return nil
    end
    return {mnx, mny, mnz, mxx, mxy, mxz}
end

function M.bbox_from_part(part)
    if not part then
        return nil
    end
    local pos = part.Position or part.position
    local sz = part.Size or part.size
    if not pos or not sz then
        return nil
    end
    local hx = (sz.X or sz.x or 0) * 0.5
    local hy = (sz.Y or sz.y or 0) * 0.5
    local hz = (sz.Z or sz.z or 0) * 0.5
    local px = pos.X or pos.x
    local py = pos.Y or pos.y
    local pz = pos.Z or pos.z
    return {px - hx, py - hy, pz - hz, px + hx, py + hy, pz + hz}
end

function M.bbox_center(bbox)
    if not bbox then
        return nil
    end
    return {
        x = (bbox[1] + bbox[4]) * 0.5,
        y = (bbox[2] + bbox[5]) * 0.5,
        z = (bbox[3] + bbox[6]) * 0.5
    }
end

local hull_cache = {}
local vm_parts_cache = {}
local HULL_CACHE_MS = 150
local HULL_MOVE_EPS = 0.05
local VM_PARTS_CACHE_MS = 600
local MAX_HULL_CACHE = 640

function M.normalize_chams_style(style)
    if style == 1 then
        return 1
    end
    return 0
end

local function trim_hull_cache()
    local n = 0
    for _ in pairs(hull_cache) do
        n = n + 1
    end
    if n <= MAX_HULL_CACHE then
        return
    end
    local now = utility.get_tick_count()
    for k, entry in pairs(hull_cache) do
        if entry.tick and now - entry.tick > HULL_CACHE_MS * 4 then
            hull_cache[k] = nil
        end
    end
end

function M.clear_hull_cache()
    for k in pairs(hull_cache) do
        hull_cache[k] = nil
    end
    for k in pairs(vm_parts_cache) do
        vm_parts_cache[k] = nil
    end
end

function M.is_drawable_body_part(part)
    if not is_part(part) then
        return false
    end
    if part.Transparency and part.Transparency >= 1 then
        return false
    end
    local sz = part.Size or part.size
    if not sz then
        return false
    end
    local sx = sz.X or sz.x or 0
    local sy = sz.Y or sz.y or 0
    local sz_z = sz.Z or sz.z or 0
    if sx < 0.05 and sy < 0.05 and sz_z < 0.05 then
        return false
    end
    return true
end

function M.collect_viewmodel_body_parts(vm)
    local parts = {}
    local seen = {}

    local function add_part(part)
        if part and not seen[part] and M.is_drawable_body_part(part) then
            seen[part] = true
            parts[#parts + 1] = part
        end
    end

    local model = vm and vm.FindFirstChild and vm:FindFirstChild("Model")
    if model then
        for _, desc in ipairs(get_descendants(model)) do
            add_part(desc)
        end
    end

    for _, bn in ipairs(cache.bone_list) do
        local bone = vm and vm.FindFirstChild and vm:FindFirstChild(bn)
        if bone then
            if is_part(bone) then
                add_part(bone)
            end
            for _, desc in ipairs(get_descendants(bone)) do
                add_part(desc)
            end
        end
    end

    return parts
end

function M.get_viewmodel_body_parts(vm)
    if not vm then
        return {}
    end
    local key = tostring(vm)
    local now = utility.get_tick_count()
    local entry = vm_parts_cache[key]
    if entry and (now - entry.tick) < VM_PARTS_CACHE_MS then
        return entry.parts
    end
    local parts = M.collect_viewmodel_body_parts(vm)
    vm_parts_cache[key] = {parts = parts, tick = now}
    return parts
end

function M.project_bbox_screen(bbox)
    if not bbox then
        return nil
    end
    local mnx, mny, mxx, mxy, vis = 10000, 10000, -10000, -10000, false
    for _, c in ipairs({
        {bbox[1], bbox[2], bbox[3]},
        {bbox[4], bbox[2], bbox[3]},
        {bbox[4], bbox[5], bbox[3]},
        {bbox[1], bbox[5], bbox[3]},
        {bbox[1], bbox[2], bbox[6]},
        {bbox[4], bbox[2], bbox[6]},
        {bbox[4], bbox[5], bbox[6]},
        {bbox[1], bbox[5], bbox[6]},
    }) do
        local sx, sy, v = utility.world_to_screen(c[1], c[2], c[3])
        if v then
            vis = true
            mnx, mny, mxx, mxy = min(mnx, sx), min(mny, sy), max(mxx, sx), max(mxy, sy)
        end
    end
    if not vis then
        return nil
    end
    return mnx, mny, mxx, mxy, (mnx + mxx) * 0.5
end

function M.draw_screen_box(mnx, mny, mxx, mxy, col)
    if not mnx then
        return
    end
    local w, h = mxx - mnx, mxy - mny
    if w > 0 and h > 0 then
        draw.rect(mnx, mny, w, h, col, 0, 1.5)
    end
end

function M.draw_screen_chams(mnx, mny, mxx, mxy, color, style, outline_color)
    if not mnx then
        return
    end
    local w, h = mxx - mnx, mxy - mny
    if w <= 0 or h <= 0 then
        return
    end
    if style == 1 then
        draw.rect(mnx, mny, w, h, outline_color or color, 0, 1.5)
    else
        draw.rect_filled(mnx, mny, w, h, color)
        if outline_color then
            draw.rect(mnx, mny, w, h, outline_color, 0, 1.5)
        end
    end
end

function M.draw_vm_body_chams(vm, color, style, outline_color)
    if not vm or not vm.FindFirstChild then
        return
    end
    for _, bn in ipairs(cache.cham_bone_list or cache.bone_list) do
        local part = vm:FindFirstChild(bn)
        if part and part.Position and part.Size then
            local sz = part.Size
            if (sz.X or sz.x or 0) > 0 then
                M.draw_part_hull_cached(part, color, style, outline_color)
            end
        end
    end
end

function M.draw_bone_chams(bones, color, style, outline_color)
    if not bones then
        return
    end
    local bone_list = cache.cham_bone_list or cache.bone_list
    for _, bn in ipairs(bone_list) do
        local bp = bones[bn]
        if bp and bp.hx and bp.hy then
            local cx, cy, cz = bp.x, bp.y, bp.z
            local sx_c, sy_c, vis = utility.world_to_screen(cx, cy, cz)
            local sx_t, sy_t, vt = utility.world_to_screen(cx, cy + bp.hy, cz)
            local sx_r, sy_r, vr = utility.world_to_screen(cx + bp.hx, cy, cz)
            if vis and vt and vr then
                local h = math.abs(sy_t - sy_c) * 2
                local w = math.abs(sx_r - sx_c) * 2
                if h < 2 then
                    h = 4
                end
                if w < 2 then
                    w = 4
                end
                local bx = sx_c - w * 0.5
                local by = sy_c - h * 0.5
                if style == 1 then
                    draw.rect(bx, by, w, h, outline_color or color, 1.5)
                else
                    draw.rect_filled(bx, by, w, h, color)
                    if outline_color then
                        draw.rect(bx, by, w, h, outline_color, 1.5)
                    end
                end
            end
        end
    end
end

function M.draw_bbox_chams(bbox, color, style, outline_color)
    if not bbox then
        return
    end
    local screen_points = {}
    local corners = {
        {bbox[1], bbox[2], bbox[3]},
        {bbox[4], bbox[2], bbox[3]},
        {bbox[4], bbox[5], bbox[3]},
        {bbox[1], bbox[5], bbox[3]},
        {bbox[1], bbox[2], bbox[6]},
        {bbox[4], bbox[2], bbox[6]},
        {bbox[4], bbox[5], bbox[6]},
        {bbox[1], bbox[5], bbox[6]},
    }
    for _, c in ipairs(corners) do
        local sx, sy, v = utility.world_to_screen(c[1], c[2], c[3])
        if v then
            screen_points[#screen_points + 1] = {sx, sy}
        end
    end
    if #screen_points < 3 then
        return
    end
    local hull = draw.compute_hull(screen_points)
    if not hull then
        return
    end
    if style == 1 then
        draw.poly_closed(hull, outline_color or color, 1.5)
    else
        draw.poly_filled(hull, color)
        if outline_color then
            draw.poly_closed(hull, outline_color, 1.5)
        end
    end
end

function M.part_screen_pos(part)
    if not part then
        return nil
    end
    local pos = part.Position or part.position
    if not pos then
        return nil
    end
    local sx, sy, vis = utility.world_to_screen(pos.X, pos.Y, pos.Z)
    if not vis then
        return nil
    end
    return sx, sy
end

function M.part_screen_radius(part)
    if not part then
        return 3
    end
    local pos = part.Position or part.position
    local sz = part.Size or part.size
    if not pos or not sz then
        return 3
    end
    local hy = (sz.Y or 0) * 0.5
    local hx = (sz.X or 0) * 0.5
    local sx1, sy1, v1 = utility.world_to_screen(pos.X, pos.Y + hy, pos.Z)
    local sx2, sy2, v2 = utility.world_to_screen(pos.X, pos.Y - hy, pos.Z)
    if v1 and v2 then
        return sqrt((sx1 - sx2) ^ 2 + (sy1 - sy2) ^ 2) * 0.5
    end
    local sx3, sy3, v3 = utility.world_to_screen(pos.X + hx, pos.Y, pos.Z)
    local sx4, sy4, v4 = utility.world_to_screen(pos.X - hx, pos.Y, pos.Z)
    if v3 and v4 then
        return sqrt((sx3 - sx4) ^ 2 + (sy3 - sy4) ^ 2) * 0.5
    end
    return 3
end

function M.draw_part_hull_cached(part, color, style, outline_color)
    if not part then
        return
    end
    local pos = part.Position or part.position
    local sz = part.Size or part.size
    if not (pos and sz) then
        return
    end

    local now = utility.get_tick_count()
    local parent_name = part.Parent and part.Parent.Name or ""
    local key = tostring(part) .. ":" .. parent_name .. ":" .. (part.Name or "")
    local entry = hull_cache[key]
    local px = pos.X or pos.x
    local py = pos.Y or pos.y
    local pz = pos.Z or pos.z

    local function moved(e)
        if not e then
            return true
        end
        return math.abs(e.px - px) > HULL_MOVE_EPS
            or math.abs(e.py - py) > HULL_MOVE_EPS
            or math.abs(e.pz - pz) > HULL_MOVE_EPS
    end

    if entry and entry.hull and (now - entry.tick) < HULL_CACHE_MS
        and not moved(entry) and entry.style == style then
        local hull = entry.hull
        if style == 1 then
            draw.poly_closed(hull, outline_color or color, 1.5)
        else
            draw.poly_filled(hull, color)
            if outline_color then
                draw.poly_closed(hull, outline_color, 1.5)
            end
        end
        return
    end

    local hx = (sz.X or sz.x or 0) * 0.5
    local hy = (sz.Y or sz.y or 0) * 0.5
    local hz = (sz.Z or sz.z or 0) * 0.5
    local rv = part.RightVector or part.right_vector
    local uv = part.UpVector or part.up_vector
    local lv = part.LookVector or part.look_vector
    local pxv = pos.X or pos.x
    local pyv = pos.Y or pos.y
    local pzv = pos.Z or pos.z

    local corners = {}
    if rv and uv and lv and rv.X and uv.X and lv.X then
        corners = {
            {pxv + rv.X * -hx + uv.X * -hy + lv.X * -hz, pyv + rv.Y * -hx + uv.Y * -hy + lv.Y * -hz, pzv + rv.Z * -hx + uv.Z * -hy + lv.Z * -hz},
            {pxv + rv.X *  hx + uv.X * -hy + lv.X * -hz, pyv + rv.Y *  hx + uv.Y * -hy + lv.Y * -hz, pzv + rv.Z *  hx + uv.Z * -hy + lv.Z * -hz},
            {pxv + rv.X * -hx + uv.X *  hy + lv.X * -hz, pyv + rv.Y * -hx + uv.Y *  hy + lv.Y * -hz, pzv + rv.Z * -hx + uv.Z *  hy + lv.Z * -hz},
            {pxv + rv.X *  hx + uv.X *  hy + lv.X * -hz, pyv + rv.Y *  hx + uv.Y *  hy + lv.Y * -hz, pzv + rv.Z *  hx + uv.Z *  hy + lv.Z * -hz},
            {pxv + rv.X * -hx + uv.X * -hy + lv.X *  hz, pyv + rv.Y * -hx + uv.Y * -hy + lv.Y *  hz, pzv + rv.Z * -hx + uv.Z * -hy + lv.Z *  hz},
            {pxv + rv.X *  hx + uv.X * -hy + lv.X *  hz, pyv + rv.Y *  hx + uv.Y * -hy + lv.Y *  hz, pzv + rv.Z *  hx + uv.Z * -hy + lv.Z *  hz},
            {pxv + rv.X * -hx + uv.X *  hy + lv.X *  hz, pyv + rv.Y * -hx + uv.Y *  hy + lv.Y *  hz, pzv + rv.Z * -hx + uv.Z *  hy + lv.Z *  hz},
            {pxv + rv.X *  hx + uv.X *  hy + lv.X *  hz, pyv + rv.Y *  hx + uv.Y *  hy + lv.Y *  hz, pzv + rv.Z *  hx + uv.Z *  hy + lv.Z *  hz},
        }
    else
        corners = {
            {pxv - hx, pyv - hy, pzv - hz},
            {pxv + hx, pyv - hy, pzv - hz},
            {pxv - hx, pyv + hy, pzv - hz},
            {pxv + hx, pyv + hy, pzv - hz},
            {pxv - hx, pyv - hy, pzv + hz},
            {pxv + hx, pyv - hy, pzv + hz},
            {pxv - hx, pyv + hy, pzv + hz},
            {pxv + hx, pyv + hy, pzv + hz},
        }
    end

    local screen_points = {}
    for _, cp in ipairs(corners) do
        local sx, sy, v
        if draw and draw.world_to_screen then
            sx, sy, v = draw.world_to_screen(cp[1], cp[2], cp[3])
        else
            sx, sy, v = utility.world_to_screen(cp[1], cp[2], cp[3])
        end
        if v then
            screen_points[#screen_points + 1] = {sx, sy}
        end
    end
    if #screen_points < 3 then
        return
    end
    local hull = draw.compute_hull(screen_points)
    if not hull then
        return
    end

    hull_cache[key] = {
        hull = hull,
        tick = now,
        px = px,
        py = py,
        pz = pz,
        style = style
    }
    trim_hull_cache()

    if style == 1 then
        draw.poly_closed(hull, outline_color or color, 1.5)
    else
        draw.poly_filled(hull, color)
        if outline_color then
            draw.poly_closed(hull, outline_color, 1.5)
        end
    end
end

function M.draw_3d_box(bbox, col)
    if not bbox then
        return
    end
    local bb = {
        {bbox[1], bbox[2], bbox[3]},
        {bbox[4], bbox[2], bbox[3]},
        {bbox[4], bbox[5], bbox[3]},
        {bbox[1], bbox[5], bbox[3]},
        {bbox[1], bbox[2], bbox[6]},
        {bbox[4], bbox[2], bbox[6]},
        {bbox[4], bbox[5], bbox[6]},
        {bbox[1], bbox[5], bbox[6]}
    }
    local bb2, av = {}, false
    for i = 1, 8 do
        local sx, sy, vis = utility.world_to_screen(bb[i][1], bb[i][2], bb[i][3])
        bb2[i] = {sx, sy, vis}
        if vis then
            av = true
        end
    end
    if av then
        local edg = {{1, 2}, {2, 3}, {3, 4}, {4, 1}, {5, 6}, {6, 7}, {7, 8}, {8, 5}, {1, 5}, {2, 6}, {3, 7}, {4, 8}}
        for _, e in ipairs(edg) do
            local c1, c2 = bb2[e[1]], bb2[e[2]]
            if c1[3] and c2[3] then
                draw.line(c1[1], c1[2], c2[1], c2[2], col, 1.5)
            end
        end
    end
end

function M.draw_part_hull(b, color, style, outline_color)
    if not (b and b.Position and b.Size) then return end
    
    local pos = b.position or b.Position
    local sz = b.size or b.Size
    local rv, uv, lv = b.right_vector, b.up_vector, b.look_vector
    
    if pos and sz and rv and uv and lv then
        local hx, hy, hz = sz.x * 0.5, sz.y * 0.5, sz.z * 0.5
        local corners = {
            pos + rv * -hx + uv * -hy + lv * -hz,
            pos + rv *  hx + uv * -hy + lv * -hz,
            pos + rv * -hx + uv *  hy + lv * -hz,
            pos + rv *  hx + uv *  hy + lv * -hz,
            pos + rv * -hx + uv * -hy + lv *  hz,
            pos + rv *  hx + uv * -hy + lv *  hz,
            pos + rv * -hx + uv *  hy + lv *  hz,
            pos + rv *  hx + uv *  hy + lv *  hz
        }
        local screen_points = {}
        for _, cp in ipairs(corners) do
            local sx, sy, v = draw.world_to_screen(cp.x, cp.y, cp.z)
            if v then
                screen_points[#screen_points + 1] = {sx, sy}
            end
        end
        if #screen_points >= 3 then
            local hull = draw.compute_hull(screen_points)
            if style == 1 then
                draw.poly_closed(hull, outline_color or color, 1.5)
            else
                draw.poly_filled(hull, color)
                if outline_color then
                    draw.poly_closed(hull, outline_color, 1.5)
                end
            end
        end
    end
end

function M.draw_box(bx, by, bw, bh, col, fill, btype, bbox)
    if fill then
        local fc = s.box_fill_color
        draw.rect_filled(bx, by, bw, bh, {fc[1], fc[2], fc[3], s.box_fill_opacity * 0.01})
    end
    if btype == BOX_TYPE.STANDARD then
        draw.rect(bx, by, bw, bh, col, 0, 1)
    elseif btype == BOX_TYPE.CORNER then
        local cl = min(bw, bh) * 0.25
        draw.line(bx, by, bx + cl, by, col, 2)
        draw.line(bx, by, bx, by + cl, col, 2)
        draw.line(bx + bw - cl, by, bx + bw, by, col, 2)
        draw.line(bx + bw, by, bx + bw, by + cl, col, 2)
        draw.line(bx, by + bh - cl, bx, by + bh, col, 2)
        draw.line(bx, by + bh, bx + cl, by + bh, col, 2)
        draw.line(bx + bw - cl, by + bh, bx + bw, by + bh, col, 2)
        draw.line(bx + bw, by + bh - cl, bx + bw, by + bh, col, 2)
    elseif btype == BOX_TYPE.THREE_D and bbox then
        M.draw_3d_box(bbox, col)
    end
end

function M.draw_segmented_line(sx, sy, ex, ey, col, style)
    if style == VIEW_LINE_STYLE.SOLID then
        draw.line(sx, sy, ex, ey, col, 2)
    elseif style == VIEW_LINE_STYLE.DASHED then
        for i = 0, 4 do
            local t1, t2 = i / 5, (i + 0.5) / 5
            draw.line(sx + (ex - sx) * t1, sy + (ey - sy) * t1, sx + (ex - sx) * t2, sy + (ey - sy) * t2, col, 2)
        end
    elseif style == VIEW_LINE_STYLE.FADE then
        for i = 0, 19 do
            local t1, t2 = i / 20, (i + 1) / 20
            draw.line(
                sx + (ex - sx) * t1,
                sy + (ey - sy) * t1,
                sx + (ex - sx) * t2,
                sy + (ey - sy) * t2,
                {col[1], col[2], col[3], col[4] * (1 - t1)},
                2
            )
        end
    end
end

function M.draw_tracer(ox, oy, tx, ty, col, style)
    if style == TRACER_STYLE.SOLID then
        draw.line(ox, oy, tx, ty, col, 1.5)
    elseif style == TRACER_STYLE.DASHED then
        for i = 0, 9 do
            local t1, t2 = i / 10, (i + 0.5) / 10
            draw.line(
                ox + (tx - ox) * t1, oy + (ty - oy) * t1,
                ox + (tx - ox) * t2, oy + (ty - oy) * t2,
                col, 1.5
            )
        end
    elseif style == TRACER_STYLE.DOTTED then
        for i = 0, 19 do
            local t = i / 20
            draw.circle_filled(ox + (tx - ox) * t, oy + (ty - oy) * t, 2, col)
        end
    end
 end

return M

end)()

-- ── game/world_scan.lua ──
June._mods["game.world_scan"] = (function()
--[[ World gadget scan — workspace + map cameras, per-type lifecycle from game dump. ]]

local draw_util = June.require("core.draw_util")
local world_items = June.require("game.world_items")
local gadget_team = June.require("game.gadget_team")
local gadget_lifecycle = June.require("game.gadget_lifecycle")
local shootable_gadgets = June.require("game.shootable_gadgets")

local M = {}

local bbox_from_part = draw_util.bbox_from_part
local get_world_item_position = draw_util.get_world_item_position
local dist3d_sq = draw_util.dist3d_sq

local GADGET_BBOX_MAX_PARTS = 12

local map_camera_folders = nil
local map_camera_folders_at = 0
local MAP_CAMERA_FOLDER_MS = 5000

local TARGETABLE_UTILITIES = {
    DRONE = true,
    C4 = true,
    CLAYMORE = true,
    JAMMER = true,
    STICKY = true,
    ["STICKY CAM"] = true,
    BREACH = true,
    CAMERA = true,
    ["MAP CAM"] = true,
    ["HARD BREACH"] = true,
    ["PROX ALARM"] = true,
    ["BP CAMERA"] = true,
    ["BP CAM"] = true,
    FLASH = true,
    STUN = true,
    FRAG = true,
    SMOKE = true,
    EMP = true,
    IMPACT = true,
    INCENDIARY = true,
}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

function M.inst_key(obj)
    if not obj then
        return nil
    end
    local addr = obj.address or obj.Address
    if addr then
        return tostring(addr)
    end
    return tostring(obj)
end

local function is_valid(inst)
    if not inst then
        return false
    end
    if utility and utility.is_valid then
        return utility.is_valid(inst)
    end
    return true
end

local function unpack_pos(pos)
    if not pos then
        return nil
    end
    local x = pos.X or pos.x
    local y = pos.Y or pos.y
    local z = pos.Z or pos.z
    if not x then
        return nil
    end
    return x, y, z
end

local function gadget_bbox(item, anchor)
    if anchor then
        return bbox_from_part(anchor)
    end
    return nil
end

local function get_map_camera_folders(ws)
    local now = tick_ms()
    if map_camera_folders and now - map_camera_folders_at < MAP_CAMERA_FOLDER_MS then
        return map_camera_folders
    end

    local folders = {}
    if not is_valid(ws) then
        map_camera_folders = folders
        map_camera_folders_at = now
        return folders
    end

    local model_root = ws:FindFirstChild("Model")
    if model_root and is_valid(model_root) then
        for _, map_child in ipairs(model_root:GetChildren()) do
            if is_valid(map_child) then
                local cams = map_child:FindFirstChild("DefaultCameras")
                if cams and is_valid(cams) then
                    folders[#folders + 1] = cams
                end
            end
        end
    end

    map_camera_folders = folders
    map_camera_folders_at = now
    return folders
end

local function should_scan_item(item, s, utilities_active, gadget_aim_active)
    if s[item.enabled] then
        return true
    end
    if gadget_aim_active and shootable_gadgets.is_shootable_item(item) then
        return true
    end
    if utilities_active and TARGETABLE_UTILITIES[item.label] then
        return true
    end
    return false
end

local function in_draw_range(dsq, max_sq, hide_sq, dynamic, for_aim)
    if dsq > max_sq then
        return false
    end
    if for_aim or dynamic then
        return true
    end
    return dsq > hide_sq
end

local function remove_entry(cache, entry)
    if entry.key then
        cache.world_lookup[entry.key] = nil
    end
    if entry.obj then
        cache.world_lookup[entry.obj] = nil
    end
end

local function add_entry(cache, entry)
    cache.world[#cache.world + 1] = entry
    if entry.key then
        cache.world_lookup[entry.key] = entry
    end
    if entry.obj then
        cache.world_lookup[entry.obj] = entry
    end
end

local function make_entry(obj, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, camera_item, for_aim)
    local scan_item = camera_item or item
    local anchor = gadget_lifecycle.find_anchor(obj, scan_item)
    if not anchor or not gadget_lifecycle.is_trackable(obj, scan_item, ws, anchor) then
        return nil
    end

    local pos, sz = get_world_item_position(obj, scan_item)
    if not pos then
        local x, y, z = unpack_pos(anchor.Position or anchor.position)
        if not x then
            return nil
        end
        pos = {X = x, Y = y, Z = z}
        sz = anchor.Size or anchor.size
    end

    local px, py, pz = unpack_pos(pos)
    if not px then
        return nil
    end

    local dsq = dist3d_sq(px, py, pz, cam_x, cam_y, cam_z)
    local is_dynamic = (item and item.dynamic == true) or for_aim
    if not in_draw_range(dsq, max_sq, hide_sq, is_dynamic, for_aim) then
        return nil
    end

    local label = item and item.label or (camera_item and camera_item.label) or obj.Name
    if camera_item then
        label = gadget_lifecycle.camera_status_label(obj, label, anchor)
    end

    local enabled_key = (camera_item and camera_item.enabled) or (item and item.enabled)
    local color_key = (camera_item and camera_item.color_key) or enabled_key

    return {
        x = px,
        y = py,
        z = pz,
        size = sz,
        bbox = gadget_bbox(scan_item, anchor),
        label = label,
        color = s[color_key .. "_color"] or {1, 1, 1, 1},
        obj = obj,
        item = camera_item or item,
        anchor = anchor,
        is_esp = enabled_key and s[enabled_key] == true,
        kind = (camera_item and camera_item.model_name) or (item and item.name),
        dist = sqrt(dsq),
        dsq = dsq,
        key = M.inst_key(obj),
        dynamic = item and item.dynamic == true,
        static = (item and item.static == true) or (camera_item and camera_item.static == true),
        map_only = camera_item and camera_item.map_only == true,
        is_teammate_gadget = gadget_team.is_friendly_gadget(obj),
        is_broken = gadget_lifecycle.is_broken(obj, scan_item, anchor),
    }
end

local function prune_entries(cache, match_fn, alive_fn, seen)
    for i = #cache.world, 1, -1 do
        local w = cache.world[i]
        if match_fn(w) then
            local tracked = w.key and seen[w.key]
            local alive = w.obj and alive_fn(w.obj, w.item)
            if not alive or not tracked then
                remove_entry(cache, w)
                table.remove(cache.world, i)
            end
        end
    end
end

function M.get_max_sq(s, utilities_active)
    local max_dist = s.world_max_distance
    if utilities_active then
        max_dist = math.max(max_dist, s.utilities_max_distance)
    end
    return max_dist * max_dist
end

function M.sync_workspace(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt, gadget_aim_active)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active or gadget_aim_active)
    local lookup = world_items.world_items_by_name
    local for_aim = gadget_aim_active == true

    if not is_valid(ws) then
        return
    end

    for _, child in ipairs(ws:GetChildren()) do
        local item = lookup[child.Name]
        if item and should_scan_item(item, s, utilities_active, gadget_aim_active) then
            if is_valid(child) then
                local key = M.inst_key(child)
                if key then
                    seen[key] = true
                    if not cache.world_lookup[key] then
                        local entry = make_entry(child, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, nil, for_aim)
                        if entry then
                            add_entry(cache, entry)
                        end
                    end
                end
            end
        end
    end

    prune_entries(cache, function(w)
        return w.item and w.item.name and not w.map_only
    end, function(obj, item)
        return gadget_lifecycle.is_trackable(obj, item, ws, nil)
    end, seen)
end

function M.sync_map_cameras(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt, gadget_aim_active)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active or gadget_aim_active)
    local default_camera = world_items.camera_items_by_name.DefaultCamera
    local for_aim = gadget_aim_active == true

    if not default_camera then
        return
    end

    local enabled = s[default_camera.enabled]
        or (utilities_active and TARGETABLE_UTILITIES["MAP CAM"])
        or (gadget_aim_active and shootable_gadgets.is_shootable_item(default_camera))

    if not enabled then
        for i = #cache.world, 1, -1 do
            local w = cache.world[i]
            if w.map_only then
                remove_entry(cache, w)
                table.remove(cache.world, i)
            end
        end
        return
    end

    for _, folder in ipairs(get_map_camera_folders(ws)) do
        if is_valid(folder) then
            for _, child in ipairs(folder:GetChildren()) do
                if is_valid(child) and child.Name == "DefaultCamera" then
                    local key = M.inst_key(child)
                    if key then
                        seen[key] = true
                        if not cache.world_lookup[key] then
                            local entry = make_entry(child, nil, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, default_camera, for_aim)
                            if entry then
                                add_entry(cache, entry)
                            end
                        end
                    end
                end
            end
        end
    end

    prune_entries(cache, function(w)
        return w.map_only == true
    end, function(obj, item)
        return gadget_lifecycle.is_map_camera_placed(obj, ws)
            and not gadget_lifecycle.is_camera_broken(obj, nil, nil)
    end, seen)
end

function M.refresh_entry_position(entry, cam_x, cam_y, cam_z, sqrt)
    if not entry or not entry.obj or not is_valid(entry.obj) then
        return false
    end

    local anchor = entry.anchor
    if not anchor or not is_valid(anchor) then
        anchor = gadget_lifecycle.find_anchor(entry.obj, entry.item)
        if not anchor then
            return false
        end
        entry.anchor = anchor
    end

    local x, y, z
    if entry.map_only then
        x, y, z = unpack_pos(anchor.Position or anchor.position)
    else
        local pos = get_world_item_position(entry.obj, entry.item)
        if pos then
            x, y, z = unpack_pos(pos)
        else
            x, y, z = unpack_pos(anchor.Position or anchor.position)
        end
    end

    if not x then
        return false
    end

    entry.x = x
    entry.y = y
    entry.z = z
    local dsq = dist3d_sq(x, y, z, cam_x, cam_y, cam_z)
    entry.dsq = dsq
    entry.dist = sqrt(dsq)

    if entry.dynamic or entry.map_only then
        entry.bbox = gadget_bbox(entry.item, anchor)
    end
    return true
end

function M.refresh_positions(cache, cam_x, cam_y, cam_z, sqrt, only_dynamic)
    for i = 1, #cache.world do
        local w = cache.world[i]
        if not only_dynamic or w.dynamic then
            M.refresh_entry_position(w, cam_x, cam_y, cam_z, sqrt)
        end
    end
end

function M.prune_lifecycle(cache, ws, refresh_team)
    for i = #cache.world, 1, -1 do
        local w = cache.world[i]
        local item = w.item
        local anchor = w.anchor
        if not is_valid(w.obj) or not gadget_lifecycle.is_trackable(w.obj, item, ws, anchor) then
            remove_entry(cache, w)
            table.remove(cache.world, i)
        else
            w.is_broken = gadget_lifecycle.is_broken(w.obj, item, anchor)
            if w.map_only and item then
                w.label = gadget_lifecycle.camera_status_label(w.obj, item.label, anchor)
            end
            if refresh_team then
                w.is_teammate_gadget = gadget_team.is_friendly_gadget(w.obj)
            end
        end
    end
end

function M.refresh_flags(cache_or_entry, s)
    local entries = cache_or_entry
    if cache_or_entry and cache_or_entry.world then
        entries = cache_or_entry.world
        for i = 1, #entries do
            M.refresh_flags(entries[i], s)
        end
        return
    end

    local entry = cache_or_entry
    if entry.map_only and entry.item then
        entry.is_esp = s[entry.item.enabled] == true
        entry.color = s[entry.item.color_key .. "_color"] or entry.color
        return
    end
    if entry.item and entry.item.enabled then
        entry.is_esp = s[entry.item.enabled] == true
        entry.color = s[entry.item.enabled .. "_color"] or entry.color
    end
end

return M

end)()

-- ── core/silent_ray.lua ──
June._mods["core.silent_ray"] = (function()
--[[ Silent raycast hook — Vector API track_silent_target (see docs/API.md). ]]

local env = June.require("core.env")

local M = {}

local hook_ready = false
local tracking = false
local MOUSE_RAY_LEN = 1024

M._last_origin = nil
M._last_target = nil
M._last_ok = false

local function unpack_pos(v)
    if not v then return nil end
    if v.x ~= nil then return v.x, v.y, v.z end
    if v.X ~= nil then return v.X, v.Y, v.Z end
    return nil
end

local function make_vec3(x, y, z)
    if Vector3 and Vector3.new then
        return Vector3.new(x, y, z)
    end
    return { x = x, y = y, z = z }
end

function M.available()
    return raycast
        and raycast.track_silent_target
        and raycast.stop_silent_tracking
end

function M.ensure_hook()
    if not M.available() then return false end
    if hook_ready or (raycast.is_silent_hook_active and raycast.is_silent_hook_active()) then
        hook_ready = true
        return true
    end
    if not raycast.enable_silent_hook then
        hook_ready = true
        return true
    end
    local ok = raycast.enable_silent_hook()
    hook_ready = ok == true
    return hook_ready
end

function M.is_tracking()
    return tracking
end

function M.get_camera_origin()
    if camera and camera.get_position then
        local ok, pos = pcall(camera.get_position)
        if ok and pos then
            local x, y, z = unpack_pos(pos)
            if x then
                return { x = x, y = y, z = z }
            end
        end
    end

    local ws = env.get_workspace()
    if ws then
        local cam = ws:FindFirstChild("Camera")
        if cam and cam.CFrame and cam.CFrame.Position then
            local pos = cam.CFrame.Position
            return { x = pos.X, y = pos.Y, z = pos.Z }
        end
    end

    return nil
end

function M.stop()
    M._last_origin = nil
    M._last_target = nil
    M._last_ok = false
    tracking = false
    if not M.available() then return end
    pcall(raycast.stop_silent_tracking)
    if raycast.clear_silent_target then
        pcall(raycast.clear_silent_target)
    end
end

function M.last_segment()
    return M._last_origin, M._last_target
end

function M.track(origin, aim_point, shoot_vk)
    M._last_ok = false
    if not aim_point then return false end

    origin = origin or M.get_camera_origin()
    if not origin then return false end
    if not M.ensure_hook() then return false end

    local ox, oy, oz = unpack_pos(origin)
    local ax, ay, az = unpack_pos(aim_point)
    if not ox or not ax then return false end

    local dx, dy, dz = ax - ox, ay - oy, az - oz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    local dir

    if dist < 0.001 then
        local cam = M.get_camera_origin()
        if cam then
            dx, dy, dz = cam.x - ox, cam.y - oy, cam.z - oz
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        if not dist or dist < 0.001 then
            dir = make_vec3(0, MOUSE_RAY_LEN * 0.01, 0)
        else
            local inv = 1 / dist
            dir = make_vec3(dx * inv * MOUSE_RAY_LEN, dy * inv * MOUSE_RAY_LEN, dz * inv * MOUSE_RAY_LEN)
        end
    else
        local inv = 1 / dist
        dir = make_vec3(dx * inv * MOUSE_RAY_LEN, dy * inv * MOUSE_RAY_LEN, dz * inv * MOUSE_RAY_LEN)
    end

    M._last_origin = { x = ox, y = oy, z = oz }
    M._last_target = { x = ax, y = ay, z = az }

    local origin_v = make_vec3(ox, oy, oz)
    local key = shoot_vk or 0x01

    local ok = raycast.track_silent_target(origin_v, dir, key) == true
    if ok and raycast.set_silent_target then
        pcall(raycast.set_silent_target, origin_v, dir)
    end

    M._last_ok = ok
    tracking = ok
    return ok
end

return M

end)()

-- ── core/vis_util.lua ──
June._mods["core.vis_util"] = (function()
--[[ Line-of-sight helpers — raycast.cast (fail-closed) with gadget target matching. ]]

local silent_ray = June.require("core.silent_ray")

local M = {}

function M.part_of(inst, root)
    if not inst or not root then
        return false
    end
    local p = inst
    while p do
        if p == root then
            return true
        end
        p = p.Parent or p.parent
    end
    return false
end

function M.ray_origin()
    local o = silent_ray.get_camera_origin()
    if o then
        return o.x, o.y, o.z
    end
    return nil
end

function M.aim_point(entry)
    if not entry then
        return nil
    end
    local anchor = entry.anchor
    if anchor and anchor.Position then
        local p = anchor.Position
        return p.X or p.x, p.Y or p.y, p.Z or p.z
    end
    if entry.x then
        return entry.x, entry.y, entry.z
    end
    return nil
end

function M.can_see_world_point(tx, ty, tz, target_root)
    if not raycast then
        return true
    end
    if raycast.is_ready and not raycast.is_ready() then
        return false
    end

    local ox, oy, oz = M.ray_origin()
    if not ox or not tx then
        return false
    end

    if raycast.cast then
        local hit, _, _, inst = raycast.cast(ox, oy, oz, tx, ty, tz)
        if not hit then
            return true
        end
        if target_root and inst and M.part_of(inst, target_root) then
            return true
        end
        return false
    end

    if raycast.is_visible then
        return raycast.is_visible(ox, oy, oz, tx, ty, tz) == true
    end

    return true
end

function M.can_see_entry(entry)
    if not entry then
        return false
    end
    local tx, ty, tz = M.aim_point(entry)
    if not tx then
        return false
    end
    return M.can_see_world_point(tx, ty, tz, entry.obj)
end

return M

end)()

-- ── features/combat/silent_resolve.lua ──
June._mods["features.combat.silent_resolve"] = (function()
--[[ Silent ray origin — camera to target (hitscan). ]]

local silent_ray = June.require("core.silent_ray")

local M = {}

function M.resolve_track(aim)
    if not aim then
        return nil, nil
    end

    local camera = silent_ray.get_camera_origin()
    if not camera then
        return nil, nil
    end

    return camera, aim
end

return M

end)()

-- ── features/utility/config.lua ──
June._mods["features.utility.config"] = (function()
local menu_defs = June.require("menu.menu_defs")
local menu_util = June.require("core.menu_util")

local M = {}
local menu_items = menu_defs.menu_items

local AUTOLOAD_FILE = 'JuneAutoload.txt'

local function cfg_path(name)
    if not name or name == '' then name = 'default' end
    if not name:lower():find('[.]') then
        name = name .. '.txt'
    end
    return name
end

local function save_cfg(name)
    local cfg_name = name or menu.get('config_name_input') or 'default'
    local path = cfg_path(cfg_name)
    local f = io.open(path, 'w')
    if not f then
        print('[June] Save failed - could not open: ' .. path)
        return false
    end
    for _, m in ipairs(menu_items) do
        if not m.id then
            goto continue
        end
        if m.t == 'checkbox' then
            local v = menu.get(m.id)
            if v ~= nil then
                f:write(m.id .. '=' .. (v and '1' or '0') .. '\n')
            end
        elseif m.t == 'slider_int' or m.t == 'slider_float' or m.t == 'combo' then
            local v = menu.get(m.id)
            if v ~= nil then f:write(m.id .. '=' .. tostring(v) .. '\n') end
        elseif m.t == 'multicombo' then
            local v = menu.get(m.id)
            if v then
                local parts = {}
                for i, val in ipairs(v) do parts[i] = val and '1' or '0' end
                f:write(m.id .. '=' .. table.concat(parts, ',') .. '\n')
            end
        elseif m.t == 'hotkey' then
            local k = menu.get_key(m.id)
            if k then f:write(m.id .. '=' .. tostring(k) .. '\n') end
        elseif m.t == 'colorpicker' then
            local c = menu.get_color(m.id)
            if c and #c >= 4 then
                f:write(string.format('%s=%.4f,%.4f,%.4f,%.4f\n', m.id, c[1], c[2], c[3], c[4]))
            end
        end
        -- Inline colorpicker attached to a non-colorpicker item
        if m.c and m.t ~= 'colorpicker' then
            local c = menu.get_color(m.id)
            if c and #c >= 4 then
                f:write(string.format('%s_color=%.4f,%.4f,%.4f,%.4f\n', m.id, c[1], c[2], c[3], c[4]))
            end
        end
        ::continue::
    end
    f:close()
    -- Always write autoload marker
    local af = io.open(AUTOLOAD_FILE, 'w')
    if af then af:write(cfg_name) af:close() end
    print('[June] Config saved: ' .. path)
    return true
end

local function load_cfg(name)
    local cfg_name = name or menu.get('config_name_input') or 'default'
    local path = cfg_path(cfg_name)
    local f = io.open(path, 'r')
    if not f then
        -- Silently fail if file doesn't exist (normal on first run)
        return false
    end
    local data = {}
    for line in f:lines() do
        local k, v = line:match('^([^=]+)=(.-)%s*$')
        if k then data[k] = v end
    end
    f:close()
    local count = 0
    for _, m in ipairs(menu_items) do
        if not m.id then
            goto continue
        end
        if data[m.id] ~= nil then
            if m.t == 'checkbox' then
                menu.set(m.id, data[m.id] == '1')
                count = count + 1
            elseif m.t == 'slider_int' or m.t == 'slider_float' then
                local n = tonumber(data[m.id])
                if n then menu.set(m.id, n) count = count + 1 end
            elseif m.t == 'combo' then
                local n = tonumber(data[m.id])
                if n then menu.set(m.id, n) count = count + 1 end
            elseif m.t == 'multicombo' then
                local vals = {}
                for val in data[m.id]:gmatch('[^,]+') do
                    vals[#vals+1] = val == '1'
                end
                menu.set(m.id, vals)
                count = count + 1
            elseif m.t == 'hotkey' then
                local k = tonumber(data[m.id])
                if k then menu.set_key(m.id, k) count = count + 1 end
            elseif m.t == 'colorpicker' then
                local r,g,b,a = data[m.id]:match('([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)')
                if r then
                    menu.set_color(m.id, {tonumber(r),tonumber(g),tonumber(b),tonumber(a)})
                    count = count + 1
                end
            end
        end
        -- Inline colorpicker
        if m.c and m.t ~= 'colorpicker' then
            local ckey = m.id .. '_color'
            if data[ckey] then
                local r,g,b,a = data[ckey]:match('([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)')
                if r then
                    menu.set_color(m.id, {tonumber(r),tonumber(g),tonumber(b),tonumber(a)})
                end
            end
        end
        ::continue::
    end
    if count > 0 then
        print('[June] Config loaded: ' .. path .. ' (' .. count .. ' values)')
    end
    return true
end

function M.register_menu()
    menu_util.ensure_groups()
    menu.add_separator(menu_util.TAB, menu_util.G.SETTINGS)
    menu.add_label(menu_util.TAB, menu_util.G.SETTINGS, "Config")
    menu.add_input(menu_util.TAB, menu_util.G.SETTINGS, "config_name_input", "Config Name", "default")
    menu.add_button(menu_util.TAB, menu_util.G.SETTINGS, "save_cfg_btn", "Save Config", function()
        save_cfg(menu.get("config_name_input"))
    end)
    menu.add_button(menu_util.TAB, menu_util.G.SETTINGS, "load_cfg_btn", "Load Config", function()
        load_cfg(menu.get("config_name_input"))
    end)
    menu.add_label(menu_util.TAB, menu_util.G.SETTINGS, "Configs: %LOCALAPPDATA%\\Project Vector\\Scripts")
    menu.add_checkbox(menu_util.TAB, menu_util.G.SETTINGS, "config_autoload_enabled", "Save as Autoload", false)
end

function M.autoload()
    -- Autoload on startup: try JuneAutoload.txt first, then fallback to default
    local _af = io.open(AUTOLOAD_FILE, 'r')
    if _af then
        local _aname = _af:read('*l')
        _af:close()
        if _aname and _aname ~= '' then
            if load_cfg(_aname) then
                menu.set('config_name_input', _aname)
            end
        end
    else
        load_cfg('default')
    end
end

M.save_cfg = save_cfg
M.load_cfg = load_cfg

return M

end)()

-- ── features/combat/scan.lua ──
June._mods["features.combat.scan"] = (function()
local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local world_scan = June.require("game.world_scan")
local draw_util = June.require("core.draw_util")
local shootable_gadgets = June.require("game.shootable_gadgets")
local vis_util = June.require("core.vis_util")

local sqrt, min, max = constants.sqrt, constants.min, constants.max
local DIST = constants.DIST
local AIM_TARGET = constants.AIM_TARGET
local MIN_BONES_REQUIRED = constants.MIN_BONES_REQUIRED

local M = {}

local s = settings.s
local dist3d_sq = draw_util.dist3d_sq
local is_teammate = draw_util.is_teammate
local project_bbox_screen = draw_util.project_bbox_screen

local last_char_update = 0
local last_player_discover = 0
local last_world_static = 0
local last_ws_sync = 0
local last_map_sync = 0
local last_lifecycle = 0
local last_world_flags = 0
local PLAYER_DISCOVER_MS = 200
local WORLD_STATIC_MS = 2500
local WORLD_LIFECYCLE_MS = 150
local WORLD_FLAGS_MS = 100

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function is_valid(inst)
    if not inst then
        return false
    end
    if utility and utility.is_valid then
        return utility.is_valid(inst)
    end
    return true
end

local function players_by_name(all_players)
    local lookup = {}
    for i = 1, #all_players do
        local ep = all_players[i]
        if ep and ep.name then
            lookup[ep.name] = ep
        end
    end
    return lookup
end

local function match_character(hx, hy, hz)
    local cn, cd, char_obj = nil, math.huge, nil
    for char, data in pairs(cache.char_models) do
        if data.hrp and data.hrp.Position then
            local pos = data.hrp.Position
            local dc = dist3d_sq(hx, hy, hz, pos.X, pos.Y, pos.Z)
            if dc < DIST.NAME_MATCH_SQ and dc < cd then
                cd, cn, char_obj = dc, char.Name, char
            end
        end
    end
    return cn, char_obj
end

local function read_bones(vm)
    local bns = {}
    local mnx, mny, mnz = math.huge, math.huge, math.huge
    local mxx, mxy, mxz = -math.huge, -math.huge, -math.huge
    local bc = 0
    for _, bn in ipairs(cache.bone_list) do
        local b = vm:FindFirstChild(bn)
        if b and b.Position and b.Size and b.Size.X > 0 then
            bc = bc + 1
            local bx, by, bz = b.Position.X, b.Position.Y, b.Position.Z
            local sz = b.Size
            local hx2, hy2, hz2 = sz.X * 0.5, sz.Y * 0.5, sz.Z * 0.5
            bns[bn] = {x = bx, y = by, z = bz}
            mnx, mny, mnz = min(mnx, bx - hx2), min(mny, by - hy2), min(mnz, bz - hz2)
            mxx, mxy, mxz = max(mxx, bx + hx2), max(mxy, by + hy2), max(mxz, bz + hz2)
        end
    end
    if bc < MIN_BONES_REQUIRED or mnx == math.huge then
        return nil
    end
    return bns, {mnx, mny, mnz, mxx, mxy, mxz}
end

local function update_screen(p)
    local mnx, mny, mxx, mxy, cx = project_bbox_screen(p.bbox)
    if mnx then
        p.screen_mnx = mnx
        p.screen_mny = mny
        p.screen_mxx = mxx
        p.screen_mxy = mxy
        p.screen_cx = cx
        p.screen_vis = true
    else
        p.screen_vis = false
    end
end

local function update_velocity(p, cn, head_pos, now)
    local velocity = {x = 0, y = 0, z = 0}
    local history = cache.player_history[cn]
    if history then
        local dt = (now - history.tick) / 1000
        if dt > 0 and dt < 0.2 then
            velocity.x = (head_pos.x - history.pos.x) / dt
            velocity.y = (head_pos.y - history.pos.y) / dt
            velocity.z = (head_pos.z - history.pos.z) / dt
        end
    end
    cache.player_history[cn] = {pos = head_pos, tick = now}
    return velocity
end

function M.needs_player_scan()
    local s = settings.s
    return s.players_enabled or s.aimbot_enabled or s.silent_aim_enabled
        or (s.aimbot_enabled and s.utilities_aimbot)
end

function M.update_char_models()
    if not cache.ws then
        return
    end
    local now = os.clock()
    -- Keep humanoids fresh so healthbars / death filtering stay accurate.
    local interval = (s.players_enabled and s.players_healthbar) and 0.12 or 0.35
    if now - last_char_update < interval then
        return
    end
    last_char_update = now

    local new_cache = {}
    for _, c in ipairs(cache.ws:GetChildren()) do
        if c.ClassName == "Model" then
            local hrp = c:FindFirstChild("HumanoidRootPart")
            local hum = c:FindFirstChild("Humanoid")
            if not hum and c.FindFirstChildOfClass then
                hum = c:FindFirstChildOfClass("Humanoid")
            end
            if hrp and hrp.Position and hum then
                new_cache[c] = {hrp = hrp, hum = hum}
            end
        end
    end
    cache.char_models = new_cache
end

local function read_live_health(p, hx, hy, hz)
    local hp, mhp = p.health, p.max_health
    local alive = true

    -- Prefer Vector entity live reads (updated every access).
    local ep = p.player_obj
    if ep then
        if ep.health ~= nil then
            hp = ep.health
        end
        if ep.max_health ~= nil and ep.max_health > 0 then
            mhp = ep.max_health
        end
        if ep.is_alive == false then
            alive = false
        end
    end

    -- Re-bind character model when the old one goes invalid / respawns.
    if (not p.char_obj or not is_valid(p.char_obj) or not cache.char_models[p.char_obj]) and hx then
        local _, char_obj = match_character(hx, hy, hz)
        if char_obj then
            p.char_obj = char_obj
        end
    end

    local data = p.char_obj and cache.char_models[p.char_obj]
    local hum = data and data.hum
    if (not hum or not is_valid(hum)) and p.char_obj and is_valid(p.char_obj) then
        hum = p.char_obj:FindFirstChild("Humanoid")
        if not hum and p.char_obj.FindFirstChildOfClass then
            hum = p.char_obj:FindFirstChildOfClass("Humanoid")
        end
        if hum and data then
            data.hum = hum
        end
    end
    if hum then
        local ok_h, live_hp = pcall(function() return hum.Health end)
        local ok_m, live_mhp = pcall(function() return hum.MaxHealth end)
        if ok_h and live_hp ~= nil then
            hp = live_hp
        end
        if ok_m and live_mhp ~= nil and live_mhp > 0 then
            mhp = live_mhp
        end
    end

    hp = tonumber(hp) or 0
    mhp = tonumber(mhp) or 100
    if mhp < 1 then mhp = 100 end
    if hp <= 0 then
        alive = false
    end

    p.health = hp
    p.max_health = mhp
    p.is_alive = alive
    return alive, hp, mhp
end

local function discover_player_from_vm(vm, cam_x, cam_y, cam_z, player_lookup)
    local h, t = vm:FindFirstChild("head"), vm:FindFirstChild("torso")
    if not h or not h.Position or not t or not t.Position or (t.Transparency and t.Transparency >= 1) then
        return nil
    end
    local tsz = t.Size
    if not tsz or tsz.X <= 0.1 or tsz.Y <= 0.1 or tsz.Z <= 0.1 then
        return nil
    end

    local hx, hy, hz = h.Position.X, h.Position.Y, h.Position.Z
    local dsq = dist3d_sq(hx, hy, hz, cam_x, cam_y, cam_z)
    if dsq > DIST.MAX_PLAYER_SQ or dsq <= DIST.ESP_HIDE_SQ then
        return nil
    end

    local cn, char_obj = match_character(hx, hy, hz)
    if not cn then
        return nil
    end

    local p_obj = player_lookup[cn]
    local entry = {
        name = cn,
        health = 100,
        max_health = 125,
        is_alive = true,
        char_obj = char_obj,
        player_obj = p_obj,
    }
    local alive = read_live_health(entry, hx, hy, hz)
    if not alive then
        return nil
    end

    local bns, bbox = read_bones(vm)
    if not bns then
        return nil
    end

    local wpn = nil
    for _, c in ipairs(vm:GetChildren()) do
        if c.ClassName == "Model" and not cache.body_part_names[c.Name] then
            wpn = c.Name
            break
        end
    end

    local lv = {x = 0, y = 0, z = -1}
    if h.LookVector then
        lv = {x = h.LookVector.X, y = h.LookVector.Y, z = h.LookVector.Z}
    end

    local php = (p_obj and p_obj.head_position) and
        {x = p_obj.head_position.x, y = p_obj.head_position.y, z = p_obj.head_position.z} or
        {x = hx, y = hy, z = hz}

    local now = tick_ms()
    local velocity = update_velocity({name = cn}, cn, php, now)

    entry.dist = sqrt(dsq)
    entry.bones = bns
    entry.bbox = bbox
    entry.weapon = wpn
    entry.is_teammate = is_teammate(vm)
    entry.viewmodel = vm
    entry.look_vector = lv
    entry.is_visible = false
    entry.head_pos = php
    entry.velocity = velocity
    update_screen(entry)
    return entry
end

local function refresh_player_live(p, cam_x, cam_y, cam_z, player_lookup)
    local vm = p.viewmodel
    if not is_valid(vm) then
        return false
    end

    local h, t = vm:FindFirstChild("head"), vm:FindFirstChild("torso")
    if not h or not h.Position or not t or not t.Position or (t.Transparency and t.Transparency >= 1) then
        return false
    end

    local hx, hy, hz = h.Position.X, h.Position.Y, h.Position.Z
    local dsq = dist3d_sq(hx, hy, hz, cam_x, cam_y, cam_z)
    if dsq > DIST.MAX_PLAYER_SQ or dsq <= DIST.ESP_HIDE_SQ then
        return false
    end

    local bns, bbox = read_bones(vm)
    if not bns then
        return false
    end

    p.bones = bns
    p.bbox = bbox
    p.dist = sqrt(dsq)

    local p_obj = player_lookup[p.name]
    p.player_obj = p_obj

    local alive = read_live_health(p, hx, hy, hz)
    if not alive then
        return false
    end

    if h.LookVector then
        p.look_vector = {x = h.LookVector.X, y = h.LookVector.Y, z = h.LookVector.Z}
    end

    local php = (p_obj and p_obj.head_position) and
        {x = p_obj.head_position.x, y = p_obj.head_position.y, z = p_obj.head_position.z} or
        {x = hx, y = hy, z = hz}
    p.head_pos = php
    p.velocity = update_velocity(p, p.name, php, tick_ms())
    update_screen(p)
    return true
end

local function discover_players(cam_x, cam_y, cam_z, player_lookup)
    if not cache.ws then
        return
    end
    local vms = cache.ws:FindFirstChild("Viewmodels")
    if not vms then
        return
    end

    local seen_vm, seen_name = {}, {}
    for i = 1, #cache.players do
        local p = cache.players[i]
        seen_vm[p.viewmodel] = true
        seen_name[p.name] = true
    end

    for _, vm in ipairs(vms:GetChildren()) do
        if vm.Name == "Viewmodel" and is_valid(vm) and not seen_vm[vm] then
            local entry = discover_player_from_vm(vm, cam_x, cam_y, cam_z, player_lookup)
            if entry and not seen_name[entry.name] then
                cache.players[#cache.players + 1] = entry
                seen_vm[vm] = true
                seen_name[entry.name] = true
            end
        end
    end
end

local function update_visibility(cam_x, cam_y, cam_z)
    if #cache.players == 0 then
        return
    end

    local need_any_vis = (s.aimbot_vischeck and s.aimbot_enabled)
        or (s.silent_filter_visible and s.silent_aim_enabled)
        or (s.players_visible_override and s.players_enabled)
    if not need_any_vis then
        return
    end

    local min_val = math.huge
    local closest_p = nil
    local cx, cy = cache.screen_w * 0.5, cache.screen_h * 0.5

    for i = 1, #cache.players do
        local p = cache.players[i]
        p.is_visible = false
        local valid_for_esp = s.players_enabled and (s.players_team or not p.is_teammate)
        local valid_for_aim = s.aimbot_enabled and (not s.aimbot_team_check or not p.is_teammate)
        local valid_for_silent = s.silent_aim_enabled and (not s.silent_filter_team or not p.is_teammate)
        local need_vis = (s.aimbot_vischeck and valid_for_aim)
            or (s.silent_filter_visible and valid_for_silent)
            or (s.players_visible_override and valid_for_esp)

        if need_vis and (valid_for_esp or valid_for_aim or valid_for_silent) then
            if s.vis_check_priority == 1 and p.screen_vis then
                local dist2d = sqrt((p.screen_cx - cx) ^ 2 + (p.screen_mny - cy) ^ 2)
                if dist2d < min_val then
                    min_val = dist2d
                    closest_p = p
                end
            elseif p.dist < min_val then
                min_val = p.dist
                closest_p = p
            end
        end
    end

    if closest_p and raycast and raycast.is_visible then
        closest_p.is_visible = raycast.is_visible(
            cam_x, cam_y, cam_z,
            closest_p.head_pos.x, closest_p.head_pos.y, closest_p.head_pos.z
        )
    end
end

local function update_gadget_visibility()
    local need_gadget_vis = s.silent_filter_visible and s.silent_aim_enabled and s.silent_gadget_aim
    if not need_gadget_vis then
        for i = 1, #cache.world do
            cache.world[i].is_visible = nil
        end
        return
    end

    for i = 1, #cache.world do
        local w = cache.world[i]
        if shootable_gadgets.is_shootable_entry(w) then
            w.is_visible = vis_util.can_see_entry(w)
        else
            w.is_visible = nil
        end
    end
end

function M.scan_players()
    if not M.needs_player_scan() then
        for i = #cache.players, 1, -1 do
            cache.players[i] = nil
        end
        return
    end
    if not cache.ws then
        return
    end

    local now = tick_ms()
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z
    local all_players = entity.get_players()
    local player_lookup = players_by_name(all_players)

    for i = #cache.players, 1, -1 do
        local p = cache.players[i]
        if not refresh_player_live(p, cam_x, cam_y, cam_z, player_lookup) then
            cache.player_history[p.name] = nil
            table.remove(cache.players, i)
        end
    end

    if now - last_player_discover >= PLAYER_DISCOVER_MS then
        last_player_discover = now
        discover_players(cam_x, cam_y, cam_z, player_lookup)
    end

    update_visibility(cam_x, cam_y, cam_z)

    if s.aimbot_target_type == AIM_TARGET.DISTANCE then
        table.sort(cache.players, function(a, b)
            return a.dist < b.dist
        end)
    end
end

local TARGETABLE_UTILITIES = {
    DRONE = true,
    C4 = true,
    CLAYMORE = true,
    JAMMER = true,
    STICKY = true,
    ["STICKY CAM"] = true,
    BREACH = true,
    CAMERA = true,
    ["MAP CAM"] = true,
    ["HARD BREACH"] = true,
    ["PROX ALARM"] = true,
    ["BP CAMERA"] = true,
    ["BP CAM"] = true,
    FLASH = true,
    STUN = true,
    FRAG = true,
    SMOKE = true,
    EMP = true,
    IMPACT = true,
    INCENDIARY = true,
}

function M.needs_world_scan()
    local utilities_active = s.aimbot_enabled and s.utilities_aimbot
    local silent_gadgets = s.silent_aim_enabled and s.silent_gadget_aim
    return s.world_enabled or utilities_active or silent_gadgets
end

function M.scan_world()
    local utilities_active = s.aimbot_enabled and s.utilities_aimbot
    local silent_gadgets = s.silent_aim_enabled and s.silent_gadget_aim
    if not cache.ws or not M.needs_world_scan() then
        cache.world = {}
        cache.world_lookup = {}
        return
    end

    local now = tick_ms()
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z
    local needs_fast = utilities_active or silent_gadgets
    local gadget_aim_active = needs_fast

    if now - last_world_flags >= WORLD_FLAGS_MS then
        last_world_flags = now
        world_scan.refresh_flags(cache, s)
    end

    if cache.should_refresh_positions() then
        world_scan.refresh_positions(cache, cam_x, cam_y, cam_z, sqrt, false)
    elseif needs_fast then
        world_scan.refresh_positions(cache, cam_x, cam_y, cam_z, sqrt, true)
    end

    if now - last_lifecycle >= WORLD_LIFECYCLE_MS then
        last_lifecycle = now
        world_scan.prune_lifecycle(cache, cache.ws, s.world_team_check or s.silent_gadget_team_check)
    end

    local ws_interval = (s.world_enabled or needs_fast) and cache.WORLD_DYNAMIC_MS or cache.WORKSPACE_SCAN_MS
    if now - last_ws_sync >= ws_interval then
        last_ws_sync = now
        world_scan.sync_workspace(
            cache.ws, s, utilities_active, cache,
            cam_x, cam_y, cam_z, DIST.ESP_HIDE_SQ, sqrt, gadget_aim_active
        )
    end

    local map_interval = gadget_aim_active and cache.WORLD_DYNAMIC_MS or cache.WORLD_STATIC_MS
    if now - last_map_sync >= map_interval then
        last_map_sync = now
        world_scan.sync_map_cameras(
            cache.ws, s, utilities_active, cache,
            cam_x, cam_y, cam_z, DIST.ESP_HIDE_SQ, sqrt, gadget_aim_active
        )
        if now - last_world_static >= WORLD_STATIC_MS then
            last_world_static = now
            cache.stats.last_world_scan = now
        end
    end

    update_gadget_visibility()
end

return M

end)()

-- ── features/combat/aimbot.lua ──
June._mods["features.combat.aimbot"] = (function()
local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local draw_util = June.require("core.draw_util")
local shootable_gadgets = June.require("game.shootable_gadgets")

local sqrt = constants.sqrt
local AIM_TARGET = constants.AIM_TARGET

local M = {}
local s = settings.s

local bone_map = {[0] = "head", [1] = "torso", [2] = "arm1", [3] = "arm2", [4] = "leg1", [5] = "leg2"}

local function get_target_bone(p)
    if not p or not p.bones then
        return nil
    end
    
    local pos = nil
    local bone = bone_map[s.aimbot_bone]
    
    if bone then
        pos = p.bones[bone]
    else
        local cx, cy, nb, nd = cache.screen_w / 2, cache.screen_h / 2, nil, math.huge
        for _, bp in pairs(p.bones) do
            if bp and bp.x then
                local sx, sy, vis = utility.world_to_screen(bp.x, bp.y, bp.z)
                if vis then
                    local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                    if d < nd then
                        nd, nb = d, bp
                    end
                end
            end
        end
        pos = nb
    end
    
    if not pos then return nil end
    
    -- Apply Prediction
    if s.aimbot_prediction and p.velocity then
        local factor = s.aimbot_prediction_val * 0.001 -- Convert to time scale
        return {
            x = pos.x + (p.velocity.x * factor),
            y = pos.y + (p.velocity.y * factor),
            z = pos.z + (p.velocity.z * factor)
        }
    end
    
    return pos
end

function M.is_target_valid(lt)
    if not lt then
        return false
    end
    if lt.is_utility then
        return lt.world_obj and cache.world_lookup[lt.world_obj] and
            cache.world_lookup[lt.world_obj].dist <= s.utilities_max_distance
    end
    for _, p in ipairs(cache.players) do
        if p.viewmodel == lt.viewmodel then
            -- Sticky aim bypasses vis-check so target stays locked through brief occlusion
            if s.aimbot_filter_health and p.health <= 0 then
                return false
            end
            return p.health > 0 and p.dist <= s.aimbot_max_distance
        end
    end
    return false
end

-- Linear smooth-aim with no deadzone.
-- Keeps the smooth divisor at all normal ranges, but guarantees a minimum
-- 0.5 px step toward center so the aimbot always converges all the way.
function M.smooth_aim(sx, sy, cx, cy, smooth)
    local dx = sx - cx
    local dy = sy - cy
    local mx = dx / smooth
    local my = dy / smooth
    -- Ensure we always step toward center — eliminates the sub-pixel deadzone
    if dx > 0 and mx < 0.5 then mx = 0.5 elseif dx < 0 and mx > -0.5 then mx = -0.5 end
    if dy > 0 and my < 0.5 then my = 0.5 elseif dy < 0 and my > -0.5 then my = -0.5 end
    input.move_mouse(mx, my)
end

function M.process_aimbot()
    local feature_bind = June.require("core.feature_bind")
    local aim_key = June.require("core.aim_key")

    -- Master toggle (Always / Hold / Toggle) is owned by feature_bind.
    if not feature_bind.active("aimbot_enabled") then
        cache.aim.current_target, cache.aim.locked_target = nil, nil
        return
    end

    local kd = aim_key.active("aimbot_key", "aimbot_key_mode")
    if not kd and cache.aim.last_key_state then
        cache.aim.locked_target = nil
    end
    cache.aim.last_key_state = kd

    -- Sticky Aim: uses normal aimkey and ignores FOV entirely
    local sticky_kd = s.aimbot_sticky and kd
    if not sticky_kd then
        cache.aim.locked_target = nil
    end

    if not kd then
        cache.aim.current_target = nil
        return
    end
    local cx, cy, fov, smooth = cache.screen_w / 2, cache.screen_h / 2, s.aimbot_fov, s.aimbot_smooth
    if sticky_kd and cache.aim.locked_target and is_target_valid(cache.aim.locked_target) then
        local tpos = nil
        if cache.aim.locked_target.is_utility then
            local w = cache.aim.locked_target.world_obj and cache.world_lookup[cache.aim.locked_target.world_obj]
            if w then
                tpos = {x = w.x, y = w.y, z = w.z}
            end
        else
            for _, p in ipairs(cache.players) do
                if p.viewmodel == cache.aim.locked_target.viewmodel then
                    cache.aim.locked_target = p
                    tpos = get_target_bone(p)
                    break
                end
            end
        end
        if tpos then
            local sx, sy = utility.world_to_screen(tpos.x, tpos.y, tpos.z)
            cache.aim.current_target = {target = cache.aim.locked_target, pos = tpos, screen_x = sx, screen_y = sy}
            smooth_aim(sx, sy, cx, cy, smooth)
            return
        end
        cache.aim.locked_target = nil
    end
    local best, bd = nil, math.huge
    for _, p in ipairs(cache.players) do
        if (not s.aimbot_team_check or not p.is_teammate)
            and p.dist <= s.aimbot_max_distance
            and (not s.aimbot_vischeck or p.is_visible)
            and (not s.aimbot_filter_health or p.health > 0)
        then
            local tb = get_target_bone(p)
            if tb then
                local sx, sy, vis = utility.world_to_screen(tb.x, tb.y, tb.z)
                if vis then
                    local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                    if d <= fov then
                        if s.aimbot_target_type == AIM_TARGET.CROSSHAIR then
                            if d < bd then
                                bd, best = d, {target = p, pos = tb, screen_x = sx, screen_y = sy}
                            end
                        else
                            best = {target = p, pos = tb, screen_x = sx, screen_y = sy}
                            break
                        end
                    end
                end
            end
        end
        ::continue::
    end
    if s.utilities_aimbot then
        -- If player priority is on and we already found a player, skip gadgets entirely
        if s.aimbot_players_priority and best and not best.target.is_utility then
            -- player already locked — don't consider gadgets
        else
        local bl_opts = s.gadget_aim_blacklist or {}
        local bl_labels = {
            "DRONE", "CLAYMORE", "C4", "JAMMER", "STICKY CAM", "BP CAM", "MAP CAM", "BREACH",
            "HARD BREACH", "PROX ALARM", "BARBED WIRE", "SHIELD",
            "THERMITE", "SHOCK BAT", "INC CANISTER", "NEEDLE MINE", "TOXIC",
        }
        local aim_blacklist = {}
        for i, enabled in ipairs(bl_opts) do
            if enabled and bl_labels[i] then
                aim_blacklist[bl_labels[i]] = true
                local base = shootable_gadgets.base_label(bl_labels[i])
                if base and base ~= bl_labels[i] then
                    aim_blacklist[base] = true
                end
            end
        end
        for _, w in ipairs(cache.world) do
            if w.dist <= s.utilities_max_distance
                and shootable_gadgets.is_shootable_entry(w)
                and not aim_blacklist[w.label]
                and not aim_blacklist[shootable_gadgets.base_label(w.label)]
            then
                if (s.aimbot_gadget_team_check or s.world_team_check) and w.is_teammate_gadget then
                    goto continue_gadget
                end
                local sx, sy, vis = utility.world_to_screen(w.x, w.y, w.z)
                if vis and sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2) <= fov then
                    local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                    if s.aimbot_target_type == AIM_TARGET.CROSSHAIR then
                        if d < bd then
                            bd, best =
                                d,
                                {
                                    target = {is_utility = true, world_obj = w.obj},
                                    pos = {x = w.x, y = w.y, z = w.z},
                                    screen_x = sx,
                                    screen_y = sy
                                }
                        end
                    else
                        if
                            not best or
                                w.dist <
                                    (best.target.is_utility and cache.world_lookup[best.target.world_obj] and
                                        cache.world_lookup[best.target.world_obj].dist or
                                        math.huge)
                         then
                            best = {
                                target = {is_utility = true, world_obj = w.obj},
                                pos = {x = w.x, y = w.y, z = w.z},
                                screen_x = sx,
                                screen_y = sy
                            }
                        end
                    end
                end
            end
            ::continue_gadget::
        end
        end -- player priority check
    end
    if best then
        cache.aim.current_target = best
        if s.aimbot_sticky and not cache.aim.locked_target then
            cache.aim.locked_target = best.target
        end
        smooth_aim(best.screen_x, best.screen_y, cx, cy, smooth)
    else
        cache.aim.current_target = nil
    end
end

function M.process_toggle(key_id, state_table, setting_id)
    -- feature_bind.tick() owns Always/Hold/Toggle for registered ids.
    local feature_bind = June.require("core.feature_bind")
    if feature_bind.is_registered(setting_id or key_id) then
        return
    end
    local kd = input.is_key_down(menu.get_key(key_id))
    if kd and not state_table.last then
        s[setting_id] = not s[setting_id]
        menu.set(setting_id, s[setting_id])
    end
    state_table.last = kd
end

return M

end)()

-- ── features/combat/silent_aim.lua ──
June._mods["features.combat.silent_aim"] = (function()
local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local silent_ray = June.require("core.silent_ray")
local silent_resolve = June.require("features.combat.silent_resolve")
local shootable_gadgets = June.require("game.shootable_gadgets")

local sqrt = constants.sqrt
local AIM_TARGET = constants.AIM_TARGET
local FOV_STYLE = constants.FOV_STYLE
local TARGET_LINE_STYLE = constants.TARGET_LINE_STYLE
local SHOOT_VK = 0x01
local TARGET_SCAN_MS = 33

local M = {}
local s = settings.s
local locked_target = nil
local last_target_scan = 0
local weapon_hold_ticks = 0
local bone_map = {[0] = "head", [1] = "torso", [2] = "arm1", [3] = "arm2", [4] = "leg1", [5] = "leg2"}

local function silent_vis_enabled()
    if menu and menu.get then
        return menu.get("silent_filter_visible") == true
    end
    return s.silent_filter_visible == true
end

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function w2s(x, y, z)
    if draw and draw.world_to_screen then
        return draw.world_to_screen(x, y, z)
    end
    if utility and utility.world_to_screen then
        return utility.world_to_screen(x, y, z)
    end
    return 0, 0, false
end

local function is_gadget_target(t)
    return t and t.is_gadget == true and t.world_entry ~= nil
end

local function live_world_entry(entry)
    if not entry then
        return nil
    end
    if entry.key and cache.world_lookup[entry.key] then
        return cache.world_lookup[entry.key]
    end
    if entry.obj and cache.world_lookup[entry.obj] then
        return cache.world_lookup[entry.obj]
    end
    return entry
end

local function holding_weapon()
    if not cache.ws then
        weapon_hold_ticks = math.max(0, weapon_hold_ticks - 1)
        return weapon_hold_ticks > 0
    end
    local vms = cache.ws:FindFirstChild("Viewmodels")
    local local_vm = vms and vms:FindFirstChild("LocalViewmodel")
    local has_weapon = false
    if local_vm then
        for _, child in ipairs(local_vm:GetChildren()) do
            if child.ClassName == "Model" and not cache.body_part_names[child.Name] and child:FindFirstChild("Magazine") then
                has_weapon = true
                break
            end
        end
    end
    if has_weapon then
        weapon_hold_ticks = 4
    else
        weapon_hold_ticks = math.max(0, weapon_hold_ticks - 1)
    end
    return weapon_hold_ticks > 0
end

local function live_bone_pos(p, bone_name)
    if not p or not p.viewmodel or not bone_name then
        return nil
    end
    local part = p.viewmodel:FindFirstChild(bone_name)
    if not part or not part.Position then
        return nil
    end
    local pos = part.Position
    return {x = pos.X, y = pos.Y, z = pos.Z}
end

local function get_bone_pos(p)
    if not p then
        return nil
    end

    local bone = bone_map[s.silent_bone]
    if bone then
        return live_bone_pos(p, bone)
    end

    local cx, cy = cache.screen_w * 0.5, cache.screen_h * 0.5
    local nb, nd = nil, math.huge
    for _, bone_name in ipairs(cache.bone_list) do
        local bp = live_bone_pos(p, bone_name)
        if bp then
            local sx, sy, vis = w2s(bp.x, bp.y, bp.z)
            if vis then
                local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                if d < nd then
                    nd, nb = d, bp
                end
            end
        end
    end
    return nb
end

local function passes_gadget_filters(w)
    if not w or not w.x then
        return false
    end
    if not shootable_gadgets.is_shootable_entry(w) then
        return false
    end
    local gadget_max = s.silent_gadget_max_distance or s.silent_max_dist or 250
    if w.dist > gadget_max then
        return false
    end
    if s.silent_gadget_team_check and w.is_teammate_gadget then
        return false
    end
    if silent_vis_enabled() and w.is_visible ~= true then
        return false
    end
    return true
end

local function get_gadget_aim(entry)
    local w = live_world_entry(entry)
    if not w then
        return nil
    end
    return {x = w.x, y = w.y, z = w.z}
end

local function passes_filters(p)
    if not p then
        return false
    end
    if s.silent_filter_team and p.is_teammate then
        return false
    end
    if s.silent_filter_health and p.health <= 0 then
        return false
    end
    if s.silent_filter_visible and not p.is_visible then
        return false
    end
    if p.dist > (s.silent_max_dist or 250) then
        return false
    end
    return true
end

local function is_valid_player_target(p)
    if not p or not passes_filters(p) then
        return false
    end
    for _, cp in ipairs(cache.players) do
        if cp.viewmodel == p.viewmodel then
            return cp.health > 0
        end
    end
    return false
end

local function is_valid_gadget_target(t)
    if not is_gadget_target(t) then
        return false
    end
    local w = live_world_entry(t.world_entry)
    if not w or not w.obj or not utility.is_valid(w.obj) then
        return false
    end
    return passes_gadget_filters(w)
end

local function is_valid_target(t)
    if is_gadget_target(t) then
        return is_valid_gadget_target(t)
    end
    return is_valid_player_target(t)
end

local function in_fov_player(p, cx, cy, fov)
    local tb = get_bone_pos(p)
    if not tb then
        return false
    end
    local sx, sy, vis = w2s(tb.x, tb.y, tb.z)
    if not vis then
        return false
    end
    return sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2) <= fov
end

local function score_player(p, cx, cy, fov)
    local tb = get_bone_pos(p)
    if not tb then
        return nil
    end
    local sx, sy, vis = w2s(tb.x, tb.y, tb.z)
    if not vis then
        return nil
    end
    local screen_d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
    if screen_d > fov then
        return nil
    end
    if s.silent_target_type == AIM_TARGET.CROSSHAIR then
        return screen_d
    end
    return p.dist
end

local function score_gadget(w, cx, cy, fov)
    if not passes_gadget_filters(w) then
        return nil
    end
    local sx, sy, vis = w2s(w.x, w.y, w.z)
    if not vis then
        return nil
    end
    local screen_d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
    if screen_d > fov then
        return nil
    end
    if s.silent_target_type == AIM_TARGET.CROSSHAIR then
        return screen_d
    end
    return w.dist
end

local function find_target(cx, cy, fov)
    local best, best_score = nil, math.huge
    local best_is_player = false

    for _, p in ipairs(cache.players) do
        if passes_filters(p) then
            local score = score_player(p, cx, cy, fov)
            if score and score < best_score then
                best_score = score
                best = p
                best_is_player = true
            end
        end
    end

    if s.silent_gadget_aim then
        -- Mirror aimbot: skip gadgets when a player is already preferred.
        if not (s.silent_players_priority and best_is_player) then
            for _, w in ipairs(cache.world) do
                local score = score_gadget(w, cx, cy, fov)
                if score and score < best_score then
                    best_score = score
                    best = {is_gadget = true, world_entry = w, key = w.key}
                end
            end
        end
    end

    return best
end

local function refresh_target(cx, cy, fov)
    if locked_target and not is_valid_target(locked_target) then
        locked_target = nil
    end

    local now = tick_ms()
    if now - last_target_scan < TARGET_SCAN_MS then
        return
    end
    last_target_scan = now

    local new = find_target(cx, cy, fov)
    if new then
        locked_target = new
        return
    end

    if not s.silent_sticky and locked_target then
        if is_gadget_target(locked_target) then
            local w = live_world_entry(locked_target.world_entry)
            if not w or not score_gadget(w, cx, cy, fov) then
                locked_target = nil
            end
        elseif not in_fov_player(locked_target, cx, cy, fov) then
            locked_target = nil
        end
    end
end

function M.active()
    local feature_bind = June.require("core.feature_bind")
    local on = feature_bind.is_registered("silent_aim_enabled")
        and feature_bind.active("silent_aim_enabled")
        or (s.silent_aim_enabled == true)
    return on and silent_ray.available()
end

function M.get_target()
    return locked_target
end

function M.get_aim_point()
    if not locked_target then
        return nil
    end
    if is_gadget_target(locked_target) then
        return get_gadget_aim(locked_target.world_entry)
    end
    return get_bone_pos(locked_target)
end

function M.update(_dt)
    if not M.active() then
        locked_target = nil
        silent_ray.stop()
        return
    end

    silent_ray.ensure_hook()

    if not holding_weapon() then
        if not (input and input.is_key_down and input.is_key_down(0x01)) then
            silent_ray.stop()
            return
        end
    end

    local cx, cy = cache.screen_w * 0.5, cache.screen_h * 0.5
    local fov = s.silent_fov or 150

    refresh_target(cx, cy, fov)

    if not locked_target then
        silent_ray.stop()
        return
    end

    local aim = M.get_aim_point()
    if not aim then
        silent_ray.stop()
        return
    end

    local origin, resolved_aim = silent_resolve.resolve_track(aim)
    if not origin or not resolved_aim then
        silent_ray.stop()
        return
    end

    silent_ray.track(origin, resolved_aim, SHOOT_VK)
end

function M.draw()
    if not M.active() then
        return
    end

    local cx, cy = cache.screen_w * 0.5, cache.screen_h * 0.5
    local fov = s.silent_fov or 150

    if s.silent_draw_fov then
        local col = s.silent_draw_fov_color or {0.55, 0.2, 1, 1}
        local fov_style = s.silent_fov_style or 0
        if s.silent_fov_fill then
            local fc = s.silent_fov_fill_color or {col[1], col[2], col[3], 0.08}
            if fov_style == FOV_STYLE.SQUARE or fov_style == FOV_STYLE.FILLED_SQUARE or fov_style == FOV_STYLE.DASHED then
                draw.rect_filled(cx - fov, cy - fov, fov * 2, fov * 2, fc)
            else
                draw.circle_filled(cx, cy, fov, fc, 64)
            end
        end
        if fov_style == FOV_STYLE.CIRCLE then
            draw.circle(cx, cy, fov, col, 64, 1)
        elseif fov_style == FOV_STYLE.FILLED_CIRCLE then
            draw.circle_filled(cx, cy, fov, {col[1], col[2], col[3], col[4] * 0.15}, 64)
            draw.circle(cx, cy, fov, col, 64, 1)
        elseif fov_style == FOV_STYLE.DOTTED then
            for i = 0, 63 do
                local angle = (i / 64) * math.pi * 2
                local x, y = cx + math.cos(angle) * fov, cy + math.sin(angle) * fov
                draw.circle_filled(x, y, 2, col)
            end
        elseif fov_style == FOV_STYLE.SQUARE then
            draw.rect(cx - fov, cy - fov, fov * 2, fov * 2, col, 0, 1)
        elseif fov_style == FOV_STYLE.FILLED_SQUARE then
            draw.rect_filled(cx - fov, cy - fov, fov * 2, fov * 2, {col[1], col[2], col[3], col[4] * 0.15})
            draw.rect(cx - fov, cy - fov, fov * 2, fov * 2, col, 0, 1)
        elseif fov_style == FOV_STYLE.DASHED then
            for i = 0, 15 do
                local t1, t2 = i / 16, (i + 0.5) / 16
                local angle1, angle2 = t1 * math.pi * 2, t2 * math.pi * 2
                local x1, y1 = cx + math.cos(angle1) * fov, cy + math.sin(angle1) * fov
                local x2, y2 = cx + math.cos(angle2) * fov, cy + math.sin(angle2) * fov
                draw.line(x1, y1, x2, y2, col, 2)
            end
        end
    end

    if s.silent_target_line and locked_target then
        local aim = M.get_aim_point()
        if aim then
            local tx, ty, vis = w2s(aim.x, aim.y, aim.z)
            if vis then
                local col = s.silent_target_line_color or {1, 0.25, 0.25, 1}
                local style = s.silent_target_line_style or 0
                if style == TARGET_LINE_STYLE.SOLID then
                    draw.line(cx, cy, tx, ty, col, 2)
                elseif style == TARGET_LINE_STYLE.DASHED then
                    for i = 0, 9 do
                        local t1, t2 = i / 10, (i + 0.5) / 10
                        draw.line(
                            cx + (tx - cx) * t1,
                            cy + (ty - cy) * t1,
                            cx + (tx - cx) * t2,
                            cy + (ty - cy) * t2,
                            col,
                            2
                        )
                    end
                elseif style == TARGET_LINE_STYLE.DOTTED then
                    for i = 0, 19 do
                        draw.circle_filled(cx + (tx - cx) * (i / 20), cy + (ty - cy) * (i / 20), 2, col)
                    end
                end
                local endpoint_style = s.silent_target_line_endpoint or 5
                if endpoint_style == 0 then
                    draw.circle_filled(tx, ty, 5, col)
                elseif endpoint_style == 1 then
                    draw.circle(tx, ty, 5, col, 32, 2)
                elseif endpoint_style == 2 then
                    draw.circle_filled(tx, ty, 2, col)
                elseif endpoint_style == 3 then
                    draw.rect_filled(tx - 4, ty - 4, 8, 8, col)
                elseif endpoint_style == 4 then
                    draw.line(tx - 5, ty - 5, tx + 5, ty + 5, col, 2)
                    draw.line(tx + 5, ty - 5, tx - 5, ty + 5, col, 2)
                end
            end
        end
    end
end

return M

end)()

-- ── features/visuals/player_esp.lua ──
June._mods["features.visuals.player_esp"] = (function()
local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local draw_util = June.require("core.draw_util")

local sqrt, floor, min, max = constants.sqrt, constants.floor, constants.min, constants.max
local clamp = constants.clamp
local BOX_TYPE = constants.BOX_TYPE
local TRACER_ORIGIN = constants.TRACER_ORIGIN
local TRACER_STYLE = constants.TRACER_STYLE

local M = {}
local s = settings.s
local draw_box = draw_util.draw_box
local draw_3d_box = draw_util.draw_3d_box
local draw_segmented_line = draw_util.draw_segmented_line
local draw_tracer = draw_util.draw_tracer

local function render_players()
    if not s.players_enabled then
        return
    end

    local show_health, show_name, show_weapon, show_dist, show_head, show_skel, show_view, show_tracer =
        s.players_healthbar,
        s.players_name,
        s.players_weapon,
        s.players_distance,
        s.players_head_dot,
        s.players_skeleton,
        s.players_view_line,
        s.players_tracers
    local esp_col, name_col, wpn_col, dist_col, head_col, skel_col, view_col, tracer_col =
        s.players_enabled_color or {1, 1, 1, 1},
        s.players_name_color,
        s.players_weapon_color,
        s.players_distance_color,
        s.players_head_dot_color,
        s.players_skeleton_color,
        s.players_view_line_color,
        s.players_tracers_color
    local view_len, view_style =
        s.view_line_length,
        s.view_line_style
    local fs_name, fs_wpn, fs_dist =
        s.font_size_name,
        s.font_size_weapon,
        s.font_size_distance
    local tracer_origin = s.tracer_origin or TRACER_ORIGIN.BOTTOM
    local tracer_style = s.tracer_style or TRACER_STYLE.SOLID
    local vis_override = s.players_visible_override
    local vis_col = s.players_visible_override_color
    local tgt_override = s.players_target_override
    local tgt_col = s.players_target_override_color
    local aim_target_vm = cache.aim.current_target and cache.aim.current_target.target and
        (not cache.aim.current_target.target.is_utility) and
        cache.aim.current_target.target.viewmodel or nil

    for _, p in ipairs(cache.players) do
        if not p.is_teammate or s.players_team then
            -- Drop corpses / zero-HP targets from ESP immediately.
            local hp = tonumber(p.health) or 0
            local mhp = tonumber(p.max_health) or 100
            if mhp < 1 then mhp = 100 end
            if p.is_alive == false or hp <= 0 then
                goto continue
            end

            if p.dist <= 3 or not p.screen_vis then
                goto continue
            end

            local mnx, mny, mxx, mxy, cx = p.screen_mnx, p.screen_mny, p.screen_mxx, p.screen_mxy, p.screen_cx
            if not mnx then
                goto continue
            end

            local eff_col = esp_col
            if tgt_override and aim_target_vm and p.viewmodel == aim_target_vm then
                eff_col = tgt_col
            elseif vis_override and p.is_visible then
                eff_col = vis_col
            end

            if s.players_box then
                local btype = s.box_type or BOX_TYPE.STANDARD
                if btype == BOX_TYPE.THREE_D and p.bbox then
                    draw_3d_box(p.bbox, eff_col)
                else
                    local bx, by, bw, bh = mnx - 3, mny - 3, mxx - mnx + 6, mxy - mny + 6
                    draw_box(bx, by, bw, bh, eff_col, s.box_fill, btype, p.bbox)
                end
            end

            local bx, by, bw, bh = mnx - 3, mny - 3, mxx - mnx + 6, mxy - mny + 6
            local c_name = eff_col
            local c_wpn = eff_col
            local c_dist = eff_col
            local c_head = eff_col
            local c_skel = eff_col
            local c_view = eff_col
            local c_trac = eff_col

            if not (tgt_override or (vis_override and p.is_visible)) then
                c_name = name_col
                c_wpn = wpn_col
                c_dist = dist_col
                c_head = head_col
                c_skel = skel_col
                c_view = view_col
                c_trac = tracer_col
            end

            if show_health and bh > 10 then
                local hf = clamp(hp / mhp, 0, 1)
                local bh2 = bh * hf
                draw.rect_filled(bx - 6, by, 3, bh, {0, 0, 0, 0.6})
                draw.rect_filled(bx - 6, by + bh - bh2, 3, bh2, {1 - hf, hf, 0, 1})
            end

            local ty = by + bh + 2
            if show_name and p.name then
                local tw = draw.get_text_size(p.name, fs_name)
                draw.text(cx - tw * 0.5, by - fs_name - 2, p.name, c_name, fs_name)
            end
            if show_weapon and p.weapon then
                local tw = draw.get_text_size(p.weapon, fs_wpn)
                draw.text(cx - tw * 0.5, ty, p.weapon, c_wpn, fs_wpn)
                ty = ty + fs_wpn + 1
            end
            if show_dist then
                local dt = floor(p.dist) .. "m"
                local tw = draw.get_text_size(dt, fs_dist)
                draw.text(cx - tw * 0.5, ty, dt, c_dist, fs_dist)
            end
            if show_head and p.bones and p.bones.head then
                local bp = p.bones.head
                local sx, sy, vis = utility.world_to_screen(bp.x, bp.y, bp.z)
                if vis then
                    draw.circle(sx, sy, 4, c_head, 16, 1.5)
                end
            end
            if show_skel and p.bones then
                for _, cn in ipairs(cache.skeleton_bones) do
                    local b1 = p.bones[cn[1]]
                    local b2 = p.bones[cn[2]]
                    if b1 and b2 then
                        local sx1, sy1, v1 = utility.world_to_screen(b1.x, b1.y, b1.z)
                        local sx2, sy2, v2 = utility.world_to_screen(b2.x, b2.y, b2.z)
                        if v1 and v2 then
                            draw.line(sx1, sy1, sx2, sy2, c_skel, 1.5)
                        end
                    end
                end
            end
            if show_view and p.look_vector and p.bones and p.bones.head then
                local h = p.bones.head
                local lv = p.look_vector
                local sx, sy, vis2 = utility.world_to_screen(h.x, h.y, h.z)
                local ex_s, ey_s, evis =
                    utility.world_to_screen(h.x + lv.x * view_len, h.y + lv.y * view_len, h.z + lv.z * view_len)
                if vis2 and evis then
                    draw_segmented_line(sx, sy, ex_s, ey_s, c_view, view_style)
                end
            end
            if show_tracer then
                local sw, sh = cache.screen_w, cache.screen_h
                local ox, oy
                if tracer_origin == TRACER_ORIGIN.BOTTOM then
                    ox, oy = sw * 0.5, sh
                elseif tracer_origin == TRACER_ORIGIN.CENTER then
                    ox, oy = sw * 0.5, sh * 0.5
                else
                    local mx, my = utility.get_mouse_pos()
                    ox, oy = mx or sw * 0.5, my or sh
                end
                local tx2, ty2 = cx, mny
                if p.bones and p.bones.head then
                    local sx, sy, vis = utility.world_to_screen(p.bones.head.x, p.bones.head.y, p.bones.head.z)
                    if vis then
                        tx2, ty2 = sx, sy
                    end
                end
                draw_tracer(ox, oy, tx2, ty2, c_trac, tracer_style)
            end
            ::continue::
        end
    end
end

M.render_players = render_players

return M

end)()

-- ── features/visuals/world_esp.lua ──
June._mods["features.visuals.world_esp"] = (function()
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local draw_util = June.require("core.draw_util")
local world_scan = June.require("game.world_scan")

local floor = June.require("core.constants").floor
local DIST = June.require("core.constants").DIST

local M = {}
local s = settings.s
local draw_3d_box = draw_util.draw_3d_box
local dist3d_sq = draw_util.dist3d_sq

local function world_to_screen(x, y, z)
    if utility and utility.world_to_screen then
        return utility.world_to_screen(x, y, z)
    end
    if draw and draw.world_to_screen then
        return draw.world_to_screen(x, y, z)
    end
    return 0, 0, false
end

function M.render_world()
    if not s.world_enabled then
        return
    end

    local display_opts = s.world_display_options or {false, false, false}
    local show_text = display_opts[1]
    local show_dist = display_opts[2]
    local show_box = display_opts[3]
    local fs_world = s.font_size_world
    local max_sq = (s.world_max_distance or 250) * (s.world_max_distance or 250)
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z
    local drawn = {}

    for _, w in ipairs(cache.world) do
        if not w.is_esp or not w.color or not w.x then
            goto continue
        end

        if w.is_broken then
            goto continue
        end

        if w.is_teammate_gadget and s.world_team_check then
            goto continue
        end

        local key = w.key or world_scan.inst_key(w.obj)
        if key and drawn[key] then
            goto continue
        end
        if key then
            drawn[key] = true
        end

        if w.x then
            local dsq = w.dsq
            if not dsq then
                dsq = dist3d_sq(w.x, w.y, w.z, cam_x, cam_y, cam_z)
                w.dsq = dsq
                w.dist = math.sqrt(dsq)
            end
            if dsq > max_sq then
                goto continue
            end
            if not w.dynamic and dsq <= DIST.ESP_HIDE_SQ then
                goto continue
            end
        end

        if show_box then
            local bbox = w.bbox
            if bbox then
                draw_3d_box(bbox, w.color)
            end
        end

        if show_text or show_dist then
            local sx, sy, v = world_to_screen(w.x, w.y, w.z)
            if v then
                local txt =
                    (show_text and w.label or "") ..
                    (show_dist and (show_text and " [" or "[") .. floor(w.dist) .. "m]" or "")
                if txt ~= "" then
                    local tw = draw.get_text_size(txt, fs_world)
                    draw.text(sx - tw * 0.5, sy - fs_world - 2, txt, w.color, fs_world)
                end
            end
        end

        ::continue::
    end
end

return M

end)()

-- ── features/visuals/aimbot_visuals.lua ──
June._mods["features.visuals.aimbot_visuals"] = (function()
local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")

local FOV_STYLE = constants.FOV_STYLE
local TARGET_LINE_STYLE = constants.TARGET_LINE_STYLE

local M = {}
local s = settings.s

local function render_aimbot_visuals()
    if not s.aimbot_enabled then
        return
    end
    if s.aimbot_fov_visible then
        local cx, cy, fov, col = cache.screen_w / 2, cache.screen_h / 2, s.aimbot_fov, s.aimbot_fov_visible_color
        local fov_style = s.aimbot_fov_style or 0
        -- Independent fill layer (drawn before the outline so outline sits on top)
        if s.aimbot_fov_fill then
            local fc = s.aimbot_fov_fill_color or {col[1], col[2], col[3], 0.08}
            if fov_style == FOV_STYLE.SQUARE or fov_style == FOV_STYLE.FILLED_SQUARE or fov_style == FOV_STYLE.DASHED then
                draw.rect_filled(cx - fov, cy - fov, fov * 2, fov * 2, fc)
            else
                draw.circle_filled(cx, cy, fov, fc, 64)
            end
        end
        if fov_style == FOV_STYLE.CIRCLE then
            draw.circle(cx, cy, fov, col, 64, 1)
        elseif fov_style == FOV_STYLE.FILLED_CIRCLE then
            draw.circle_filled(cx, cy, fov, {col[1], col[2], col[3], col[4] * 0.15}, 64)
            draw.circle(cx, cy, fov, col, 64, 1)
        elseif fov_style == FOV_STYLE.DOTTED then
            for i = 0, 63 do
                local angle = (i / 64) * math.pi * 2
                local x, y = cx + math.cos(angle) * fov, cy + math.sin(angle) * fov
                draw.circle_filled(x, y, 2, col)
            end
        elseif fov_style == FOV_STYLE.SQUARE then
            draw.rect(cx - fov, cy - fov, fov * 2, fov * 2, col, 0, 1)
        elseif fov_style == FOV_STYLE.FILLED_SQUARE then
            draw.rect_filled(cx - fov, cy - fov, fov * 2, fov * 2, {col[1], col[2], col[3], col[4] * 0.15})
            draw.rect(cx - fov, cy - fov, fov * 2, fov * 2, col, 0, 1)
        elseif fov_style == FOV_STYLE.DASHED then
            for i = 0, 15 do
                local t1, t2 = i / 16, (i + 0.5) / 16
                local angle1, angle2 = t1 * math.pi * 2, t2 * math.pi * 2
                local x1, y1 = cx + math.cos(angle1) * fov, cy + math.sin(angle1) * fov
                local x2, y2 = cx + math.cos(angle2) * fov, cy + math.sin(angle2) * fov
                draw.line(x1, y1, x2, y2, col, 2)
            end
        end
    end
    if s.aimbot_target_line and cache.aim.current_target then
        local cx, cy, t = cache.screen_w / 2, cache.screen_h / 2, cache.aim.current_target
        local col = s.aimbot_target_line_color
        if s.target_line_style == TARGET_LINE_STYLE.SOLID then
            draw.line(cx, cy, t.screen_x, t.screen_y, col, 2)
        elseif s.target_line_style == TARGET_LINE_STYLE.DASHED then
            for i = 0, 9 do
                local t1, t2 = i / 10, (i + 0.5) / 10
                draw.line(
                    cx + (t.screen_x - cx) * t1,
                    cy + (t.screen_y - cy) * t1,
                    cx + (t.screen_x - cx) * t2,
                    cy + (t.screen_y - cy) * t2,
                    col,
                    2
                )
            end
        elseif s.target_line_style == TARGET_LINE_STYLE.DOTTED then
            for i = 0, 19 do
                draw.circle_filled(cx + (t.screen_x - cx) * (i / 20), cy + (t.screen_y - cy) * (i / 20), 2, col)
            end
        end
        local endpoint_style = s.target_line_endpoint or 0
        if endpoint_style == 0 then
            draw.circle_filled(t.screen_x, t.screen_y, 5, col)
        elseif endpoint_style == 1 then
            draw.circle(t.screen_x, t.screen_y, 5, col, 32, 2)
        elseif endpoint_style == 2 then
            draw.circle_filled(t.screen_x, t.screen_y, 2, col)
        elseif endpoint_style == 3 then
            draw.rect_filled(t.screen_x - 4, t.screen_y - 4, 8, 8, col)
        elseif endpoint_style == 4 then
            draw.line(t.screen_x - 5, t.screen_y - 5, t.screen_x + 5, t.screen_y + 5, col, 2)
            draw.line(t.screen_x + 5, t.screen_y - 5, t.screen_x - 5, t.screen_y + 5, col, 2)
        end
    end
end

M.render_aimbot_visuals = render_aimbot_visuals

return M

end)()

-- ── features/visuals/crosshair.lua ──
June._mods["features.visuals.crosshair"] = (function()
local settings = June.require("core.settings")
local cache = June.require("core.cache")

local M = {}
local s = settings.s

local function draw_crosshair()
    if not s.crosshair_enabled then return end
    local cx, cy = cache.screen_w / 2, cache.screen_h / 2
    local col = s.crosshair_enabled_color
    local sz  = s.crosshair_size  or 8
    local gap = s.crosshair_gap   or 3
    local csty = s.crosshair_style or 0
    if csty == 0 then -- Cross
        draw.line(cx - sz - gap, cy, cx - gap, cy, col, 1.5)
        draw.line(cx + gap, cy, cx + sz + gap, cy, col, 1.5)
        draw.line(cx, cy - sz - gap, cx, cy - gap, col, 1.5)
        draw.line(cx, cy + gap, cx, cy + sz + gap, col, 1.5)
    elseif csty == 1 then -- Dot
        draw.circle_filled(cx, cy, sz * 0.4, col)
    elseif csty == 2 then -- Circle
        draw.circle(cx, cy, sz + gap, col, 48, 1.5)
    elseif csty == 3 then -- Plus (no gap)
        draw.line(cx - sz, cy, cx + sz, cy, col, 1.5)
        draw.line(cx, cy - sz, cx, cy + sz, col, 1.5)
    end
end

M.draw_crosshair = draw_crosshair

return M

end)()

-- ── features/utility/keybind_window.lua ──
June._mods["features.utility.keybind_window"] = (function()
local settings = June.require("core.settings")

local M = {}
local s = settings.s

local function draw_keybind_window()
    if not s.keybind_window_enabled then
        return
    end
    local itms = {}
    if s.aimbot_enabled then
        itms[#itms + 1] = "Aimbot Key: " .. (input.is_key_down(menu.get_key("aimbot_key")) and "ON" or "OFF")
    end
    if s.utilities_aimbot and s.aimbot_enabled then
        itms[#itms + 1] = "Utilities Aimbot: ON"
    end
    if s.players_enabled then
        itms[#itms + 1] = "Player ESP: ON"
    end
    if s.world_enabled then
        itms[#itms + 1] = "World ESP: ON"
    end
    if s.silent_aim_enabled then
        itms[#itms + 1] = "Silent Aim: ON"
    end
    if #itms > 0 then
        draw.window(1500, 200, "keybind_list", " KEYBINDS ", itms)
    end
end

M.draw_keybind_window = draw_keybind_window

return M

end)()

-- ── menu/tabs.lua ──
June._mods["menu.tabs"] = (function()
local menu_defs = June.require("menu.menu_defs")
local config = June.require("features.utility.config")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local env = June.require("core.env")
local scan = June.require("features.combat.scan")
local aimbot = June.require("features.combat.aimbot")
local silent_aim = June.require("features.combat.silent_aim")
local player_esp = June.require("features.visuals.player_esp")
local world_esp = June.require("features.visuals.world_esp")
local aimbot_visuals = June.require("features.visuals.aimbot_visuals")
local crosshair = June.require("features.visuals.crosshair")
local keybind_window = June.require("features.utility.keybind_window")

local M = {}
M._menu_registered = false

function M.register_all()
    if M._menu_registered then return end
    -- Custom UI backend: feature register_menu() writes into gs_state, not Vector menu.
    pcall(function()
        June.require("ui.menu_shim").install()
    end)
    menu_defs.register_all()
    config.register_menu()
    M._menu_registered = true
end

function M.init()
    M.register_all()
    config.autoload()
    return true
end

function M.update(_dt)
    local s = settings.s
    cache.ws = env.get_workspace()
    if not cache.ws then
        return
    end
    local cam = cache.ws:FindFirstChild("Camera")
    if cam and cam.CFrame then
        cache.cam_x, cache.cam_y, cache.cam_z = cam.CFrame.X, cam.CFrame.Y, cam.CFrame.Z
    end
    cache.screen_w, cache.screen_h = utility.get_screen_size()
    settings.sync_settings()
    menu.set_visible("world_display_options", s.world_enabled)
    menu.set_visible("world_team_check", s.world_enabled)
    menu.set_visible("box_type", s.players_enabled and s.players_box)
    menu.set_visible("box_fill", s.players_enabled and s.players_box)
    menu.set_visible("box_fill_opacity", s.players_enabled and s.box_fill)
    menu.set_visible("view_line_length", s.players_enabled and s.players_view_line)
    menu.set_visible("view_line_style", s.players_enabled and s.players_view_line)
    menu.set_visible("tracer_origin", s.players_enabled and s.players_tracers)
    menu.set_visible("tracer_style", s.players_enabled and s.players_tracers)
    menu.set_visible("crosshair_style", s.crosshair_enabled)
    menu.set_visible("crosshair_size", s.crosshair_enabled)
    menu.set_visible("crosshair_gap", s.crosshair_enabled)
    menu.set_visible("utilities_max_distance", s.aimbot_enabled and s.utilities_aimbot)
    menu.set_visible("aimbot_fov", s.aimbot_enabled and s.aimbot_fov_visible)
    menu.set_visible("aimbot_fov_style", s.aimbot_enabled and s.aimbot_fov_visible)
    menu.set_visible("target_line_style", s.aimbot_enabled and s.aimbot_target_line)
    menu.set_visible("vis_check_priority", (s.aimbot_enabled and s.aimbot_vischeck) or (s.players_enabled and s.players_visible_override))
    menu.set_visible("silent_fov_style", s.silent_aim_enabled and s.silent_draw_fov)
    menu.set_visible("silent_fov_fill", s.silent_aim_enabled and s.silent_draw_fov)
    menu.set_visible("silent_gadget_aim", s.silent_aim_enabled)
    menu.set_visible("silent_gadget_team_check", s.silent_aim_enabled and s.silent_gadget_aim)
    scan.update_char_models()
    scan.scan_players()
    scan.scan_world()
    aimbot.process_toggle("players_enabled", cache.toggles.player, "players_enabled")
    aimbot.process_toggle("world_enabled", cache.toggles.world, "world_enabled")
    silent_aim.update(_dt)
    aimbot.process_aimbot()
end

function M.draw()
    player_esp.render_players()
    world_esp.render_world()
    aimbot_visuals.render_aimbot_visuals()
    silent_aim.draw()
    crosshair.draw_crosshair()
    keybind_window.draw_keybind_window()
end

return M

end)()

-- ── app.lua ──
June._mods["app"] = (function()
local tabs = June.require("menu.tabs")
local debug = June.require("core.debug")
local custom_menu = June.require("ui.custom_menu")

local M = {}
local initialized = false

function M.init()
    if initialized then return true end
    initialized = tabs.init()
    if initialized then
        pcall(custom_menu.init)
        pcall(function()
            local fb = June.require("core.feature_bind")
            fb.register({ id = "aimbot_enabled", label = "Aimbot", key_id = "aimbot_enabled" })
            fb.register({ id = "silent_aim_enabled", label = "Silent Aim", key_id = "silent_aim_enabled" })
            fb.register({ id = "players_enabled", label = "Players", key_id = "players_enabled" })
            fb.register({ id = "world_enabled", label = "World", key_id = "world_enabled" })
        end)
    end
    return initialized
end

function M.on_frame()
    if not initialized then return end
    debug.tick_frame()

    pcall(function()
        June.require("core.feature_bind").tick()
    end)
    pcall(function()
        June.require("core.aim_key").tick("aimbot_key", "aimbot_key_mode")
    end)

    local dt = 0.016
    if utility and utility.get_delta_time then
        dt = utility.get_delta_time()
    end

    debug.guard("tabs.update", tabs.update, dt)
    debug.guard("tabs.draw", tabs.draw)
    debug.guard("custom_menu.draw", custom_menu.draw)
end

return M

end)()

do
    June.require("menu.tabs").register_all()
end

June._init_ok = false

local ok, err = pcall(function()
    local debug = June.require("core.debug")
    local app = June.require("app")

    if not app.init() then
        debug.error_once("init", "app.init() returned false")
        return
    end

    June._init_ok = true

    if not debug.register_frame_hook(function()
        app.on_frame()
    end) then
        debug.error_once("init", "Failed to register on_frame")
        return
    end

    print("[June] v" .. (June.version or "?") .. " ready — INSERT for June menu")
end)

if not ok then
    print("[June] Fatal: " .. tostring(err))
    if debug and debug.traceback then print(debug.traceback(err)) end
end

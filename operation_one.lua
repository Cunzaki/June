--[[
    April Operation One for Project Vector
    Built: 2026-07-07T09:06:29.049Z
]]

OperationOne = {
    version = "1.1.0",
    debug = false,
    _mods = {},
    bundled = true,
}

if menu and menu.add_tab then
    menu.add_tab("Operation One", "O", "full")
end
OperationOne._menu_tab_ready = true

function OperationOne.require(path)
    local mod = OperationOne._mods[path]
    if mod == nil then
        error("[OperationOne] bundled module missing: " .. path)
    end
    return mod
end


-- ── core/constants.lua ──
OperationOne._mods["core.constants"] = (function()
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
OperationOne._mods["core.env"] = (function()
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
    if game and game.Workspace then return game.Workspace end
    if game and game.workspace then return game.workspace end
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
OperationOne._mods["core.debug"] = (function()
--[[ Operation One debug — off by default. Set OperationOne.debug = true for logs. ]]

local M = {}

local seen_errors = {}
local frame_count = 0

function M.enabled()
    return OperationOne and OperationOne.debug == true
end

function M.verbose()
    return OperationOne and OperationOne.debug_verbose == true
end

function M.log(msg)
    if not M.enabled() then return end
    print("[OperationOne] " .. tostring(msg))
end

function M.warn(msg)
    if not M.enabled() then return end
    print("[OperationOne WARN] " .. tostring(msg))
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
    print("[OperationOne ERROR][" .. key .. "] " .. tostring(err) .. suffix)
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

function M.register_frame_hook(fn)
    if type(fn) ~= "function" then
        M.error_once("frame_hook", "on_frame handler is not a function")
        return false
    end

    -- Vector only invokes global on_frame (see April/docs/API.md).
    -- callbacks.add / draw.callback stack on reload and draw everything twice.
    _G.on_frame = fn

    if draw then
        draw.callback = nil
    end

    return true
end

function M.tick_frame()
    frame_count = frame_count + 1
end

return M

end)()

-- ── core/cache.lua ──
OperationOne._mods["core.cache"] = (function()
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

-- ── core/menu_util.lua ──
OperationOne._mods["core.menu_util"] = (function()
--[[
    Vector full-mode grid:
      menu.add_group(tab, name)           -> left column, new row
      menu.add_group(tab, name, 0, true) -> right column, same row as previous left
]]

local M = {}

M.TAB = "Operation One"

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
    if not (OperationOne and OperationOne._menu_tab_ready) and menu and menu.add_tab then
        menu.add_tab(M.TAB, "O", "full")
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
OperationOne._mods["core.incremental_scan"] = (function()
--[[ Time-budgeted scans — spread heavy workspace work across frames. ]]

local debug = OperationOne.require("core.debug")

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
OperationOne._mods["game.world_items"] = (function()
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

-- ── game/gadget_team.lua ──
OperationOne._mods["game.gadget_team"] = (function()
--[[ Gadget ownership — mirrors Util.ownership from game scripts (UserId / Team attributes). ]]

local env = OperationOne.require("core.env")

local M = {}

local function get_attr(inst, name)
    if not inst or type(inst.GetAttribute) ~= "function" then
        return nil
    end
    return inst:GetAttribute(name)
end

local function local_identity()
    local lp = env.get_local_player()
    if not lp then
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

    return {
        user_id = user_id,
        team = team,
        spectator = spectator == true,
    }
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
OperationOne._mods["game.gadget_lifecycle"] = (function()
--[[ Gadget alive/broken rules derived from Operation One decompiled scripts.
    Cameras: Disabled attribute, Cam/Dot transparency (Breakable/Electronic states).
    Placeables/throwables: leave Workspace when destroyed (Garbage pool).
]]

local M = {}

local CAMERA_MODELS = {
    DefaultCamera = true,
    BulletproofCamera = true,
    StickyCamera = true,
}

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

local function is_pooled(obj)
    local parent = obj and (obj.Parent or obj.parent)
    if not parent then
        return false
    end
    local pname = parent.Name or parent.name or ""
    if pname == "Garbage" or pname == "Objects" then
        return true
    end
    if game and game.ReplicatedStorage then
        local garbage = game.ReplicatedStorage:FindFirstChild("Garbage")
        if garbage and parent == garbage then
            return true
        end
        local objects = game.ReplicatedStorage:FindFirstChild("Objects")
        if objects and parent == objects then
            return true
        end
    end
    return false
end

function M.is_camera_model(name)
    return CAMERA_MODELS[name] == true
end

function M.is_camera_broken(obj)
    if not is_valid(obj) then
        return true
    end
    if get_attr(obj, "Disabled") == true then
        return true
    end

    local dot = obj:FindFirstChild("Dot")
    if dot and dot.Transparency ~= nil and dot.Transparency >= 1 then
        return true
    end

    local cam = obj:FindFirstChild("Cam")
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
    return parent and (parent.ClassName == "Workspace" or parent == game.Workspace)
end

function M.is_broken(obj, item)
    if not obj then
        return true
    end

    local kind = (item and item.name) or obj.Name
    if M.is_camera_model(kind) then
        return M.is_camera_broken(obj)
    end

    if get_attr(obj, "Disabled") == true then
        return true
    end

    local anchor_name = (item and (item.anchor_part or item.priority_part)) or "Root"
    local anchor = obj:FindFirstChild(anchor_name)
    if anchor and not part_visible(anchor) then
        return true
    end

    return false
end

function M.is_trackable(obj, item, ws)
    if not obj or not item then
        return false
    end
    if item.map_only then
        return M.is_map_camera_placed(obj, ws) and not M.is_camera_broken(obj)
    end
    return M.is_workspace_placed(obj, ws) and not M.is_broken(obj, item)
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

function M.camera_status_label(obj, base_label)
    if not is_valid(obj) then
        return base_label
    end
    if get_attr(obj, "Disabled") == true then
        return base_label .. " (OFF)"
    end
    if M.is_camera_broken(obj) then
        return base_label .. " (BROKEN)"
    end
    return base_label
end

return M

end)()

-- ── menu/menu_defs.lua ──
OperationOne._mods["menu.menu_defs"] = (function()
local menu_util = OperationOne.require("core.menu_util")

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
    {g = "Combat", t = "checkbox", id = "silent_gadget_aim", n = "Silent Gadget Aim", v = false, p = "silent_filter_visible"},
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
    {g = "Combat", t = "separator"},
    {g = "Combat", t = "label", n = "Gun Mods (GC)"},
    {g = "Combat", t = "checkbox", id = "gun_mods_enabled", n = "Enable Gun Mods", v = false},
    {g = "Combat", t = "checkbox", id = "gm_no_recoil", n = "No Recoil", v = false, p = "gun_mods_enabled"},
    {g = "Combat", t = "checkbox", id = "gm_no_spread", n = "No Spread", v = false, p = "gun_mods_enabled"},
    {g = "Combat", t = "checkbox", id = "gm_firerate_enabled", n = "Fire Rate", v = false, p = "gun_mods_enabled"},
    {
        g = "Combat",
        t = "slider_int",
        id = "gm_firerate",
        n = "Fire Rate (RPM)",
        min = 400,
        max = 2000,
        v = 1200,
        p = "gm_firerate_enabled"
    },
    {g = "Combat", t = "checkbox", id = "gm_speed_enabled", n = "Weapon Swap Speed", v = false, p = "gun_mods_enabled"},
    {
        g = "Combat",
        t = "slider_float",
        id = "gm_speed_mult",
        n = "Swap Speed Mult",
        min = 1.0,
        max = 1.5,
        v = 1.2,
        p = "gm_speed_enabled"
    },
    {g = "Combat", t = "checkbox", id = "gm_reload_enabled", n = "Fast Reload", v = false, p = "gun_mods_enabled"},
    {
        g = "Combat",
        t = "slider_float",
        id = "gm_reload_mult",
        n = "Reload Speed Mult",
        min = 1.0,
        max = 4.0,
        v = 2.5,
        p = "gm_reload_enabled"
    },
    {g = "Combat", t = "checkbox", id = "gm_accuracy_enabled", n = "Max Accuracy", v = false, p = "gun_mods_enabled"},
    {g = "Combat", t = "checkbox", id = "gm_ads_enabled", n = "Instant ADS", v = false, p = "gun_mods_enabled"},
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
        o = {"Drone", "C4", "Claymore", "Jammer", "Sticky Cam", "Breach", "Map Cam", "Hard Breach", "Prox Alarm", "BP Cam"},
        v = {false, false, false, false, false, false, false, false, false, false},
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
OperationOne._mods["core.settings"] = (function()
local menu_defs = OperationOne.require("menu.menu_defs")
local world_items = OperationOne.require("game.world_items")

local M = {}
M.s = {}

local _callbacks = {}

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

-- ── core/draw_util.lua ──
OperationOne._mods["core.draw_util"] = (function()
local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")

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
OperationOne._mods["game.world_scan"] = (function()
--[[ World gadget scan — workspace + map cameras, per-type lifecycle from game dump. ]]

local draw_util = OperationOne.require("core.draw_util")
local world_items = OperationOne.require("game.world_items")
local gadget_team = OperationOne.require("game.gadget_team")
local gadget_lifecycle = OperationOne.require("game.gadget_lifecycle")

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

local function should_scan_item(item, s, utilities_active)
    if s[item.enabled] then
        return true
    end
    if utilities_active and TARGETABLE_UTILITIES[item.label] then
        return true
    end
    return false
end

local function in_draw_range(dsq, max_sq, hide_sq, dynamic)
    if dsq > max_sq then
        return false
    end
    if dynamic then
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

local function resolve_position(obj, item, anchor)
    local pos, sz = get_world_item_position(obj, item)
    if pos then
        return pos, sz, anchor or gadget_lifecycle.find_anchor(obj, item)
    end

    anchor = anchor or gadget_lifecycle.find_anchor(obj, item)
    if anchor then
        local x, y, z = unpack_pos(anchor.Position or anchor.position)
        if x then
            return {X = x, Y = y, Z = z}, anchor.Size or anchor.size, anchor
        end
    end

    return nil, nil, anchor
end

local function make_entry(obj, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, camera_item)
    local scan_item = camera_item or item
    if not gadget_lifecycle.is_trackable(obj, scan_item, ws) then
        return nil
    end

    local anchor = gadget_lifecycle.find_anchor(obj, scan_item)
    if not anchor then
        return nil
    end

    local pos, sz, resolved_anchor = resolve_position(obj, scan_item, anchor)
    if not pos then
        return nil
    end
    anchor = resolved_anchor or anchor

    local px, py, pz = unpack_pos(pos)
    if not px then
        return nil
    end

    local dsq = dist3d_sq(px, py, pz, cam_x, cam_y, cam_z)
    local is_dynamic = item and item.dynamic == true
    if not in_draw_range(dsq, max_sq, hide_sq, is_dynamic) then
        return nil
    end

    local label = item and item.label or (camera_item and camera_item.label) or obj.Name
    if camera_item then
        label = gadget_lifecycle.camera_status_label(obj, label)
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
        key = M.inst_key(obj),
        dynamic = item and item.dynamic == true,
        static = (item and item.static == true) or (camera_item and camera_item.static == true),
        map_only = camera_item and camera_item.map_only == true,
        is_teammate_gadget = gadget_team.is_friendly_gadget(obj),
        is_broken = gadget_lifecycle.is_broken(obj, scan_item),
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

function M.sync_workspace(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active)
    local lookup = world_items.world_items_by_name

    if not is_valid(ws) then
        return
    end

    for _, child in ipairs(ws:GetChildren()) do
        local item = lookup[child.Name]
        if item and should_scan_item(item, s, utilities_active) then
            if gadget_lifecycle.is_trackable(child, item, ws) then
                local key = M.inst_key(child)
                if key then
                    seen[key] = true
                    local entry = cache.world_lookup[key]
                    if entry then
                        M.refresh_flags(entry, s)
                        entry.is_teammate_gadget = gadget_team.is_friendly_gadget(child)
                        entry.is_broken = gadget_lifecycle.is_broken(child, item)
                    else
                        entry = make_entry(child, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, nil)
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
        return gadget_lifecycle.is_trackable(obj, item, ws)
    end, seen)
end

function M.sync_map_cameras(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active)
    local default_camera = world_items.camera_items_by_name.DefaultCamera

    if not default_camera then
        return
    end

    local enabled = s[default_camera.enabled]
        or (utilities_active and TARGETABLE_UTILITIES["MAP CAM"])

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
                    if gadget_lifecycle.is_trackable(child, default_camera, ws) then
                        local key = M.inst_key(child)
                        if key then
                            seen[key] = true
                            local entry = cache.world_lookup[key]
                            if entry then
                                M.refresh_flags(entry, s)
                                entry.is_broken = gadget_lifecycle.is_broken(child, default_camera)
                                entry.label = gadget_lifecycle.camera_status_label(child, default_camera.label)
                            else
                                entry = make_entry(child, nil, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, default_camera)
                                if entry then
                                    add_entry(cache, entry)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    prune_entries(cache, function(w)
        return w.map_only == true
    end, function(obj)
        return gadget_lifecycle.is_trackable(obj, default_camera, ws)
    end, seen)
end

function M.refresh_workspace_entry(entry, cam_x, cam_y, cam_z, sqrt, ws)
    if not entry or entry.map_only then
        return false
    end
    if not gadget_lifecycle.is_trackable(entry.obj, entry.item, ws) then
        return false
    end

    local anchor = gadget_lifecycle.find_anchor(entry.obj, entry.item)
    if not anchor then
        return false
    end

    local pos, _, resolved_anchor = resolve_position(entry.obj, entry.item, anchor)
    if not pos then
        return false
    end
    anchor = resolved_anchor or anchor

    local x, y, z = unpack_pos(pos)
    if not x then
        return false
    end

    entry.anchor = anchor
    entry.x = x
    entry.y = y
    entry.z = z
    entry.dist = sqrt(dist3d_sq(x, y, z, cam_x, cam_y, cam_z))
    entry.bbox = gadget_bbox(entry.item, anchor)
    entry.is_teammate_gadget = gadget_team.is_friendly_gadget(entry.obj)
    entry.is_broken = gadget_lifecycle.is_broken(entry.obj, entry.item)
    return true
end

function M.refresh_map_camera_entry(entry, cam_x, cam_y, cam_z, sqrt, ws)
    if not entry or not entry.map_only then
        return false
    end

    local camera_item = entry.item or world_items.camera_items_by_name.DefaultCamera
    if not camera_item or not gadget_lifecycle.is_trackable(entry.obj, camera_item, ws) then
        return false
    end

    local anchor = gadget_lifecycle.find_anchor(entry.obj, camera_item)
    if not anchor then
        return false
    end

    local x, y, z = unpack_pos(anchor.Position or anchor.position)
    if not x then
        return false
    end

    entry.anchor = anchor
    entry.x = x
    entry.y = y
    entry.z = z
    entry.dist = sqrt(dist3d_sq(x, y, z, cam_x, cam_y, cam_z))
    entry.bbox = bbox_from_part(anchor)
    entry.is_broken = gadget_lifecycle.is_broken(entry.obj, camera_item)
    entry.label = gadget_lifecycle.camera_status_label(entry.obj, camera_item.label)
    return true
end

function M.refresh_flags(entry, s)
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

function M.refresh_all(cache, cam_x, cam_y, cam_z, sqrt, ws)
    ws = ws or cache.ws
    for i = #cache.world, 1, -1 do
        local w = cache.world[i]
        local ok
        if w.map_only then
            ok = M.refresh_map_camera_entry(w, cam_x, cam_y, cam_z, sqrt, ws)
        else
            ok = M.refresh_workspace_entry(w, cam_x, cam_y, cam_z, sqrt, ws)
        end
        if not ok then
            remove_entry(cache, w)
            table.remove(cache.world, i)
        end
    end
end

return M

end)()

-- ── core/silent_ray.lua ──
OperationOne._mods["core.silent_ray"] = (function()
--[[ Silent raycast hook — Vector API track_silent_target (see docs/API.md). ]]

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

    if game and game.Workspace then
        local cam = game.Workspace:FindFirstChild("Camera")
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

-- ── features/combat/silent_resolve.lua ──
OperationOne._mods["features.combat.silent_resolve"] = (function()
--[[ Silent ray origin — camera to target (Operation One hitscan). ]]

local silent_ray = OperationOne.require("core.silent_ray")

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

-- ── game/gc_weapon_mods.lua ──
OperationOne._mods["game.gc_weapon_mods"] = (function()
--[[ Operation One weapon mods — refreshgc → getgc(keys) → applygc(keys, values) ]]

local debug = OperationOne.require("core.debug")
local env = OperationOne.require("core.env")

local M = {}

M.WEAPON_STAT_KEYS = {
    "recoil_up",
    "recoil_side",
    "spread",
    "accuracy",
    "firerate",
    "reload_speed",
    "ads",
    "speed",
}

M.WEAPON_FIND_KEYS = {
    "recoil_up",
    "recoil_side",
    "spread",
    "accuracy",
    "firerate",
    "reload_speed",
    "ads",
    "speed",
    "trail_size",
    "pellets",
    "zoom",
    "mag_size",
    "damage",
    "range",
    "destructive",
}

M.ALLOWED = {}
for _, key in ipairs(M.WEAPON_STAT_KEYS) do
    M.ALLOWED[key] = true
end

M._last_node_count = 0

local function has_api()
    return type(refreshgc) == "function"
        and type(getgc) == "function"
        and type(applygc) == "function"
end

function M.available()
    return has_api()
end

function M.last_node_count()
    return M._last_node_count
end

function M.in_game()
    if env.get_local_player() ~= nil then
        return true
    end
    local ws = env.get_workspace()
    return ws ~= nil and ws:FindFirstChild("Viewmodels") ~= nil
end

local function sanitize_payload(mods)
    local out = {}
    for k, v in pairs(mods) do
        if M.ALLOWED[k] and v ~= nil then
            local num = tonumber(v)
            if num ~= nil then
                out[k] = num
            end
        end
    end
    return out
end

local function keys_for_payload(payload)
    local keys = {}
    for k in pairs(payload) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function warm_nodes(keys)
    local count = 0
    local ok, result = pcall(getgc, keys)
    if ok and type(result) == "number" then
        count = result
    end
    if count <= 0 then
        ok, result = pcall(getgc, M.WEAPON_FIND_KEYS)
        if ok and type(result) == "number" then
            count = result
        end
    end
    return count
end

local function patch_count(keys, payload)
    local patched = 0

    local ok, result = pcall(applygc, keys, payload)
    if ok and type(result) == "number" then
        patched = result
    end

    if patched <= 0 then
        ok, result = pcall(applygc, M.WEAPON_FIND_KEYS, payload)
        if ok and type(result) == "number" then
            patched = result
        end
    end

    if patched <= 0 then
        ok, result = pcall(applygc, payload)
        if ok and type(result) == "number" then
            patched = result
        end
    end

    return patched
end

function M.apply_weapon(mods, _quiet)
    if not has_api() then
        return false, 0, "GC API unavailable"
    end

    local payload = sanitize_payload(mods)
    if not next(payload) then
        return false, 0, "No modifiers selected"
    end

    if not M.in_game() then
        return false, 0, "Enter a match first"
    end

    pcall(refreshgc)

    local patch_keys = keys_for_payload(payload)
    warm_nodes(M.WEAPON_FIND_KEYS)
    warm_nodes(patch_keys)

    local patched = patch_count(patch_keys, payload)
    M._last_node_count = math.max(M._last_node_count, patched, warm_nodes(patch_keys))

    if patched > 0 then
        return true, patched, string.format("%d node(s) patched", patched)
    end

    debug.warn_once("gun_mods:nodes", "GC warming — enable master + a mod, wait a moment")
    return false, 0, "GC warming — wait a moment"
end

function M.apply(mods)
    return M.apply_weapon(mods)
end

function M.refresh_cache()
    if not has_api() or not M.in_game() then
        M._last_node_count = 0
        return 0
    end

    pcall(refreshgc)
    warm_nodes(M.WEAPON_FIND_KEYS)
    local count = warm_nodes(M.WEAPON_STAT_KEYS)
    M._last_node_count = count
    return count
end

function M.dump_keys(path)
    if type(dumpgc) ~= "function" then
        return false, 0, "dumpgc unavailable"
    end
    local ok, result = pcall(dumpgc, M.WEAPON_FIND_KEYS, path or "op_one_gc_dump.txt")
    if ok and type(result) == "number" then
        return true, result, "Dumped " .. result .. " entries"
    end
    return false, 0, "dumpgc failed"
end

function M.status_text()
    if not has_api() then
        return "GC: unavailable"
    end
    return string.format("GC nodes: %d", M._last_node_count)
end

return M

end)()

-- ── features/utility/config.lua ──
OperationOne._mods["features.utility.config"] = (function()
local menu_defs = OperationOne.require("menu.menu_defs")
local menu_util = OperationOne.require("core.menu_util")

local M = {}
local menu_items = menu_defs.menu_items

local AUTOLOAD_FILE = 'AnxietyAutoload.txt'

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
        print('[Anxiety] Save failed - could not open: ' .. path)
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
    print('[Anxiety] Config saved: ' .. path)
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
        print('[Anxiety] Config loaded: ' .. path .. ' (' .. count .. ' values)')
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
    -- Autoload on startup: try AnxietyAutoload.txt first, then fallback to default
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
OperationOne._mods["features.combat.scan"] = (function()
local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local world_scan = OperationOne.require("game.world_scan")
local draw_util = OperationOne.require("core.draw_util")

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
local PLAYER_DISCOVER_MS = 200
local WORLD_STATIC_MS = 2500

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
    if now - last_char_update < 1.0 then
        return
    end
    last_char_update = now

    local new_cache = {}
    for _, c in ipairs(cache.ws:GetChildren()) do
        if c.ClassName == "Model" then
            local hrp, hum = c:FindFirstChild("HumanoidRootPart"), c:FindFirstChild("Humanoid")
            if hrp and hrp.Position and hum then
                new_cache[c] = {hrp = hrp, hum = hum}
            end
        end
    end
    cache.char_models = new_cache
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

    local char_data = cache.char_models[char_obj]
    local hp, mhp = 100, 125
    if char_data and char_data.hum then
        hp, mhp = char_data.hum.Health, char_data.hum.MaxHealth
    end
    if hp <= 0 then
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

    local p_obj = player_lookup[cn]
    local php = (p_obj and p_obj.head_position) and
        {x = p_obj.head_position.x, y = p_obj.head_position.y, z = p_obj.head_position.z} or
        {x = hx, y = hy, z = hz}

    local now = tick_ms()
    local velocity = update_velocity({name = cn}, cn, php, now)

    local entry = {
        name = cn,
        dist = sqrt(dsq),
        bones = bns,
        bbox = bbox,
        weapon = wpn,
        health = hp,
        max_health = mhp,
        is_teammate = is_teammate(vm),
        viewmodel = vm,
        char_obj = char_obj,
        look_vector = lv,
        is_visible = false,
        head_pos = php,
        velocity = velocity,
        player_obj = p_obj,
    }
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

    if p.char_obj and cache.char_models[p.char_obj] and cache.char_models[p.char_obj].hum then
        local hum = cache.char_models[p.char_obj].hum
        p.health = hum.Health
        p.max_health = hum.MaxHealth
        if p.health <= 0 then
            return false
        end
    end

    if h.LookVector then
        p.look_vector = {x = h.LookVector.X, y = h.LookVector.Y, z = h.LookVector.Z}
    end

    local p_obj = player_lookup[p.name]
    p.player_obj = p_obj
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
    local silent_gadgets = s.silent_aim_enabled and s.silent_filter_visible and s.silent_gadget_aim
    return s.world_enabled or utilities_active or silent_gadgets
end

function M.scan_world()
    local utilities_active = s.aimbot_enabled and s.utilities_aimbot
    if not cache.ws or not M.needs_world_scan() then
        cache.world = {}
        cache.world_lookup = {}
        return
    end

    local now = tick_ms()
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z

    for i = 1, #cache.world do
        world_scan.refresh_flags(cache.world[i], s)
    end

    world_scan.refresh_all(cache, cam_x, cam_y, cam_z, sqrt, cache.ws)

    world_scan.sync_workspace(
        cache.ws, s, utilities_active, cache,
        cam_x, cam_y, cam_z, DIST.ESP_HIDE_SQ, sqrt
    )

    world_scan.sync_map_cameras(
        cache.ws, s, utilities_active, cache,
        cam_x, cam_y, cam_z, DIST.ESP_HIDE_SQ, sqrt
    )

    if now - last_world_static >= WORLD_STATIC_MS then
        last_world_static = now
        cache.stats.last_world_scan = now
    end
end

return M

end)()

-- ── features/combat/aimbot.lua ──
OperationOne._mods["features.combat.aimbot"] = (function()
local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local draw_util = OperationOne.require("core.draw_util")

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
    local main_kd = input.is_key_down(menu.get_key("aimbot_enabled"))
    if main_kd and not cache.aim.last_main_key_state then
        s.aimbot_enabled = not s.aimbot_enabled
        menu.set("aimbot_enabled", s.aimbot_enabled)
        cache.aim.locked_target, cache.aim.current_target = nil, nil
    end
    cache.aim.last_main_key_state = main_kd
    if not s.aimbot_enabled then
        cache.aim.current_target, cache.aim.locked_target = nil, nil
        return
    end
    local kd = input.is_key_down(menu.get_key("aimbot_key"))
    if not kd and cache.aim.last_key_state then
        cache.aim.locked_target = nil
    end
    cache.aim.last_key_state = kd
    
    local lmb_kd = input.is_key_down(0x01)
    local lmb_clicked = lmb_kd and not cache.aim.last_lmb_state
    cache.aim.last_lmb_state = lmb_kd

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
            if s.aimbot_flick then
                if lmb_kd then
                    if lmb_clicked then
                        -- Initial Snap to Head
                        local hb = cache.aim.locked_target.bones and cache.aim.locked_target.bones.head
                        if hb then camera.look_at(hb.x, hb.y, hb.z) end
                    else
                        -- Smoothed tracking during spray
                        smooth_aim(sx, sy, cx, cy, smooth)
                    end
                end
            else
                -- Normal non-flick aimbot tracks while aimkey is held
                smooth_aim(sx, sy, cx, cy, smooth)
            end
            return
        end
        cache.aim.locked_target = nil
    end
    local best, bd = nil, math.huge
    for _, p in ipairs(cache.players) do
        if (not s.aimbot_team_check or not p.is_teammate) and p.dist <= s.aimbot_max_distance and (not s.aimbot_vischeck or p.is_visible) then
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
        local tu = {
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
        }
        local bl_opts = s.gadget_aim_blacklist or {}
        local bl_labels = {
            "DRONE", "C4", "CLAYMORE", "JAMMER", "STICKY CAM", "BREACH",
            "MAP CAM", "HARD BREACH", "PROX ALARM", "BP CAM",
        }
        local aim_blacklist = {}
        for i, enabled in ipairs(bl_opts) do
            if enabled and bl_labels[i] then
                aim_blacklist[bl_labels[i]] = true
            end
        end
        for _, w in ipairs(cache.world) do
            if w.dist <= s.utilities_max_distance and tu[w.label] and not aim_blacklist[w.label] then
                if w.is_broken then
                    goto continue_gadget
                end
                if s.world_team_check and w.is_teammate_gadget then
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
        if s.aimbot_flick then
            if lmb_kd then
                if lmb_clicked then
                    -- Initial Snap to Head
                    local hb = best.target.bones and best.target.bones.head
                    if hb then camera.look_at(hb.x, hb.y, hb.z) end
                else
                    -- Smoothed tracking during spray
                    smooth_aim(best.screen_x, best.screen_y, cx, cy, smooth)
                end
            end
        else
            -- Normal non-flick aimbot tracks while aimkey is held
            smooth_aim(best.screen_x, best.screen_y, cx, cy, smooth)
        end
    else
        cache.aim.current_target = nil
    end
end

function M.process_toggle(key_id, state_table, setting_id)
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
OperationOne._mods["features.combat.silent_aim"] = (function()
local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local silent_ray = OperationOne.require("core.silent_ray")
local silent_resolve = OperationOne.require("features.combat.silent_resolve")

local sqrt = constants.sqrt
local AIM_TARGET = constants.AIM_TARGET
local SHOOT_VK = 0x01
local TARGET_SCAN_MS = 33

local M = {}
local s = settings.s
local locked_target = nil
local last_target_scan = 0
local weapon_hold_ticks = 0
local bone_map = {[0] = "head", [1] = "torso", [2] = "arm1", [3] = "arm2", [4] = "leg1", [5] = "leg2"}

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

local function apply_prediction(pos, p)
    if not pos or not s.silent_prediction or not p or not p.velocity then
        return pos
    end
    local factor = (s.silent_prediction_val or 50) * 0.001
    return {
        x = pos.x + p.velocity.x * factor,
        y = pos.y + p.velocity.y * factor,
        z = pos.z + p.velocity.z * factor,
    }
end

local function get_bone_pos(p)
    if not p then
        return nil
    end

    local pos
    local bone = bone_map[s.silent_bone]
    if bone then
        pos = live_bone_pos(p, bone)
    else
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
        pos = nb
    end

    return apply_prediction(pos, p)
end

local function gadget_visible(w)
    if not w then
        return false
    end
    if not raycast or not raycast.is_visible then
        return true
    end
    return raycast.is_visible(cache.cam_x, cache.cam_y, cache.cam_z, w.x, w.y, w.z)
end

local function passes_gadget_filters(w)
    if not w or not w.x then
        return false
    end
    if not TARGETABLE_UTILITIES[w.label] then
        return false
    end
    if w.dist > (s.silent_max_dist or 250) then
        return false
    end
    if w.is_broken then
        return false
    end
    if s.world_team_check and w.is_teammate_gadget then
        return false
    end
    return gadget_visible(w)
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

    for _, p in ipairs(cache.players) do
        if passes_filters(p) then
            local score = score_player(p, cx, cy, fov)
            if score and score < best_score then
                best_score = score
                best = p
            end
        end
    end

    if s.silent_filter_visible and s.silent_gadget_aim then
        for _, w in ipairs(cache.world) do
            local score = score_gadget(w, cx, cy, fov)
            if score and score < best_score then
                best_score = score
                best = {is_gadget = true, world_entry = w, key = w.key}
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
    return s.silent_aim_enabled and silent_ray.available()
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
        if s.silent_fov_fill then
            local fc = s.silent_fov_fill_color or {col[1], col[2], col[3], 0.08}
            draw.circle_filled(cx, cy, fov, fc, 64)
        end
        if s.silent_fov_style == 1 then
            draw.circle_filled(cx, cy, fov, {col[1], col[2], col[3], col[4] * 0.15}, 64)
        end
        draw.circle(cx, cy, fov, col, 64, 1)
    end

    if s.silent_target_line and locked_target then
        local aim = M.get_aim_point()
        if aim then
            local tx, ty, vis = w2s(aim.x, aim.y, aim.z)
            if vis then
                local col = s.silent_target_line_color or {1, 0.25, 0.25, 1}
                draw.line(cx, cy, tx, ty, col, 1.5)
            end
        end
    end
end

return M

end)()

-- ── features/combat/gun_mods.lua ──
OperationOne._mods["features.combat.gun_mods"] = (function()
local settings = OperationOne.require("core.settings")
local gc = OperationOne.require("game.gc_weapon_mods")

local M = {}

local s = settings.s
local RETRY_MS = 750
local RETRY_MAX_MS = 30000

M._apply_dirty = false
M._force_apply = false
M._defer_until = 0
M._retry_until = 0
M._was_enabled = false
M._status = "GC: idle"
M._logged_apply = false
M._callbacks_ready = false
M._last_mod_sig = ""

local MOD_IDS = {
    "gm_no_recoil",
    "gm_no_spread",
    "gm_firerate_enabled",
    "gm_speed_enabled",
    "gm_reload_enabled",
    "gm_accuracy_enabled",
    "gm_ads_enabled",
    "gm_firerate",
    "gm_speed_mult",
    "gm_reload_mult",
}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function build_mods()
    local mods = {}

    if s.gm_no_recoil then
        mods.recoil_up = 0
        mods.recoil_side = 0
    end

    if s.gm_no_spread then
        mods.spread = 0
    end

    if s.gm_firerate_enabled then
        mods.firerate = s.gm_firerate or 1200
    end

    if s.gm_speed_enabled then
        mods.speed = s.gm_speed_mult or 1.2
    end

    if s.gm_reload_enabled then
        mods.reload_speed = s.gm_reload_mult or 2.5
    end

    if s.gm_accuracy_enabled then
        mods.accuracy = 25
    end

    if s.gm_ads_enabled then
        mods.ads = 0
    end

    return mods
end

local function payload_signature(mods)
    local keys = {}
    for k in pairs(mods) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        parts[i] = k .. "=" .. tostring(mods[k])
    end
    return table.concat(parts, ";")
end

local function has_active_mods()
    return s.gm_no_recoil
        or s.gm_no_spread
        or s.gm_firerate_enabled
        or s.gm_speed_enabled
        or s.gm_reload_enabled
        or s.gm_accuracy_enabled
        or s.gm_ads_enabled
end

function M.schedule_apply(delay_ms)
    M._apply_dirty = true
    M._force_apply = true
    local now = tick_ms()
    local until_ms = now + (delay_ms or 400)
    if until_ms > M._defer_until then
        M._defer_until = until_ms
    end
    if M._retry_until <= now then
        M._retry_until = now + RETRY_MAX_MS
    end
end

function M.try_apply(silent)
    if not s.gun_mods_enabled or not has_active_mods() then
        M._status = "GC: off"
        M._apply_dirty = false
        M._force_apply = false
        return false
    end

    local mods = build_mods()
    if not next(mods) then
        return false
    end

    if not M._force_apply and not M._apply_dirty then
        M._status = gc.status_text()
        return true
    end

    local ok, count, msg = gc.apply_weapon(mods, silent)
    if ok then
        M._apply_dirty = false
        M._force_apply = false
        M._defer_until = 0
        M._retry_until = 0
        M._status = gc.status_text()
        if not silent and not M._logged_apply then
            M._logged_apply = true
            print("[OperationOne] Gun mods: " .. (msg or (count .. " nodes patched")))
        end
        return true
    end

    M._status = msg or "GC: warming"
    M._apply_dirty = true
    M._force_apply = true
    M._defer_until = tick_ms() + RETRY_MS
    return false
end

local function on_mod_changed()
    if s.gun_mods_enabled then
        M.schedule_apply(150)
    end
end

function M.register_callbacks()
    if M._callbacks_ready then
        return
    end

    settings.on_change("gun_mods_enabled", function(enabled)
        if enabled then
            gc.refresh_cache()
            M._logged_apply = false
            M.schedule_apply(500)
            print("[OperationOne] Gun mods enabled — warming GC...")
        else
            M._apply_dirty = false
            M._force_apply = false
            M._defer_until = 0
            M._retry_until = 0
            M._status = "GC: off"
            M._logged_apply = false
        end
    end)

    for _, id in ipairs(MOD_IDS) do
        settings.on_change(id, on_mod_changed)
    end

    M._callbacks_ready = true
end

function M.update(_dt)
    local enabled = s.gun_mods_enabled and has_active_mods()

    if enabled and not M._was_enabled then
        gc.refresh_cache()
        M._logged_apply = false
        M.schedule_apply(500)
    elseif not enabled and M._was_enabled then
        M._apply_dirty = false
        M._force_apply = false
        M._status = "GC: off"
        M._logged_apply = false
    end

    M._was_enabled = enabled

    if not s.gun_mods_enabled then
        return
    end

    local mods = build_mods()
    local sig = payload_signature(mods)
    if sig ~= M._last_mod_sig then
        M._last_mod_sig = sig
        if has_active_mods() then
            M.schedule_apply(150)
        end
    end

    if not has_active_mods() then
        M._apply_dirty = false
        M._force_apply = false
        return
    end

    local now = tick_ms()

    if not M._apply_dirty then
        return
    end

    if now < M._defer_until then
        return
    end

    if M._retry_until > 0 and now > M._retry_until then
        M._apply_dirty = false
        M._force_apply = false
        M._status = "GC: timeout — toggle mods again"
        return
    end

    M.try_apply(true)
end

function M.get_status()
    return M._status
end

function M.register_menu()
    local menu_util = OperationOne.require("core.menu_util")
    local gc_mod = OperationOne.require("game.gc_weapon_mods")
    menu_util.ensure_groups()
    menu.add_button(menu_util.TAB, "Combat", "gm_dump_gc", "Dump GC Keys", function()
        local ok, count, msg = gc_mod.dump_keys("op_one_gc_dump.txt")
        print("[OperationOne] " .. (msg or (ok and "dump ok" or "dump failed")) .. " (" .. tostring(count) .. ")")
    end, { parent = "gun_mods_enabled" })
    M.register_callbacks()
end

return M

end)()

-- ── features/visuals/player_esp.lua ──
OperationOne._mods["features.visuals.player_esp"] = (function()
local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local draw_util = OperationOne.require("core.draw_util")

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
                local hf = clamp(p.health / p.max_health, 0, 1)
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
OperationOne._mods["features.visuals.world_esp"] = (function()
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local draw_util = OperationOne.require("core.draw_util")
local world_scan = OperationOne.require("game.world_scan")

local floor = OperationOne.require("core.constants").floor
local DIST = OperationOne.require("core.constants").DIST

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
            local dsq = dist3d_sq(w.x, w.y, w.z, cam_x, cam_y, cam_z)
            if dsq > max_sq then
                goto continue
            end
            if not w.dynamic and dsq <= DIST.ESP_HIDE_SQ then
                goto continue
            end
            w.dist = math.sqrt(dsq)
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
OperationOne._mods["features.visuals.aimbot_visuals"] = (function()
local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")

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
OperationOne._mods["features.visuals.crosshair"] = (function()
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")

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
OperationOne._mods["features.utility.keybind_window"] = (function()
local settings = OperationOne.require("core.settings")

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
    if s.gun_mods_enabled then
        itms[#itms + 1] = "Gun Mods: ON"
    end
    if #itms > 0 then
        draw.window(1500, 200, "keybind_list", " KEYBINDS ", itms)
    end
end

M.draw_keybind_window = draw_keybind_window

return M

end)()

-- ── menu/tabs.lua ──
OperationOne._mods["menu.tabs"] = (function()
local menu_defs = OperationOne.require("menu.menu_defs")
local config = OperationOne.require("features.utility.config")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local scan = OperationOne.require("features.combat.scan")
local aimbot = OperationOne.require("features.combat.aimbot")
local silent_aim = OperationOne.require("features.combat.silent_aim")
local gun_mods = OperationOne.require("features.combat.gun_mods")
local player_esp = OperationOne.require("features.visuals.player_esp")
local world_esp = OperationOne.require("features.visuals.world_esp")
local aimbot_visuals = OperationOne.require("features.visuals.aimbot_visuals")
local crosshair = OperationOne.require("features.visuals.crosshair")
local keybind_window = OperationOne.require("features.utility.keybind_window")

local M = {}
M._menu_registered = false

function M.register_all()
    if M._menu_registered then return end
    menu_defs.register_all()
    gun_mods.register_menu()
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
    cache.ws = game.Workspace
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
    menu.set_visible("silent_prediction_val", s.silent_aim_enabled and s.silent_prediction)
    menu.set_visible("silent_fov_style", s.silent_aim_enabled and s.silent_draw_fov)
    menu.set_visible("silent_fov_fill", s.silent_aim_enabled and s.silent_draw_fov)
    menu.set_visible("silent_gadget_aim", s.silent_aim_enabled and s.silent_filter_visible)
    scan.update_char_models()
    scan.scan_players()
    scan.scan_world()
    aimbot.process_toggle("players_enabled", cache.toggles.player, "players_enabled")
    aimbot.process_toggle("world_enabled", cache.toggles.world, "world_enabled")
    silent_aim.update(_dt)
    aimbot.process_aimbot()
    gun_mods.update(_dt)
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
OperationOne._mods["app"] = (function()
local tabs = OperationOne.require("menu.tabs")
local debug = OperationOne.require("core.debug")

local M = {}
local initialized = false

function M.init()
    if initialized then return true end
    initialized = tabs.init()
    return initialized
end

function M.on_frame()
    if not initialized then return end
    debug.tick_frame()

    local dt = 0.016
    if utility and utility.get_delta_time then
        dt = utility.get_delta_time()
    end

    debug.guard("tabs.update", tabs.update, dt)
    debug.guard("tabs.draw", tabs.draw)
end

return M

end)()

do
    OperationOne.require("menu.tabs").register_all()
end

OperationOne._init_ok = false

local ok, err = pcall(function()
    local debug = OperationOne.require("core.debug")
    local app = OperationOne.require("app")

    if not app.init() then
        debug.error_once("init", "app.init() returned false")
        return
    end

    OperationOne._init_ok = true

    if not debug.register_frame_hook(function()
        app.on_frame()
    end) then
        debug.error_once("init", "Failed to register on_frame")
    end
end)

if not ok then
    print("[OperationOne] Fatal: " .. tostring(err))
    if debug and debug.traceback then print(debug.traceback(err)) end
end

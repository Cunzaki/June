local settings = June.require("core.settings")
local cache = June.require("core.cache")
local env = June.require("core.env")
local gpu_chams = June.require("core.gpu_chams")
local world_items = June.require("game.world_items")

local M = {}

local PLAYER_CHAMS = "players_engine_chams"
local PLAYER_MODE = "players_engine_chams_mode"
local PLAYER_COLOR = "players_engine_chams_color"
local PLAYER_RANGE = "players_engine_chams_range"
local PLAYER_TEAM = "players_engine_chams_team_check"
local PLAYER_VIS = "players_engine_chams_vischeck"

local WORLD_CHAMS = "world_engine_chams"
local WORLD_MODE = "world_engine_chams_mode"
local WORLD_COLOR = "world_engine_chams_color"
local WORLD_RANGE = "world_engine_chams_range"

local PLAYER_PARTS = {
    {label = "Head", bones = {"head"}},
    {label = "Torso", bones = {"torso"}},
    {label = "Left Arm", bones = {"arm1"}},
    {label = "Right Arm", bones = {"arm2"}},
    {label = "Left Leg", bones = {"leg1"}},
    {label = "Right Leg", bones = {"leg2"}},
    {label = "Left Shoulder", bones = {"shoulder1"}},
    {label = "Right Shoulder", bones = {"shoulder2"}},
    {label = "Left Hip", bones = {"hip1"}},
    {label = "Right Hip", bones = {"hip2"}},
}

local WORLD_CHAMS_ITEMS = {}
do
    for _, item in ipairs(world_items.world_items) do
        WORLD_CHAMS_ITEMS[#WORLD_CHAMS_ITEMS + 1] = {
            label = item.name,
            enabled = item.enabled,
            match_label = item.label,
            item = item,
        }
    end
    for _, item in ipairs(world_items.camera_items) do
        WORLD_CHAMS_ITEMS[#WORLD_CHAMS_ITEMS + 1] = {
            label = "Map Cam",
            enabled = item.enabled,
            match_label = item.label,
            item = item,
            map_cam = true,
        }
    end
end

local _wired = false

local function players_active()
    if not gpu_chams.available() then
        return false
    end
    if not settings.enabled("players_enabled") then
        return false
    end
    return gpu_chams.multicombo_any(PLAYER_CHAMS, #PLAYER_PARTS)
end

local function world_active()
    if not gpu_chams.available() then
        return false
    end
    if not settings.enabled("world_enabled") then
        return false
    end
    return gpu_chams.multicombo_any(WORLD_CHAMS, #WORLD_CHAMS_ITEMS)
end

local function selected_player_bones()
    local bones = {}
    for i, part in ipairs(PLAYER_PARTS) do
        if gpu_chams.multicombo_selected(PLAYER_CHAMS, i) then
            for _, b in ipairs(part.bones) do
                bones[#bones + 1] = b
            end
        end
    end
    return bones
end

local function collect_player_chams(applied)
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z
    if not cam_x then
        return
    end

    local range = settings.num(PLAYER_RANGE, 250)
    local range_sq = range * range
    local team_check = settings.enabled(PLAYER_TEAM)
    local vis_check = settings.enabled(PLAYER_VIS)
    local bones = selected_player_bones()
    if #bones == 0 then
        return
    end

    for _, p in ipairs(cache.players) do
        if not p or not p.viewmodel or not env.is_valid(p.viewmodel) then
            goto continue
        end
        if not p.health or p.health <= 0 then
            goto continue
        end
        if team_check and p.is_teammate then
            goto continue
        end
        if vis_check and not p.is_visible then
            goto continue
        end

        local dist = p.dist
        if not dist and p.head_pos then
            local dx = p.head_pos.x - cam_x
            local dy = p.head_pos.y - cam_y
            local dz = p.head_pos.z - cam_z
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        if dist and (dist * dist) > range_sq then
            goto continue
        end

        local vm = p.viewmodel
        for i = 1, #bones do
            local part = env.safe_call(function()
                return vm:FindFirstChild(bones[i])
            end)
            if part then
                gpu_chams.cham_part(part, applied)
            end
        end
        ::continue::
    end
end

local function world_index_for_entry(w)
    if not w then
        return nil
    end
    for i, meta in ipairs(WORLD_CHAMS_ITEMS) do
        if w.item and meta.item and w.item.enabled == meta.enabled then
            return i
        end
        if meta.map_cam and w.map_only then
            return i
        end
        if meta.match_label and w.label and w.label:find(meta.match_label, 1, true) then
            return i
        end
    end
    return nil
end

local function collect_world_chams(applied)
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z
    if not cam_x then
        return
    end

    local range = settings.num(WORLD_RANGE, 250)
    local range_sq = range * range
    local team_check = settings.enabled("world_team_check")

    for _, w in ipairs(cache.world) do
        if not w or not w.obj or not env.is_valid(w.obj) then
            goto continue
        end
        if w.is_broken then
            goto continue
        end
        if team_check and w.is_teammate_gadget then
            goto continue
        end

        local idx = world_index_for_entry(w)
        if not idx or not gpu_chams.multicombo_selected(WORLD_CHAMS, idx) then
            goto continue
        end

        local dsq = w.dsq
        if not dsq and w.x then
            local dx = w.x - cam_x
            local dy = w.y - cam_y
            local dz = w.z - cam_z
            dsq = dx * dx + dy * dy + dz * dz
        end
        if dsq and dsq > range_sq then
            goto continue
        end

        gpu_chams.cham_entry_part(w, applied)
        ::continue::
    end
end

local function force_sync(owner_id, active_fn)
    if active_fn() then
        gpu_chams.sync_owner(owner_id, true)
    else
        gpu_chams.clear_owner(owner_id)
    end
end

local function wire_owner_callbacks(owner_id, active_fn, multicombo_id, mode_id, color_id, extra_ids)
    settings.on_change(multicombo_id, function()
        force_sync(owner_id, active_fn)
    end)
    for _, id in ipairs(extra_ids or {}) do
        settings.on_change(id, function()
            force_sync(owner_id, active_fn)
        end)
    end
    gpu_chams.wire_style_controls(owner_id, mode_id, color_id)
end

function M.register()
    if _wired then
        return
    end
    _wired = true

    gpu_chams.register_owner("players", {
        rescan_ms = 350,
        is_active = players_active,
        style = function()
            return gpu_chams.mode_index(PLAYER_MODE, 0), gpu_chams.color_index(PLAYER_COLOR, 0)
        end,
        collect = collect_player_chams,
    })

    gpu_chams.register_owner("world", {
        rescan_ms = 500,
        is_active = world_active,
        style = function()
            return gpu_chams.mode_index(WORLD_MODE, 0), gpu_chams.color_index(WORLD_COLOR, 0)
        end,
        collect = collect_world_chams,
    })

    wire_owner_callbacks("players", players_active, PLAYER_CHAMS, PLAYER_MODE, PLAYER_COLOR, {
        "players_enabled",
        PLAYER_RANGE,
        PLAYER_TEAM,
        PLAYER_VIS,
    })
    wire_owner_callbacks("world", world_active, WORLD_CHAMS, WORLD_MODE, WORLD_COLOR, {
        "world_enabled",
        "world_team_check",
        WORLD_RANGE,
    })
end

function M.update()
    if not _wired then
        M.register()
    end
    gpu_chams.sync_owner("players")
    gpu_chams.sync_owner("world")
end

function M.update_visibility(s)
    local players_on = s.players_enabled == true
    local world_on = s.world_enabled == true

    menu.set_visible(PLAYER_CHAMS, players_on)
    menu.set_visible(PLAYER_MODE, players_on)
    menu.set_visible(PLAYER_COLOR, players_on and gpu_chams.color_visible_for_mode(gpu_chams.mode_index(PLAYER_MODE, 0)))
    menu.set_visible(PLAYER_RANGE, players_on)
    menu.set_visible(PLAYER_TEAM, players_on)
    menu.set_visible(PLAYER_VIS, players_on)

    menu.set_visible(WORLD_CHAMS, world_on)
    menu.set_visible(WORLD_MODE, world_on)
    menu.set_visible(WORLD_COLOR, world_on and gpu_chams.color_visible_for_mode(gpu_chams.mode_index(WORLD_MODE, 0)))
    menu.set_visible(WORLD_RANGE, world_on)
end

return M

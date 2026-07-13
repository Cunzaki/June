local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local health = June.require("core.health")
local world_scan = June.require("game.world_scan")
local draw_util = June.require("core.draw_util")
local shootable_gadgets = June.require("game.shootable_gadgets")
local vis_util = June.require("core.vis_util")
local combat_vis = June.require("core.combat_vis")

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

    local char_data = char_obj and cache.char_models[char_obj] or nil
    local p_obj = player_lookup[cn]
    local hp, mhp, alive = health.resolve(cn, p_obj, char_data, vm)
    if not alive or hp <= 0 then
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

    local entry = {
        name = cn,
        dist = sqrt(dsq),
        bones = bns,
        bbox = bbox,
        weapon = wpn,
        health = hp,
        max_health = mhp,
        is_alive = alive,
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

    if not health.apply(p, player_lookup[p.name], p.char_obj and cache.char_models[p.char_obj] or nil) then
        return false
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

    local per_player = (s.players_visible_override and s.players_enabled)
        or (s.silent_filter_visible and s.silent_aim_enabled)

    local function should_check(p)
        local valid_esp = s.players_enabled and (s.players_team or not p.is_teammate)
        local valid_aim = s.aimbot_enabled and (not s.aimbot_team_check or not p.is_teammate)
        local valid_silent = s.silent_aim_enabled and (not s.silent_filter_team or not p.is_teammate)
        return (s.aimbot_vischeck and valid_aim)
            or (s.silent_filter_visible and valid_silent)
            or (s.players_visible_override and valid_esp)
    end

    local function check_player(p)
        local penetrate = s.silent_filter_visible and s.silent_aim_enabled
        return combat_vis.can_see_player(cam_x, cam_y, cam_z, p, p.head_pos, penetrate, nil)
    end

    if per_player then
        for i = 1, #cache.players do
            local p = cache.players[i]
            p.is_visible = false
            if should_check(p) then
                p.is_visible = check_player(p)
            end
        end
        return
    end

    local min_val = math.huge
    local closest_p = nil
    local cx, cy = cache.screen_w * 0.5, cache.screen_h * 0.5

    for i = 1, #cache.players do
        local p = cache.players[i]
        p.is_visible = false
        if should_check(p) then
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

    if closest_p then
        closest_p.is_visible = check_player(closest_p)
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

    local active_names = {}
    for i = 1, #cache.players do
        active_names[cache.players[i].name] = true
    end
    health.prune_cache(active_names)

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

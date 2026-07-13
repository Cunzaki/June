local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local health = June.require("core.health")
local silent_ray = June.require("core.silent_ray")
local silent_resolve = June.require("features.combat.silent_resolve")
local hitscan_visuals = June.require("features.visuals.hitscan_visuals")
local shootable_gadgets = June.require("game.shootable_gadgets")
local combat_origin = June.require("game.combat_origin")
local combat_vis = June.require("core.combat_vis")

local sqrt = constants.sqrt
local AIM_TARGET = constants.AIM_TARGET
local SHOOT_VK = 0x01
local WEAPON_CHECK_MS = 80

local M = {}
local s = settings.s
local locked_target = nil
local last_weapon_check = 0
local weapon_holding = false
local bone_map = {[0] = "head", [1] = "torso", [2] = "arm1", [3] = "arm2", [4] = "leg1", [5] = "leg2"}

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
    local now = tick_ms()
    if now - last_weapon_check < WEAPON_CHECK_MS then
        return weapon_holding
    end
    last_weapon_check = now

    weapon_holding = combat_origin.has_weapon() == true
    if not weapon_holding and input and input.is_key_down and input.is_key_down(SHOOT_VK) then
        weapon_holding = true
    end
    return weapon_holding
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

function M.get_bone_pos(p)
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

local function vis_filter_enabled()
    if menu and menu.get then
        return menu.get("silent_filter_visible") == true
    end
    return s.silent_filter_visible == true
end

local function player_visible(p, aim)
    if not vis_filter_enabled() then
        return true
    end
    if not p or not aim then
        return false
    end
    local cam = silent_ray.get_camera_origin()
    if not cam then
        return false
    end
    local muzzle = combat_origin.get_muzzle_origin()
    return combat_vis.can_see_player(cam.x, cam.y, cam.z, p, aim, true, muzzle)
end

local function passes_gadget_filters(w)
    if not w or not w.x then
        return false
    end
    if not shootable_gadgets.is_shootable_entry(w) then
        return false
    end
    if w.dist > (s.silent_max_dist or 250) then
        return false
    end
    if s.silent_gadget_team_check and w.is_teammate_gadget then
        return false
    end
    if vis_filter_enabled() and w.is_visible ~= true then
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
    if s.silent_filter_health and not health.passes(s, p) then
        return false
    end
    if p.dist > (s.silent_max_dist or 250) then
        return false
    end
    local aim = M.get_bone_pos(p)
    if not aim then
        return false
    end
    return player_visible(p, aim)
end

local function is_valid_player_target(p)
    if not p or not passes_filters(p) then
        return false
    end
    for _, cp in ipairs(cache.players) do
        if cp.viewmodel == p.viewmodel then
            return health.passes(s, cp)
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
    local tb = M.get_bone_pos(p)
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
    local tb = M.get_bone_pos(p)
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

    if s.silent_gadget_aim then
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

    local new = find_target(cx, cy, fov)
    if new then
        locked_target = new
        return
    end

    if is_gadget_target(locked_target) then
        local w = live_world_entry(locked_target.world_entry)
        if not w or not score_gadget(w, cx, cy, fov) then
            locked_target = nil
        end
    elseif locked_target and not in_fov_player(locked_target, cx, cy, fov) then
        locked_target = nil
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
    return M.get_bone_pos(locked_target)
end

function M.update(_dt)
    if not M.active() then
        locked_target = nil
        cache.aim.silent_target_vm = nil
        silent_ray.stop()
        return
    end

    silent_ray.ensure_hook()
    combat_origin.invalidate()

    if not holding_weapon() then
        cache.aim.silent_target_vm = nil
        return
    end

    local cx, cy = cache.screen_w * 0.5, cache.screen_h * 0.5
    local fov = s.silent_fov or 150

    refresh_target(cx, cy, fov)

    if not locked_target then
        cache.aim.silent_target_vm = nil
        return
    end

    if is_gadget_target(locked_target) then
        cache.aim.silent_target_vm = nil
    else
        cache.aim.silent_target_vm = locked_target.viewmodel
    end

    local aim = M.get_aim_point()
    if not aim then
        return
    end

    local origin, resolved_aim, hitpart = silent_resolve.resolve_track(aim, s.silent_bone)
    if not origin or not resolved_aim then
        return
    end

    silent_ray.track(origin, resolved_aim, SHOOT_VK, hitpart or aim, true)
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

    if s.silent_hitscan_vis then
        hitscan_visuals.draw(silent_resolve.last_info)
    end
end

return M

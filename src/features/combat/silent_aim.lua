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

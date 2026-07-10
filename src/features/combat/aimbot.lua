local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local shootable_gadgets = June.require("game.shootable_gadgets")

local sqrt = constants.sqrt
local AIM_TARGET = constants.AIM_TARGET

local M = {}
local s = settings.s

local bone_map = {[0] = "head", [1] = "torso", [2] = "arm1", [3] = "arm2", [4] = "leg1", [5] = "leg2"}

local function screen_center()
    if input and input.get_screen_center then
        local cx, cy = input.get_screen_center()
        if cx and cy then
            return cx, cy
        end
    end
    local sw = cache.screen_w or 0
    local sh = cache.screen_h or 0
    if sw > 0 and sh > 0 then
        return sw * 0.5, sh * 0.5
    end
    if utility and utility.get_screen_size then
        sw, sh = utility.get_screen_size()
        if sw and sh and sw > 0 and sh > 0 then
            cache.screen_w, cache.screen_h = sw, sh
            return sw * 0.5, sh * 0.5
        end
    end
    return 0, 0
end

local function get_target_bone(p)
    if not p or not p.bones then
        return nil
    end

    local pos = nil
    local bone = bone_map[s.aimbot_bone]

    if bone then
        pos = p.bones[bone]
    else
        local cx, cy = screen_center()
        local nb, nd = nil, math.huge
        for _, bp in pairs(p.bones) do
            if bp and bp.x then
                local sx, sy, vis = utility.world_to_screen(bp.x, bp.y, bp.z)
                if vis and sx and sy then
                    local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                    if d < nd then
                        nd, nb = d, bp
                    end
                end
            end
        end
        pos = nb
    end

    if not pos then
        return nil
    end

    if s.aimbot_prediction and p.velocity then
        local factor = (s.aimbot_prediction_val or 0) * 0.001
        return {
            x = pos.x + (p.velocity.x * factor),
            y = pos.y + (p.velocity.y * factor),
            z = pos.z + (p.velocity.z * factor)
        }
    end

    return pos
end

local function is_target_valid(lt)
    if not lt then
        return false
    end
    if lt.is_utility then
        return lt.world_obj and cache.world_lookup[lt.world_obj] and
            cache.world_lookup[lt.world_obj].dist <= (s.utilities_max_distance or 75)
    end
    for _, p in ipairs(cache.players) do
        if p.viewmodel == lt.viewmodel then
            return p.health > 0 and p.dist <= (s.aimbot_max_distance or 500)
        end
    end
    return false
end

-- Relative mouse aim toward a screen point. Uses input.move_mouse only.
local function move_aim_to(sx, sy, cx, cy, smooth, snap)
    if not sx or not sy or not cx or not cy then
        return false
    end
    if not input or not input.move_mouse then
        return false
    end

    local dx = sx - cx
    local dy = sy - cy
    local dist_sq = dx * dx + dy * dy
    if dist_sq < 0.25 then
        return true
    end

    local mx, my
    if snap then
        mx, my = dx, dy
    else
        local div = tonumber(smooth) or 1
        if div < 1 then
            div = 1
        end
        mx = dx / div
        my = dy / div

        -- Integer-safe minimum step so truncated mouse APIs still move.
        if dx > 0 and mx < 1 then
            mx = 1
        elseif dx < 0 and mx > -1 then
            mx = -1
        end
        if dy > 0 and my < 1 then
            my = 1
        elseif dy < 0 and my > -1 then
            my = -1
        end

        if math.abs(mx) > math.abs(dx) then
            mx = dx
        end
        if math.abs(my) > math.abs(dy) then
            my = dy
        end
    end

    if mx ~= 0 or my ~= 0 then
        input.move_mouse(mx, my)
    end
    return true
end

function M.is_target_valid(lt)
    return is_target_valid(lt)
end

function M.smooth_aim(sx, sy, cx, cy, smooth)
    return move_aim_to(sx, sy, cx, cy, smooth, false)
end

local function aim_at_screen(sx, sy, cx, cy, smooth, lmb_kd, lmb_clicked)
    if s.aimbot_flick then
        if not lmb_kd then
            return
        end
        move_aim_to(sx, sy, cx, cy, smooth, lmb_clicked)
        return
    end
    move_aim_to(sx, sy, cx, cy, smooth, false)
end

local function world_to_aim_screen(x, y, z)
    local sx, sy, vis = utility.world_to_screen(x, y, z)
    if not vis or not sx or not sy then
        return nil, nil
    end
    return sx, sy
end

local function locked_world_pos()
    local lt = cache.aim.locked_target
    if not lt then
        return nil
    end
    if lt.is_utility then
        local w = lt.world_obj and cache.world_lookup[lt.world_obj]
        if w then
            return {x = w.x, y = w.y, z = w.z}
        end
        return nil
    end
    for _, p in ipairs(cache.players) do
        if p.viewmodel == lt.viewmodel then
            cache.aim.locked_target = p
            return get_target_bone(p)
        end
    end
    return nil
end

local GADGET_AIM_LABELS = {
    "DRONE", "CLAYMORE", "C4", "JAMMER", "STICKY CAM", "BP CAM", "MAP CAM", "BREACH",
    "HARD BREACH", "PROX ALARM", "BARBED WIRE", "SHIELD",
    "THERMITE", "SHOCK BAT", "INC CANISTER", "NEEDLE MINE", "TOXIC",
}

local function build_aim_blacklist()
    local bl_opts = s.gadget_aim_blacklist or {}
    local aim_blacklist = {}
    for i, enabled in ipairs(bl_opts) do
        if enabled and GADGET_AIM_LABELS[i] then
            aim_blacklist[GADGET_AIM_LABELS[i]] = true
            local base = shootable_gadgets.base_label(GADGET_AIM_LABELS[i])
            if base and base ~= GADGET_AIM_LABELS[i] then
                aim_blacklist[base] = true
            end
        end
    end
    return aim_blacklist
end

local function consider_candidate(best, bd, candidate, d, dist)
    if s.aimbot_target_type == AIM_TARGET.CROSSHAIR then
        if d < bd then
            return candidate, d
        end
        return best, bd
    end
    if not best or dist < (best.world_dist or math.huge) then
        candidate.world_dist = dist
        return candidate, bd
    end
    return best, bd
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

    local sticky_on = s.aimbot_sticky and kd
    if not sticky_on then
        cache.aim.locked_target = nil
    end

    if not kd then
        cache.aim.current_target = nil
        return
    end

    local cx, cy = screen_center()
    local fov = s.aimbot_fov or 125
    local smooth = s.aimbot_smooth or 5

    if sticky_on and cache.aim.locked_target and is_target_valid(cache.aim.locked_target) then
        local tpos = locked_world_pos()
        if tpos then
            local sx, sy = world_to_aim_screen(tpos.x, tpos.y, tpos.z)
            if sx then
                cache.aim.current_target = {
                    target = cache.aim.locked_target,
                    pos = tpos,
                    screen_x = sx,
                    screen_y = sy
                }
                aim_at_screen(sx, sy, cx, cy, smooth, lmb_kd, lmb_clicked)
                return
            end
        end
        cache.aim.locked_target = nil
    end

    local best, bd = nil, math.huge
    local max_dist = s.aimbot_max_distance or 500

    for _, p in ipairs(cache.players) do
        if p.health and p.health > 0
            and (not s.aimbot_team_check or not p.is_teammate)
            and p.dist <= max_dist
            and (not s.aimbot_vischeck or p.is_visible)
        then
            local tb = get_target_bone(p)
            if tb then
                local sx, sy = world_to_aim_screen(tb.x, tb.y, tb.z)
                if sx then
                    local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                    if d <= fov then
                        best, bd = consider_candidate(
                            best,
                            bd,
                            {target = p, pos = tb, screen_x = sx, screen_y = sy, world_dist = p.dist},
                            d,
                            p.dist
                        )
                    end
                end
            end
        end
    end

    if s.utilities_aimbot then
        local skip_gadgets = s.aimbot_players_priority and best and best.target and not best.target.is_utility
        if not skip_gadgets then
            local aim_blacklist = build_aim_blacklist()
            local util_max = s.utilities_max_distance or 75
            for _, w in ipairs(cache.world) do
                if w.dist <= util_max
                    and shootable_gadgets.is_shootable_entry(w)
                    and not aim_blacklist[w.label]
                    and not aim_blacklist[shootable_gadgets.base_label(w.label)]
                    and not (s.world_team_check and w.is_teammate_gadget)
                then
                    local sx, sy = world_to_aim_screen(w.x, w.y, w.z)
                    if sx then
                        local d = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                        if d <= fov then
                            best, bd = consider_candidate(
                                best,
                                bd,
                                {
                                    target = {is_utility = true, world_obj = w.obj},
                                    pos = {x = w.x, y = w.y, z = w.z},
                                    screen_x = sx,
                                    screen_y = sy,
                                    world_dist = w.dist
                                },
                                d,
                                w.dist
                            )
                        end
                    end
                end
            end
        end
    end

    if best then
        cache.aim.current_target = best
        if s.aimbot_sticky and not cache.aim.locked_target then
            cache.aim.locked_target = best.target
        end
        aim_at_screen(best.screen_x, best.screen_y, cx, cy, smooth, lmb_kd, lmb_clicked)
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

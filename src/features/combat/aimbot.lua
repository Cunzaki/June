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

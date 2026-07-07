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

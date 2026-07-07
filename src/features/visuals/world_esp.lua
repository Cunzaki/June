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

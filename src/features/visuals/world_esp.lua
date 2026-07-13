local settings = June.require("core.settings")
local cache = June.require("core.cache")
local draw_util = June.require("core.draw_util")
local world_scan = June.require("game.world_scan")

local floor = June.require("core.constants").floor
local DIST = June.require("core.constants").DIST
local bbox_center = draw_util.bbox_center

local M = {}
local s = settings.s
local draw_3d_box = draw_util.draw_3d_box
local dist3d_sq = draw_util.dist3d_sq

local TEXT_W_CACHE = {}
local TEXT_W_CACHE_MAX = 256

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function world_to_screen(x, y, z)
    if utility and utility.world_to_screen then
        return utility.world_to_screen(x, y, z)
    end
    if draw and draw.world_to_screen then
        return draw.world_to_screen(x, y, z)
    end
    return 0, 0, false
end

local function text_width(txt, fs)
    local key = txt .. "\0" .. tostring(fs)
    local cached = TEXT_W_CACHE[key]
    if cached then
        return cached
    end
    cached = draw.get_text_size(txt, fs)
    if cached then
        local n = 0
        for _ in pairs(TEXT_W_CACHE) do n = n + 1 end
        if n >= TEXT_W_CACHE_MAX then
            TEXT_W_CACHE = {}
        end
        TEXT_W_CACHE[key] = cached
    end
    return cached or (#txt * fs * 0.55)
end

local function label_anchor(w)
    if w.bbox then
        local c = bbox_center(w.bbox)
        if c then
            return c.x, c.y, c.z
        end
    end
    return w.x, w.y, w.z
end

local function build_label_text(w, show_text, show_dist)
    local dist_i = floor(w.dist or 0)
    if w._esp_dist_i == dist_i and w._esp_label_text then
        return w._esp_label_text
    end
    local txt = ""
    if show_text and w.label then
        txt = w.label
    end
    if show_dist then
        txt = txt .. (show_text and " [" or "[") .. dist_i .. "m]"
    end
    w._esp_dist_i = dist_i
    w._esp_label_text = txt
    return txt
end

function M.render_world()
    if not s.world_enabled then
        return
    end

    local display_opts = s.world_display_options or {false, false, false}
    local show_text = display_opts[1]
    local show_dist = display_opts[2]
    local show_box = display_opts[3]
    if not show_text and not show_dist and not show_box then
        return
    end

    local fs_world = s.font_size_world or 14
    local max_sq = (s.world_max_distance or 250) * (s.world_max_distance or 250)
    local cam_x, cam_y, cam_z = cache.cam_x, cache.cam_y, cache.cam_z
    local drawn = {}

    for i = 1, #cache.world do
        local w = cache.world[i]
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

        local dsq = w.dsq
        if not dsq then
            dsq = dist3d_sq(w.x, w.y, w.z, cam_x, cam_y, cam_z)
            w.dsq = dsq
        end
        w.dist = math.sqrt(dsq)
        if dsq > max_sq then
            goto continue
        end
        if not w.dynamic and dsq <= DIST.ESP_HIDE_SQ then
            goto continue
        end

        if show_box then
            if not w.bbox and w.obj then
                world_scan.refresh_entry_position(w, cam_x, cam_y, cam_z, math.sqrt)
            end
            if w.bbox then
                draw_3d_box(w.bbox, w.color)
            end
        end

        if show_text or show_dist then
            local lx, ly, lz = label_anchor(w)
            local sx, sy, v = world_to_screen(lx, ly, lz)
            if v then
                local txt = build_label_text(w, show_text, show_dist)
                if txt ~= "" then
                    local tw = text_width(txt, fs_world)
                    draw.text(sx - tw * 0.5, sy - fs_world - 2, txt, w.color, fs_world)
                end
            end
        end

        ::continue::
    end
end

return M

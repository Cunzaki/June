local manip_math = June.require("core.manip_math")
local combat_origin = June.require("game.combat_origin")
local settings = June.require("core.settings")
local cache = June.require("core.cache")

local M = {}

local MANIP_LABELS = {
    direct = "MANIP: CLEAR SHOT",
    ready = "MANIP: RAY READY",
    scanning = "MANIP: SCANNING",
    blocked = "MANIP: NO PEEK",
    tp = "MANIP: BULLET TP",
    off = "",
}

local function w2s(x, y, z)
    if utility and utility.world_to_screen then
        return utility.world_to_screen(x, y, z)
    end
    if draw and draw.world_to_screen then
        return draw.world_to_screen(x, y, z)
    end
    return 0, 0, false
end

local function draw_link(a, b, col, thick)
    if not a or not b then return end
    local x1, y1, v1 = w2s(a.x, a.y, a.z)
    local x2, y2, v2 = w2s(b.x, b.y, b.z)
    if v1 and v2 then
        draw.line(x1, y1, x2, y2, col, thick or 1)
    end
end

local function draw_world_line(a, b, col, thick)
    if draw and draw.line_3d then
        pcall(draw.line_3d, a.x, a.y, a.z, b.x, b.y, b.z, col, thick or 1.5)
        return
    end
    draw_link(a, b, col, thick)
end

local function draw_cross_world(x, y, z, size, col, thick)
    local sx, sy, v = w2s(x, y, z)
    if not v then return end
    draw.line(sx - size, sy, sx + size, sy, col, thick or 1)
    draw.line(sx, sy - size, sx, sy + size, col, thick or 1)
end

local function draw_labeled(x, y, z, label, col, fs)
    local sx, sy, v = w2s(x, y, z)
    if not v or not label then return end
    fs = fs or 11
    local tw = draw.get_text_size(label, fs)
    draw.text(sx - tw * 0.5, sy - fs - 2, label, col, fs)
end

function M.draw_extend_bar(cx, cy, fov, info)
    local s = settings.s
    if not s.silent_manip_extend then return end
    if not info then return end
    if info.state ~= "scanning" and info.state ~= "ready" and info.state ~= "direct" then return end

    local has_target = info.state == "ready" or info.state == "direct"
    local prog = has_target and 1 or math.max(0, math.min(1, info.scan_progress or 0))

    local bar_w, bar_h = 120, 6
    local x = cx - bar_w * 0.5
    local y = cy + fov + 8
    local fill_w = bar_w * prog
    local fill_col = has_target and {0.2, 0.95, 0.35, 0.95} or {1 - prog, prog, 0.15, 0.95}
    local bg_col = {0.08, 0.08, 0.1, 0.85}
    local border_col = has_target and {0.2, 0.95, 0.35, 0.55} or {0.95, 0.2, 0.2, 0.5}

    draw.rect_filled(x, y, bar_w, bar_h, bg_col)
    if fill_w > 0.5 then
        draw.rect_filled(x, y, fill_w, bar_h, fill_col)
    end
    draw.rect(x, y, bar_w, bar_h, border_col, 1)
end

function M.draw_manip_status(cx, cy, fov, info)
    if not settings.s.silent_manip_status then return end
    if not info or info.state == "off" then return end

    local ready = info.state == "ready" or info.state == "direct" or info.state == "tp"
    local text = MANIP_LABELS[info.state] or ("MANIP: " .. tostring(info.state))
    local col = ready and {0.2, 0.95, 0.35, 1} or (
        info.state == "scanning" and {1, 0.65, 0.15, 1} or {0.95, 0.25, 0.25, 1}
    )

    local fs = 11
    local tw = draw.get_text_size(text, fs)
    local pad_x, pad_y = 10, 4
    local w = tw + pad_x * 2
    local h = 18
    local x = cx - w * 0.5
    local y = cy + fov + (settings.s.silent_manip_extend and 22 or 10)

    draw.rect_filled(x, y, w, h, {0.08, 0.08, 0.1, 0.9})
    draw.rect(x, y, w, h, {col[1], col[2], col[3], 0.45}, 1)
    draw.rect_filled(x, y, 2, h, {col[1], col[2], col[3], 0.85})
    draw.text(x + pad_x, y + pad_y, text, col, fs)
end

function M.draw_manip_peek(info)
    if not settings.s.silent_manip_peek_vis then return end
    if not info or not info.peek then return end
    if info.state ~= "ready" then return end

    local body = combat_origin.get_server_origin()
    if not body then return end

    local peek = info.peek
    local col_peek = {1, 0.85, 0.2, 0.95}
    local show_labels = settings.s.silent_manip_status == true
    local eye_y = peek.y + manip_math.eye_offset_y()

    draw_cross_world(peek.x, eye_y, peek.z, 6, col_peek, 2)
    if show_labels then
        draw_labeled(peek.x, eye_y, peek.z, "PEEK", col_peek, 11)
    end

    local ray_from = info.origin or manip_math.peek_track_origin(peek)
    if ray_from and info.aim then
        draw_world_line(ray_from, info.aim, {1, 0.45, 0.2, 0.55}, 1.5)
        draw_cross_world(ray_from.x, ray_from.y, ray_from.z, 5, {1, 0.85, 0.2, 0.95}, 2)
    end
end

function M.draw_tp_ray_path(info)
    if not settings.s.silent_tp_ray_vis then return end
    if not info then return end
    if info.state ~= "tp" and info.state ~= "ready" then return end
    if info.state == "tp" and not settings.s.silent_bullet_tp then return end
    if info.state == "ready" and not settings.s.silent_bullet_manip then return end

    local path = info.tp_path
    if not path or #path < 2 then return end

    local col = {0.95, 0.45, 1, 0.9}
    local start_i = 1
    if #path >= 3 then
        start_i = 2
    end
    for i = start_i, #path - 1 do
        draw_world_line(path[i], path[i + 1], col, 1.5)
    end

    local hook = info.origin or path[start_i]
    local aim = info.hitpart or info.aim
    if hook and aim then
        draw_cross_world(hook.x, hook.y, hook.z, 5, {1, 0.85, 0.2, 0.95}, 2)
    end
end

function M.draw_all(info)
    if not info or info.state == "off" then return end

    local cx = cache.screen_w * 0.5
    local cy = cache.screen_h * 0.5
    local fov = settings.s.silent_fov or 150

    if settings.s.silent_bullet_manip then
        M.draw_extend_bar(cx, cy, fov, info)
        M.draw_manip_status(cx, cy, fov, info)
        M.draw_manip_peek(info)
    end

    M.draw_tp_ray_path(info)
end

return M

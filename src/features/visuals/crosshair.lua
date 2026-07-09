local settings = June.require("core.settings")
local cache = June.require("core.cache")

local M = {}
local s = settings.s

local function draw_crosshair()
    if not s.crosshair_enabled then return end
    local cx, cy = cache.screen_w / 2, cache.screen_h / 2
    local col = s.crosshair_enabled_color
    local sz  = s.crosshair_size  or 8
    local gap = s.crosshair_gap   or 3
    local csty = s.crosshair_style or 0
    if csty == 0 then
        draw.line(cx - sz - gap, cy, cx - gap, cy, col, 1.5)
        draw.line(cx + gap, cy, cx + sz + gap, cy, col, 1.5)
        draw.line(cx, cy - sz - gap, cx, cy - gap, col, 1.5)
        draw.line(cx, cy + gap, cx, cy + sz + gap, col, 1.5)
    elseif csty == 1 then
        draw.circle_filled(cx, cy, sz * 0.4, col)
    elseif csty == 2 then
        draw.circle(cx, cy, sz + gap, col, 48, 1.5)
    elseif csty == 3 then
        draw.line(cx - sz, cy, cx + sz, cy, col, 1.5)
        draw.line(cx, cy - sz, cx, cy + sz, col, 1.5)
    end
end

M.draw_crosshair = draw_crosshair

return M

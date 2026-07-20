-- Clean Neverlose-style monoline sidebar icons.
local theme = June.require("ui.gs_theme")

local M = {}

local function line(x1, y1, x2, y2, col, t)
    if draw and draw.line then
        draw.line(x1, y1, x2, y2, col, t or 1.8)
    end
end

local function circle(x, y, r, col, filled, segs)
    if not draw then return end
    segs = segs or 22
    if filled and draw.circle_filled then
        draw.circle_filled(x, y, r, col, segs)
    elseif draw.circle then
        draw.circle(x, y, r, col, segs, 1.8)
    end
end

local function rect(x, y, w, h, col, filled, round)
    if not draw then return end
    if filled then
        draw.rect_filled(x, y, w, h, col, round or 0)
    else
        draw.rect(x, y, w, h, col, round or 0, 1.6)
    end
end

function M.draw(name, cx, cy, col)
    col = col or theme.TEXT
    local t = 1.85

    if name == "aim" then
        -- Compact crosshair (Neverlose-like)
        circle(cx, cy, 6.2, col, false, 24)
        circle(cx, cy, 1.35, col, true, 10)
        line(cx - 10, cy, cx - 5.2, cy, col, t)
        line(cx + 5.2, cy, cx + 10, cy, col, t)
        line(cx, cy - 10, cx, cy - 5.2, col, t)
        line(cx, cy + 5.2, cx, cy + 10, col, t)

    elseif name == "visuals" then
        -- Eye with pupil
        circle(cx, cy, 3.2, col, false, 16)
        circle(cx + 0.7, cy - 0.5, 1.15, col, true, 10)
        -- lids as gentle arcs via short polylines
        local top, bot = {}, {}
        for i = 0, 10 do
            local a = -math.pi + (math.pi * i / 10)
            top[#top + 1] = { cx + math.cos(a) * 8.2, cy + math.sin(a) * 4.0 }
            bot[#bot + 1] = { cx + math.cos(a) * 8.2, cy - math.sin(a) * 4.0 }
        end
        if draw and draw.poly then
            draw.poly(top, col, t)
            draw.poly(bot, col, t)
        else
            for i = 1, #top - 1 do
                line(top[i][1], top[i][2], top[i + 1][1], top[i + 1][2], col, t)
                line(bot[i][1], bot[i][2], bot[i + 1][1], bot[i + 1][2], col, t)
            end
        end

    elseif name == "world" then
        -- Globe
        circle(cx, cy, 7.2, col, false, 26)
        -- equator
        local eq = {}
        for i = 0, 16 do
            local a = (i / 16) * math.pi * 2
            eq[#eq + 1] = { cx + math.cos(a) * 7.2, cy + math.sin(a) * 2.6 }
        end
        if draw and draw.poly then
            draw.poly(eq, col, 1.55)
        end
        -- meridian
        local mer = {}
        for i = 0, 16 do
            local a = (i / 16) * math.pi * 2
            mer[#mer + 1] = { cx + math.sin(a) * 2.6, cy + math.cos(a) * 7.2 }
        end
        if draw and draw.poly then
            draw.poly(mer, col, 1.55)
        else
            line(cx, cy - 7.2, cx, cy + 7.2, col, 1.5)
        end

    elseif name == "misc" then
        -- Three horizontal sliders (settings)
        for i = 0, 2 do
            local yy = cy - 6.5 + i * 6.5
            line(cx - 8, yy, cx + 8, yy, col, 1.55)
            local knob = ({ -3.5, 3.2, -0.5 })[i + 1]
            circle(cx + knob, yy, 2.35, col, true, 12)
        end

    elseif name == "config" then
        -- Clean gear
        local teeth = 8
        for i = 0, teeth - 1 do
            local a = (i / teeth) * math.pi * 2 + 0.2
            local c, s = math.cos(a), math.sin(a)
            local x1, y1 = cx + c * 3.4, cy + s * 3.4
            local x2, y2 = cx + c * 7.4, cy + s * 7.4
            local px, py = -s * 1.35, c * 1.35
            if draw and draw.poly then
                draw.poly({
                    { x1 + px, y1 + py },
                    { x2 + px * 0.65, y2 + py * 0.65 },
                    { x2 - px * 0.65, y2 - py * 0.65 },
                    { x1 - px, y1 - py },
                }, col, 1.45)
            else
                line(x1, y1, x2, y2, col, 1.6)
            end
        end
        circle(cx, cy, 3.6, col, false, 18)
        circle(cx, cy, 1.55, col, true, 10)

    else
        circle(cx, cy, 4, col, false)
    end
end

return M

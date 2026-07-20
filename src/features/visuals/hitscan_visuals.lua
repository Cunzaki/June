local settings = June.require("core.settings")

local M = {}

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

local function draw_marker(pos, col, size)
    if not pos then return end
    local sx, sy, v = w2s(pos.x, pos.y, pos.z)
    if not v then return end
    local r = size or 5
    draw.line(sx - r, sy, sx + r, sy, col, 2)
    draw.line(sx, sy - r, sx, sy + r, col, 2)
end

function M.draw(info)
    if not settings.s.silent_hitscan_vis then return end
    if not info or (info.state ~= "hitscan" and info.state ~= "silent") then return end

    local path = info.path
    if not path or #path < 2 then return end

    local line_col = info.state == "hitscan"
        and {0.95, 0.45, 1, 0.9}
        or {0.45, 0.75, 1, 0.85}
    local hook_col = {1, 0.85, 0.2, 0.95}
    local target_col = {0.4, 1, 0.5, 0.9}

    local start_i = #path >= 3 and 2 or 1
    for i = start_i, #path - 1 do
        draw_link(path[i], path[i + 1], line_col, 1.5)
    end

    if #path >= 3 then
        draw_link(path[1], path[2], {line_col[1], line_col[2], line_col[3], 0.55}, 1)
    end

    local hook = info.origin or path[start_i]
    draw_marker(hook, hook_col, 5)

    local target = path[#path]
    draw_marker(target, target_col, 5)
end

return M

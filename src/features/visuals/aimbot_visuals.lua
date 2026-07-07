local constants = June.require("core.constants")
local settings = June.require("core.settings")
local cache = June.require("core.cache")

local FOV_STYLE = constants.FOV_STYLE
local TARGET_LINE_STYLE = constants.TARGET_LINE_STYLE

local M = {}
local s = settings.s

local function render_aimbot_visuals()
    if not s.aimbot_enabled then
        return
    end
    if s.aimbot_fov_visible then
        local cx, cy, fov, col = cache.screen_w / 2, cache.screen_h / 2, s.aimbot_fov, s.aimbot_fov_visible_color
        local fov_style = s.aimbot_fov_style or 0
        -- Independent fill layer (drawn before the outline so outline sits on top)
        if s.aimbot_fov_fill then
            local fc = s.aimbot_fov_fill_color or {col[1], col[2], col[3], 0.08}
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
    if s.aimbot_target_line and cache.aim.current_target then
        local cx, cy, t = cache.screen_w / 2, cache.screen_h / 2, cache.aim.current_target
        local col = s.aimbot_target_line_color
        if s.target_line_style == TARGET_LINE_STYLE.SOLID then
            draw.line(cx, cy, t.screen_x, t.screen_y, col, 2)
        elseif s.target_line_style == TARGET_LINE_STYLE.DASHED then
            for i = 0, 9 do
                local t1, t2 = i / 10, (i + 0.5) / 10
                draw.line(
                    cx + (t.screen_x - cx) * t1,
                    cy + (t.screen_y - cy) * t1,
                    cx + (t.screen_x - cx) * t2,
                    cy + (t.screen_y - cy) * t2,
                    col,
                    2
                )
            end
        elseif s.target_line_style == TARGET_LINE_STYLE.DOTTED then
            for i = 0, 19 do
                draw.circle_filled(cx + (t.screen_x - cx) * (i / 20), cy + (t.screen_y - cy) * (i / 20), 2, col)
            end
        end
        local endpoint_style = s.target_line_endpoint or 0
        if endpoint_style == 0 then
            draw.circle_filled(t.screen_x, t.screen_y, 5, col)
        elseif endpoint_style == 1 then
            draw.circle(t.screen_x, t.screen_y, 5, col, 32, 2)
        elseif endpoint_style == 2 then
            draw.circle_filled(t.screen_x, t.screen_y, 2, col)
        elseif endpoint_style == 3 then
            draw.rect_filled(t.screen_x - 4, t.screen_y - 4, 8, 8, col)
        elseif endpoint_style == 4 then
            draw.line(t.screen_x - 5, t.screen_y - 5, t.screen_x + 5, t.screen_y + 5, col, 2)
            draw.line(t.screen_x + 5, t.screen_y - 5, t.screen_x - 5, t.screen_y + 5, col, 2)
        end
    end
end

M.render_aimbot_visuals = render_aimbot_visuals

return M

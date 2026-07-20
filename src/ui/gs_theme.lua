-- Neverlose-inspired palette for the draw-only June UI.
local M = {}

M.BG = { 0.039, 0.043, 0.051, 0.99 }
M.BG_INNER = { 0.051, 0.055, 0.067, 1 }
M.PANEL = { 0.067, 0.071, 0.086, 0.99 }
M.PANEL_ALT = { 0.078, 0.084, 0.102, 1 }
M.PANEL_RAISED = { 0.094, 0.102, 0.125, 1 }
M.OVERLAY = { 0.067, 0.071, 0.090, 0.995 }
M.SHADOW = { 0, 0, 0, 0.40 }
M.BORDER = { 0.145, 0.165, 0.205, 1 }
M.BORDER_SOFT = { 0.110, 0.125, 0.155, 1 }
M.BORDER_HOT = { 0.22, 0.42, 0.72, 1 }
M.SIDEBAR = { 0.047, 0.051, 0.063, 1 }
M.SIDEBAR_ACTIVE = { 0.090, 0.145, 0.230, 1 }

M.TEXT = { 0.78, 0.80, 0.86, 1 }
M.TEXT_DIM = { 0.42, 0.46, 0.54, 1 }
M.TEXT_ACTIVE = { 0.96, 0.97, 1.0, 1 }
M.TEXT_TITLE = { 0.70, 0.74, 0.82, 1 }
M.TEXT_SECTION = { 0.38, 0.42, 0.50, 1 }

-- Neverlose sky / royal blue accent
M.ACCENT = { 0.294, 0.549, 0.957, 1 }
M.ACCENT_DIM = { 0.16, 0.30, 0.52, 1 }
M.CHECK_OFF = { 0.14, 0.155, 0.19, 1 }
M.SLIDER_BG = { 0.12, 0.135, 0.165, 1 }
M.BUTTON = { 0.105, 0.115, 0.145, 1 }
M.BUTTON_HOVER = { 0.145, 0.175, 0.230, 1 }
M.HOVER = { 0.12, 0.16, 0.22, 0.85 }
M.FOCUS = { 0.294, 0.549, 0.957, 0.72 }

M.RAINBOW = {
    { 0.294, 0.549, 0.957, 1 },
    { 0.35, 0.75, 0.95, 1 },
    { 0.55, 0.45, 0.95, 1 },
    { 0.95, 0.45, 0.55, 1 },
    { 0.35, 0.90, 0.55, 1 },
}

M.FONT = 13
M.FONT_SMALL = 12
M.FONT_TITLE = 13
M.FONT_CAPTION = 11
M.FONT_BRAND = 16
M.FONT_SECTION = 11

M.WINDOW_W = 900
M.WINDOW_H = 580
M.SIDEBAR_W = 178
M.TAB_H = 34
M.SECTION_GAP = 14
M.SECTION_LABEL_H = 18
M.BRAND_H = 48
M.GROUP_PAD = 12
M.GROUP_GAP = 12
M.GROUP_HEADER_H = 28
M.ROW_H = 28
M.ITEM_GAP = 8
M.LABEL_H = 16
M.LABEL_GAP = 8
M.CTRL_H = 20
M.CTRL_PAD = 4
M.CHECK_SIZE = 13
M.TOGGLE_W = 34
M.TOGGLE_H = 18
M.SLIDER_H = 4
M.STACKED_ROW_H = M.LABEL_H + M.LABEL_GAP + M.CTRL_H + M.CTRL_PAD
M.SLIDER_ROW_H = M.LABEL_H + M.LABEL_GAP + M.SLIDER_H + 12 + M.CTRL_PAD
M.CORNER = 6
M.CORNER_SMALL = 4
M.CORNER_PILL = 9

function M.alpha(col, a)
    return { col[1], col[2], col[3], a }
end

function M.lerp_color(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        a[4] + (b[4] - a[4]) * t,
    }
end

function M.rainbow_at(t)
    local n = #M.RAINBOW
    local x = (t % 1) * n
    local i = math.floor(x) + 1
    local j = (i % n) + 1
    local f = x - math.floor(x)
    return M.lerp_color(M.RAINBOW[i], M.RAINBOW[j], f)
end

return M

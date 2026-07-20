-- Animated accent bars + per-element theme sync for the custom UI.
local theme = June.require("ui.gs_theme")

local M = {}

M.MODES = { "Static", "Rainbow", "Pulse", "Wave", "Flow" }
M.MODES_UI = { "Default", "Static", "Rainbow", "Pulse", "Wave", "Flow" }

M.TARGET_TITLE = 1
M.TARGET_SECTION = 2
M.TARGET_SLIDER = 3
M.TARGET_SCROLL = 4
M.TARGET_SIDEBAR = 5
M.TARGET_CHECKBOX = 6
M.TARGET_HOVER = 7
M.TARGET_OVERLAY = 8

M.STYLE_TITLE = "june_ui_style_title"
M.STYLE_SECTION = "june_ui_style_section"
M.STYLE_SLIDER = "june_ui_style_slider"
M.STYLE_SCROLL = "june_ui_style_scroll"
M.STYLE_SIDEBAR = "june_ui_style_sidebar"
M.STYLE_CHECKBOX = "june_ui_style_checkbox"
M.STYLE_OVERLAY = "june_ui_style_overlay"

M.COL_TITLE = "june_ui_col_title"
M.COL_SECTION = "june_ui_col_section"
M.COL_SLIDER = "june_ui_col_slider"
M.COL_SCROLL = "june_ui_col_scroll"
M.COL_SIDEBAR = "june_ui_col_sidebar"
M.COL_CHECKBOX = "june_ui_col_checkbox"
M.COL_OVERLAY = "june_ui_col_overlay"

local DEFAULT_ACCENT = { 0.294, 0.549, 0.957, 1 }
local transitions = {}

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

function M.lerp(a, b, t)
    t = clamp(t or 0, 0, 1)
    return a + (b - a) * t
end

function M.ease_out_cubic(t)
    t = clamp(t or 0, 0, 1)
    local q = 1 - t
    return 1 - q * q * q
end

-- Persistent transition value for hover/active UI elements.
function M.transition(id, target, rate)
    local now = M.now()
    local entry = transitions[id]
    if not entry then
        entry = { value = target and 1 or 0, at = now }
        transitions[id] = entry
        return entry.value
    end
    local dt = math.min(math.max(now - (entry.at or now), 0), 0.1)
    entry.at = now
    local goal = target and 1 or 0
    local speed = rate or 12
    local alpha = 1 - math.exp(-speed * dt)
    entry.value = M.lerp(entry.value or 0, goal, alpha)
    return entry.value
end

function M.mix(a, b, t)
    return theme.lerp_color(a, b, clamp(t or 0, 0, 1))
end

local function settings()
    return June.require("core.settings")
end

local function hsv_to_rgb(h, s, v)
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

function M.now()
    if utility and utility.get_time then
        return utility.get_time()
    end
    return 0
end

function M.speed()
    local n = settings().num("june_ui_anim_speed", 40)
    return clamp(n, 1, 100) * 0.028
end

function M.phase()
    return M.now() * M.speed()
end

function M.colors_enabled()
    return settings().bool("june_ui_custom_colors", false)
end

function M.anim_enabled()
    return settings().bool("june_ui_custom_anim", false)
end

function M.global_mode()
    local n = tonumber(settings().get("june_ui_accent_anim", 1)) or 1
    return clamp(math.floor(n + 0.5), 0, #M.MODES - 1)
end

function M.resolve_mode(style_id)
    if not M.anim_enabled() then
        return 0
    end
    local pick = settings().combo_index(style_id, M.MODES_UI, 0)
    if pick == 0 then
        return M.global_mode()
    end
    return pick - 1
end

function M.base_accent()
    if not M.colors_enabled() then
        return DEFAULT_ACCENT
    end
    return settings().color("june_ui_accent", DEFAULT_ACCENT)
end

function M.color_override_enabled(target_index)
    if not M.colors_enabled() then
        return false
    end
    return settings().multi("june_ui_color_overrides", target_index, false)
end

function M.element_color(target_index, color_id)
    if M.color_override_enabled(target_index) then
        return settings().color(color_id, M.base_accent())
    end
    return M.base_accent()
end

function M.anim_target_enabled(target_index)
    if not M.anim_enabled() then
        return false
    end
    return settings().multi("june_ui_anim_targets", target_index, true)
end

function M.sync_theme()
    local col = M.base_accent()
    theme.ACCENT = { col[1], col[2], col[3], col[4] or 1 }
    local pulse = 0.62 + 0.38 * math.sin(M.phase() * 2.2)
    theme.ACCENT_DIM = {
        col[1] * pulse * 0.55,
        col[2] * pulse * 0.55,
        col[3] * pulse * 0.55,
        1,
    }
end

function M.accent_at_mode(mode, base, t, alpha)
    alpha = alpha or 1
    local phase = M.phase()
    t = (t or 0) % 1

    if mode == 0 then
        return { base[1], base[2], base[3], alpha }
    end
    if mode == 1 then
        local hue = (t + phase * 0.14) % 1
        local r, g, b = hsv_to_rgb(hue, 1, 1)
        return { r, g, b, alpha }
    end
    if mode == 2 then
        local p = 0.5 + 0.5 * math.sin(phase * 2.4 + t * 6.28318)
        return { base[1] * p, base[2] * p, base[3] * p, alpha }
    end
    if mode == 3 then
        local w = 0.45 + 0.55 * math.sin((t * 10 - phase * 2.8) * 6.28318)
        return {
            base[1] * (0.55 + 0.45 * w),
            base[2] * (0.55 + 0.45 * w),
            base[3] * (0.55 + 0.45 * w),
            alpha,
        }
    end
    local sweep_h = (t + phase * 0.18) % 1
    local sr, sg, sb = hsv_to_rgb(sweep_h, 1, 1)
    local mix = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 6.28318 + phase * 1.6))
    local c = theme.lerp_color(base, { sr, sg, sb, 1 }, mix)
    return { c[1], c[2], c[3], alpha }
end

function M.accent_at(t, alpha)
    return M.accent_at_mode(M.global_mode(), M.base_accent(), t, alpha)
end

local function widget_clip()
    local clip = nil
    pcall(function()
        clip = June.require("ui.gs_widgets").clip
    end)
    return clip
end

function M.rect(x, y, w, h, col, filled)
    if not draw then return end
    local c = widget_clip()
    if c then
        local x2, y2 = x + w, y + h
        local cx, cy = c.x, c.y
        local cx2, cy2 = c.x + c.w, c.y + c.h
        if x2 <= cx or y2 <= cy or x >= cx2 or y >= cy2 then return end
        if x < cx then w = w - (cx - x); x = cx end
        if y < cy then h = h - (cy - y); y = cy end
        if x + w > cx2 then w = cx2 - x end
        if y + h > cy2 then h = cy2 - y end
        if w <= 0 or h <= 0 then return end
    end
    if filled then
        draw.rect_filled(x, y, w, h, col, 0)
    else
        draw.rect(x, y, w, h, col, 0, 1)
    end
end

function M.draw_bar_h(x, y, w, h, scroll_t, style_id, color_id, color_target)
    if w <= 0 or h <= 0 then return end
    scroll_t = scroll_t or 0
    local base = M.element_color(color_target, color_id)
    local mode = M.resolve_mode(style_id)
    if mode == 0 then
        M.rect(x, y, w, h, base, true)
        return
    end
    local segs = math.max(16, math.floor(w / 4))
    local sw = w / segs
    for i = 0, segs - 1 do
        local t = (i / segs + scroll_t) % 1
        M.rect(x + i * sw, y, sw + 0.75, h, M.accent_at_mode(mode, base, t, 1), true)
    end
end

function M.draw_bar_v(x, y, w, h, scroll_t, style_id, color_id, color_target)
    if w <= 0 or h <= 0 then return end
    scroll_t = scroll_t or 0
    local base = M.element_color(color_target, color_id)
    local mode = M.resolve_mode(style_id)
    if mode == 0 then
        M.rect(x, y, w, h, base, true)
        return
    end
    local segs = math.max(8, math.floor(h / 4))
    local sh = h / segs
    for i = 0, segs - 1 do
        local t = (i / segs + scroll_t) % 1
        M.rect(x, y + i * sh, w, sh + 0.75, M.accent_at_mode(mode, base, t, 1), true)
    end
end

function M.draw_flat(x, y, w, h, style_id, color_id, color_target)
    local base = M.element_color(color_target, color_id)
    M.rect(x, y, w, h, base, true)
end

function M.section_scroll()
    return M.phase() * 0.09
end

function M.draw_section_top(x, y, w)
    if not M.anim_target_enabled(M.TARGET_SECTION) then
        M.draw_flat(x, y, w, 2, M.STYLE_SECTION, M.COL_SECTION, M.TARGET_SECTION)
        return
    end
    M.draw_bar_h(x, y, w, 2, M.section_scroll(), M.STYLE_SECTION, M.COL_SECTION, M.TARGET_SECTION)
end

function M.draw_title_bar(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_TITLE) then
        M.draw_flat(x, y, w, h, M.STYLE_TITLE, M.COL_TITLE, M.TARGET_TITLE)
        return
    end
    M.draw_bar_h(x, y, w, h, M.phase() * 0.12, M.STYLE_TITLE, M.COL_TITLE, M.TARGET_TITLE)
end

function M.draw_slider_fill(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_SLIDER) then
        M.draw_flat(x, y, w, h, M.STYLE_SLIDER, M.COL_SLIDER, M.TARGET_SLIDER)
        return
    end
    M.draw_bar_h(x, y, w, h, M.phase() * 0.06, M.STYLE_SLIDER, M.COL_SLIDER, M.TARGET_SLIDER)
end

function M.draw_scroll_thumb(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_SCROLL) then
        M.draw_flat(x, y, w, h, M.STYLE_SCROLL, M.COL_SCROLL, M.TARGET_SCROLL)
        return
    end
    M.draw_bar_v(x, y, w, h, M.phase() * 0.05, M.STYLE_SCROLL, M.COL_SCROLL, M.TARGET_SCROLL)
end

function M.draw_tab_indicator(x, y, w, h)
    if not M.anim_target_enabled(M.TARGET_SIDEBAR) then
        M.draw_flat(x, y, w, h, M.STYLE_SIDEBAR, M.COL_SIDEBAR, M.TARGET_SIDEBAR)
        return
    end
    M.draw_bar_v(x, y, w, h, M.phase() * 0.07, M.STYLE_SIDEBAR, M.COL_SIDEBAR, M.TARGET_SIDEBAR)
end

function M.tab_icon_color()
    local base = M.element_color(M.TARGET_SIDEBAR, M.COL_SIDEBAR)
    if not M.anim_target_enabled(M.TARGET_SIDEBAR) then
        return base
    end
    return M.accent_at_mode(M.resolve_mode(M.STYLE_SIDEBAR), base, M.phase() * 0.03, 1)
end

function M.hover_tint(base, hot)
    if not hot then return base end
    if not M.anim_target_enabled(M.TARGET_HOVER) then
        return base
    end
    local pulse = 0.88 + 0.12 * math.sin(M.phase() * 6)
    return {
        base[1] * pulse,
        base[2] * pulse,
        base[3] * pulse,
        base[4] or 1,
    }
end

function M.interactive_fill(id, base, hover, active)
    local h = M.transition("hover:" .. tostring(id), hover, 15)
    local a = M.transition("active:" .. tostring(id), active, 20)
    local col = M.mix(base, hover and theme.BUTTON_HOVER or theme.HOVER, M.ease_out_cubic(h))
    return M.mix(col, M.element_color(M.TARGET_CHECKBOX, M.COL_CHECKBOX), a * 0.16)
end

function M.checkbox_fill()
    local base = M.element_color(M.TARGET_CHECKBOX, M.COL_CHECKBOX)
    if not M.anim_target_enabled(M.TARGET_CHECKBOX) then
        return base
    end
    return M.accent_at_mode(M.resolve_mode(M.STYLE_CHECKBOX), base, M.phase() * 0.04, 1)
end

function M.menu_fade()
    if not M.colors_enabled() or not settings().bool("june_ui_menu_fade", false) then
        return 1
    end
    return clamp(0.86 + math.sin(M.now() * 0.001) * 0.02, 0.86, 1)
end

function M.panel_bg()
    if not M.colors_enabled() then
        return theme.BG
    end
    local dim = settings().num("june_ui_bg_dim", 0)
    dim = clamp(dim, 0, 40) * 0.01
    local bg = theme.BG
    return {
        bg[1] - dim * 0.04,
        bg[2] - dim * 0.04,
        bg[3] - dim * 0.04,
        bg[4] or 1,
    }
end

return M

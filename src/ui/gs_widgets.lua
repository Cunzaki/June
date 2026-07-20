-- Gamesense-style widgets (draw API) backed by ui.gs_state.
local theme = June.require("ui.gs_theme")
local input = June.require("ui.gs_input")
local state = June.require("ui.gs_state")
local anim = June.require("ui.gs_anim")

local M = {}

M.active_slider = nil
M.active_input = nil
M.open_combo = nil
M.open_multi = nil
M.open_color = nil
M.listening_key = nil
M.drag_offset_x = 0
M.drag_offset_y = 0
M.dragging_window = false
M.clip = nil -- { x, y, w, h }
M.popup_used_click = false -- set when a popup consumes this frame's click
M.interacted = false -- any widget captured LMB this frame
M._hue_cache = {} -- id -> hue 0..1 for color picker
M._list_scroll = {} -- id -> first visible option index (0-based)
M.LIST_MAX_VISIBLE = 8
M.wheel_consumed = false -- set when a dropdown/list eats the wheel this frame
M.block_under = false -- true while pointer is over a floating popup (prior frame rect)
-- Floating color picker (drawn after the menu so it doesn't expand sections)
M._color_anchor = nil -- { id, x, y, w }
M._color_hit = nil -- { x, y, w, h } last drawn picker rect
M.open_bind_mode = nil -- keybind id whose Always/Hold/Toggle menu is open
M._bind_mode_anchor = nil -- { id, x, y, w }
M._bind_mode_hit = nil
M._active_input_rect = nil -- { x, y, w, h } for click-outside blur
M._input_repeat_at = 0
M._input_repeat_vk = nil

local LISTEN_SKIP = {
    [0x01] = true, -- LMB used for UI
}

local function listen_skip_vk(vk)
    if LISTEN_SKIP[vk] then return true end
    local menu_vk = state.get_key("june_ui_menu_key")
    if not menu_vk or menu_vk == 0 then menu_vk = 0x2D end
    return vk == menu_vk
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function text_w(str, size)
    if draw and draw.get_text_size then
        local w = draw.get_text_size(str, size or theme.FONT)
        if type(w) == "number" then return w end
    end
    return #(tostring(str or "")) * 7
end

local function in_clip(y, h)
    local c = M.clip
    if not c then return true end
    return y >= c.y and y + h <= c.y + c.h
end

local function stacked_metrics(y)
    local label_y = y + 3
    local ctrl_y = y + theme.LABEL_H + theme.LABEL_GAP
    return label_y, ctrl_y, theme.CTRL_H, theme.STACKED_ROW_H
end

local function interactive(x, y, w, h)
    if M.block_under then return false end
    if not in_clip(y, h) then return false end
    local c = M.clip
    if c and not input.hover(c.x, c.y, c.w, c.h) then
        return false
    end
    return true
end

local function ui_clicked(x, y, w, h)
    if M.block_under then return false end
    return input.clicked(x, y, w, h)
end

local function ui_rmb_clicked(x, y, w, h)
    if M.block_under then return false end
    return input.rmb_click and input.hover(x, y, w, h)
end

local function rgb_to_hsv(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local d = max - min
    local h = 0
    if d > 1e-6 then
        if max == r then
            h = ((g - b) / d) % 6
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
        if h < 0 then h = h + 1 end
    end
    local s = max <= 1e-6 and 0 or (d / max)
    return h, s, max
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

function M.begin_popups()
    M.popup_used_click = false
    M.interacted = false
    M.wheel_consumed = false
    M._color_anchor = nil
    M._bind_mode_anchor = nil
    M._active_input_rect = nil

    -- Block underlay widgets when the cursor is over last frame's popup rect
    M.block_under = false
    if M.open_color and M._color_hit then
        local r = M._color_hit
        if input.hover(r.x, r.y, r.w, r.h) then
            M.block_under = true
            if input.lmb or input.lmb_click or input.rmb or input.rmb_click then
                M.interacted = true
                M.popup_used_click = true
            end
        end
    end
    if M.open_bind_mode and M._bind_mode_hit then
        local r = M._bind_mode_hit
        if input.hover(r.x, r.y, r.w, r.h) then
            M.block_under = true
            if input.lmb or input.lmb_click or input.rmb or input.rmb_click then
                M.interacted = true
                M.popup_used_click = true
            end
        end
    end
end

local function mark_interacted()
    M.interacted = true
    M.popup_used_click = true
end

local function open_color_popup(id, anchor_x, anchor_y, row_w)
    if M.open_color == id then
        M.open_color = nil
        M._color_anchor = nil
        M._color_hit = nil
    else
        M.open_color = id
        M.open_combo = nil
        M.open_multi = nil
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M._color_anchor = { id = id, x = anchor_x, y = anchor_y, w = row_w or 160 }
    end
end

local function open_bind_mode_popup(id, anchor_x, anchor_y, chip_w)
    if M.open_bind_mode == id then
        M.open_bind_mode = nil
        M._bind_mode_anchor = nil
        M._bind_mode_hit = nil
    else
        M.open_bind_mode = id
        M.open_combo = nil
        M.open_multi = nil
        M.open_color = nil
        M._color_hit = nil
        M._bind_mode_anchor = { id = id, x = anchor_x, y = anchor_y, w = chip_w or 56 }
    end
end

local function list_scroll_for(id, count, max_vis)
    max_vis = max_vis or M.LIST_MAX_VISIBLE
    local max_off = math.max(0, count - max_vis)
    local off = M._list_scroll[id] or 0
    if off < 0 then off = 0 end
    if off > max_off then off = max_off end
    M._list_scroll[id] = off
    return off, max_off, math.min(count, max_vis)
end

local LIST_SCROLL_EDGE = 22

local function apply_list_edge_scroll(id, count, max_vis, list_x, list_y, list_w, list_h)
    max_vis = max_vis or M.LIST_MAX_VISIBLE
    local max_off = math.max(0, count - max_vis)
    if max_off <= 0 then return end
    if not input.hover(list_x, list_y, list_w, list_h) then return end

    local off = M._list_scroll[id] or 0
    if input.wheel ~= 0 and not M.wheel_consumed then
        off = off - input.wheel
        M.wheel_consumed = true
    elseif input.my < list_y + LIST_SCROLL_EDGE then
        off = off - 1
    elseif input.my > list_y + list_h - LIST_SCROLL_EDGE then
        off = off + 1
    end
    if off < 0 then off = 0 end
    if off > max_off then off = max_off end
    M._list_scroll[id] = off
end

function M.end_popups()
    if input.lmb_click and M.active_input and M._active_input_rect then
        local r = M._active_input_rect
        if not input.hover(r.x, r.y, r.w, r.h) then
            M.active_input = nil
        end
    end

    if (input.lmb_click or input.rmb_click) and not M.popup_used_click then
        if M.open_combo or M.open_multi or M.open_color or M.open_bind_mode then
            M.open_combo = nil
            M.open_multi = nil
            M.open_color = nil
            M.open_bind_mode = nil
            M._color_anchor = nil
            M._color_hit = nil
            M._bind_mode_anchor = nil
            M._bind_mode_hit = nil
        end
    end
end

--- Draw floating color picker on top of the whole menu (call after columns).
function M.draw_color_overlay()
    if not M.open_color then
        M._color_hit = nil
        return
    end
    local id = M.open_color
    local col = state.get_color(id, { 1, 1, 1, 1 })
    local pw, ph = 168, 138
    local ax = M._color_anchor
    local px, py
    if ax and ax.id == id then
        px = ax.x + (ax.w or 160) - pw
        py = ax.y + theme.ROW_H + 2
    else
        px = input.mx + 12
        py = input.my + 12
    end
    -- Keep on screen
    local sw, sh = 1920, 1080
    if draw and draw.get_screen_size then
        sw, sh = draw.get_screen_size()
    end
    if px < 4 then px = 4 end
    if py < 4 then py = 4 end
    if px + pw > sw - 4 then px = sw - pw - 4 end
    if py + ph > sh - 4 then py = sh - ph - 4 end

    M._color_hit = { x = px, y = py, w = pw, h = ph }

    -- Soft shadow / backdrop
    M.rect(px + 3, py + 4, pw, ph, theme.SHADOW, true, theme.CORNER)
    M.draw_color_picker(px, py, pw, ph, id, col)

    if input.hover(px, py, pw, ph) then
        if input.lmb or input.lmb_click or input.rmb or input.rmb_click then
            mark_interacted()
        end
    end
end

--- Right-click keybind mode menu (Always / Hold / Toggle).
function M.draw_bind_mode_overlay()
    if not M.open_bind_mode then
        M._bind_mode_hit = nil
        return
    end
    local id = M.open_bind_mode
    local modes = { "Always", "Hold", "Toggle" }
    local mode_id = id .. "_mode"
    local cur = tonumber(state.get(mode_id, 2)) or 2
    local pw = 78
    local row_h = 18
    local ph = 4 + #modes * row_h
    local ax = M._bind_mode_anchor
    local px, py
    if ax and ax.id == id then
        px = ax.x + (ax.w or 56) - pw
        py = ax.y + 18
    else
        px = input.mx
        py = input.my + 8
    end
    local sw, sh = 1920, 1080
    if draw and draw.get_screen_size then
        sw, sh = draw.get_screen_size()
    end
    if px < 4 then px = 4 end
    if py < 4 then py = 4 end
    if px + pw > sw - 4 then px = sw - pw - 4 end
    if py + ph > sh - 4 then py = sh - ph - 4 end

    M._bind_mode_hit = { x = px, y = py, w = pw, h = ph }

    M.rect(px + 3, py + 4, pw, ph, theme.SHADOW, true, theme.CORNER)
    M.rect(px, py, pw, ph, theme.OVERLAY, true, theme.CORNER)
    M.rect(px, py, pw, ph, theme.BORDER_HOT, false, theme.CORNER)

    for i, name in ipairs(modes) do
        local iy = py + 2 + (i - 1) * row_h
        local selected = (cur == i - 1)
        if input.hover(px, iy, pw, row_h) then
            M.rect(px + 3, iy + 1, pw - 6, row_h - 2, theme.HOVER, true, theme.CORNER_SMALL)
        end
        if selected then
            anim.draw_tab_indicator(px + 2, iy + 4, 3, row_h - 8)
        end
        M.text(px + 10, iy + 2, name, selected and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
        if input.clicked(px, iy, pw, row_h) then
            mark_interacted()
            state.set(mode_id, i - 1)
            M.open_bind_mode = nil
            M._bind_mode_hit = nil
        end
    end

    if input.hover(px, py, pw, ph) and (input.lmb_click or input.rmb_click) then
        mark_interacted()
    end
end

function M.vk_name(vk)
    local ok, mod = pcall(June.require, "core.vk_names")
    if ok and mod and mod.label then
        return mod.label(vk)
    end
    vk = tonumber(vk) or 0
    if vk <= 0 then return "none" end
    return string.format("%02X", vk)
end

function M.rect(x, y, w, h, col, filled, rounding)
    if not draw then return end
    local c = M.clip
    if c then
        local x2 = x + w
        local y2 = y + h
        local cx = c.x
        local cy = c.y
        local cx2 = c.x + c.w
        local cy2 = c.y + c.h
        if x2 <= cx or y2 <= cy or x >= cx2 or y >= cy2 then return end
        if x < cx then
            w = w - (cx - x)
            x = cx
        end
        if y < cy then
            h = h - (cy - y)
            y = cy
        end
        if x + w > cx2 then w = cx2 - x end
        if y + h > cy2 then h = cy2 - y end
        if w <= 0 or h <= 0 then return end
    end
    if filled then
        draw.rect_filled(x, y, w, h, col, rounding or 0)
    else
        draw.rect(x, y, w, h, col, rounding or 0, 1)
    end
end

function M.text(x, y, str, col, size)
    if draw and draw.text then
        draw.text(x, y, tostring(str), col, size or theme.FONT)
    end
end

function M.rainbow_bar(x, y, w, h)
    anim.draw_title_bar(x, y, w, h)
end

function M.group_box(x, y, w, h, title)
    local c = M.clip
    if c then
        -- Only paint the portion inside the clip rect
        local top = math.max(y, c.y)
        local bot = math.min(y + h, c.y + c.h)
        if bot <= top then return end
        M.rect(x, top, w, bot - top, theme.PANEL, true)
        M.rect(x, top, w, bot - top, theme.BORDER, false)
        if y >= c.y - 2 and y < c.y + c.h then
            M.text(x + 12, y + 5, title, theme.TEXT_ACTIVE, theme.FONT_TITLE)
        end
        return
    end
    M.rect(x, y, w, h, theme.PANEL, true)
    M.rect(x, y, w, h, theme.BORDER, false)
    M.text(x + 12, y + 5, title, theme.TEXT_ACTIVE, theme.FONT_TITLE)
end

local LISTEN_VKS = {
    0x02, 0x04, 0x05, 0x06, 0x08, 0x09, 0x0D, 0x10, 0x11, 0x12, 0x14, 0x1B, 0x20,
    0x25, 0x26, 0x27, 0x28, 0x2E,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
    0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B,
    0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0,
}

function M.tick_key_listen()
    if not M.listening_key then return end
    if input.key_pressed(0x1B) then
        M.listening_key = nil
        return
    end
    for i = 1, #LISTEN_VKS do
        local vk = LISTEN_VKS[i]
        if not listen_skip_vk(vk) and input.key_pressed(vk) then
            state.set_key(M.listening_key, vk)
            M.listening_key = nil
            return
        end
    end
end

local INPUT_VKS = {
    0x20,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
    0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
    0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE,
}

local INPUT_SHIFT = {
    [0x30] = ")", [0x31] = "!", [0x32] = "@", [0x33] = "#", [0x34] = "$",
    [0x35] = "%", [0x36] = "^", [0x37] = "&", [0x38] = "*", [0x39] = "(",
    [0xBA] = ":", [0xBB] = "+", [0xBC] = "<", [0xBD] = "_", [0xBE] = ">",
    [0xBF] = "?", [0xC0] = "~", [0xDB] = "{", [0xDC] = "|", [0xDD] = "}",
    [0xDE] = "\"",
}

local INPUT_PLAIN = {
    [0x20] = " ",
    [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
    [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
    [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-", [0xBE] = ".",
    [0xBF] = "/", [0xC0] = "`", [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]",
    [0xDE] = "'",
}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function vk_to_char(vk)
    local shift = input.key_down(0x10)
    if vk >= 0x41 and vk <= 0x5A then
        local ch = string.char(vk)
        return shift and ch or string.lower(ch)
    end
    if shift then
        return INPUT_SHIFT[vk] or INPUT_PLAIN[vk]
    end
    return INPUT_PLAIN[vk]
end

local function input_key_repeat(vk)
    if input.key_pressed(vk) then
        M._input_repeat_vk = vk
        M._input_repeat_at = tick_ms() + 400
        return true
    end
    if M._input_repeat_vk ~= vk or not input.key_down(vk) then
        return false
    end
    local now = tick_ms()
    if now >= M._input_repeat_at then
        M._input_repeat_at = now + 35
        return true
    end
    return false
end

local function focus_input(id)
    M.active_input = id
    M.open_combo = nil
    M.open_multi = nil
    M.open_color = nil
    M.open_bind_mode = nil
    M.listening_key = nil
    M._input_repeat_vk = nil
end

function M.tick_text_input()
    if not M.active_input or M.listening_key then return end
    if input.key_down(0x11) or input.key_down(0x12) then return end

    local id = M.active_input
    local val = tostring(state.get(id, ""))

    if input.key_pressed(0x1B) or input.key_pressed(0x0D) then
        M.active_input = nil
        M._input_repeat_vk = nil
        return
    end

    if input_key_repeat(0x08) then
        if #val > 0 then
            state.set(id, val:sub(1, -2))
        end
        return
    end

    if input_key_repeat(0x2E) then
        if #val > 0 then
            state.set(id, val:sub(1, -2))
        end
        return
    end

    for i = 1, #INPUT_VKS do
        local vk = INPUT_VKS[i]
        if input.key_pressed(vk) then
            local ch = vk_to_char(vk)
            if ch then
                state.set(id, val .. ch)
            end
            M._input_repeat_vk = nil
            return
        end
    end
end

function M.checkbox(x, y, w, id, label, opts)
    opts = opts or {}
    if id and not state.is_visible(id) then
        return 0
    end
    state.define(id, opts.default == true)
    if opts.color then
        state.define_color(id, opts.color)
    end
    local on = state.get(id, false)
    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    local hovered = input.hover(x, y, w, h)
    local hover_fill = anim.transition("check-hover:" .. tostring(id), hovered, 16)
    if hover_fill > 0.01 then
        M.rect(x, y + 1, w, h - 2, theme.alpha(theme.HOVER, hover_fill), true, theme.CORNER_SMALL)
    end

    -- Neverlose-style pill toggle on the right
    local tw = theme.TOGGLE_W or 34
    local th = theme.TOGGLE_H or 18
    local has_color = opts.color or state.colors[id]
    local right_pad = has_color and 28 or 8
    local tx = x + w - right_pad - tw
    local ty = y + (h - th) * 0.5
    local fill = on and anim.checkbox_fill() or theme.CHECK_OFF
    M.rect(tx, ty, tw, th, fill, true, theme.CORNER_PILL or 9)
    M.rect(tx, ty, tw, th, on and theme.FOCUS or theme.BORDER_SOFT, false, theme.CORNER_PILL or 9)
    local knob_r = (th - 4) * 0.5
    local knob_x = on and (tx + tw - knob_r - 3) or (tx + knob_r + 3)
    local knob_y = ty + th * 0.5
    if draw and draw.circle_filled then
        draw.circle_filled(knob_x, knob_y, knob_r, { 1, 1, 1, 1 }, 14)
    else
        M.rect(knob_x - knob_r, knob_y - knob_r, knob_r * 2, knob_r * 2, { 1, 1, 1, 1 }, true, knob_r)
    end

    M.text(x + 6, y + 5, label, on and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT)

    local swatch_clicked = false
    if has_color then
        local col = state.get_color(id, opts.color or { 1, 1, 1, 1 })
        local cx = x + w - 18
        local cy = y + (h - 12) * 0.5
        M.rect(cx, cy, 12, 12, col, true, 2)
        M.rect(cx, cy, 12, 12, theme.BORDER, false, 2)
        if ui_clicked(cx - 2, cy - 2, 16, 16) then
            swatch_clicked = true
            mark_interacted()
            local hh = rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1)
            M._hue_cache[id] = hh
            open_color_popup(id, x, y, w)
        elseif M.open_color == id then
            M._color_anchor = { id = id, x = x, y = y, w = w }
        end
    end

    if not swatch_clicked and interactive(x, y, w, h) and ui_clicked(x, y, w - (has_color and 22 or 0), h) then
        mark_interacted()
        state.toggle(id)
    end
    return h
end

function M.slider(x, y, w, id, label, minv, maxv, default, opts)
    opts = opts or {}
    if id and not state.is_visible(id) then return 0 end
    local is_float = opts.float == true
    state.define(id, default)
    local val = tonumber(state.get(id, default)) or default
    local h = theme.SLIDER_ROW_H
    if not in_clip(y, h) then return h end

    local hovered = input.hover(x, y, w, h)
    local hover_fill = anim.transition("slider-hover:" .. tostring(id), hovered, 16)
    if hover_fill > 0.01 then
        M.rect(x, y + 1, w, h - 2, theme.alpha(theme.HOVER, hover_fill), true, theme.CORNER_SMALL)
    end

    local fmt = opts.fmt or (is_float and "%.2f" or "%d")
    local shown = string.format(fmt, val)
    M.text(x + 4, y + 3, label, theme.TEXT, theme.FONT)
    local vw = text_w(shown, theme.FONT_SMALL)
    M.text(x + w - vw - 6, y + 3, shown, theme.TEXT_DIM, theme.FONT_SMALL)

    local sx = x + 4
    local sy = y + theme.LABEL_H + theme.LABEL_GAP + 4
    local sw = w - 8
    M.rect(sx, sy, sw, theme.SLIDER_H, theme.SLIDER_BG, true, theme.SLIDER_H * 0.5)
    local t = 0
    if maxv > minv then
        t = clamp((val - minv) / (maxv - minv), 0, 1)
    end
    if t > 0 then
        anim.draw_slider_fill(sx, sy, math.max(2, sw * t), theme.SLIDER_H)
    end
    M.rect(sx, sy, sw, theme.SLIDER_H, theme.BORDER_SOFT, false, theme.SLIDER_H * 0.5)
    local thumb_x = sx + sw * t
    M.rect(thumb_x - 3, sy - 2, 6, theme.SLIDER_H + 4,
        M.active_slider == id and theme.TEXT_ACTIVE or anim.checkbox_fill(), true, 3)

    local hot = input.hover(sx, sy - 4, sw, theme.SLIDER_H + 8)
    if interactive(x, y, w, h) and ((input.lmb_click and hot) or (input.lmb and M.active_slider == id)) then
        M.active_slider = id
        mark_interacted()
        local nt = clamp((input.mx - sx) / sw, 0, 1)
        local nv = minv + (maxv - minv) * nt
        if not is_float then nv = math.floor(nv + 0.5) end
        state.set(id, nv)
    elseif M.active_slider == id and not input.lmb then
        M.active_slider = nil
    end
    return h
end

function M.combo(x, y, w, id, label, options, default_idx)
    if id and not state.is_visible(id) then return 0 end
    state.define(id, default_idx or 0)
    local idx = tonumber(state.get(id, default_idx or 0)) or 0
    local label_y, ctrl_y, ctrl_h, h = stacked_metrics(y)
    local open = M.open_combo == id
    if not in_clip(y, h) and not open then return h end

    M.text(x + 4, label_y, label, theme.TEXT, theme.FONT)
    local bx, by, bw, bh = x + 4, ctrl_y, w - 8, ctrl_h
    local hovered = input.hover(bx, by, bw, bh)
    local fill = anim.interactive_fill("combo:" .. tostring(id), theme.BUTTON, hovered, open)
    M.rect(bx, by, bw, bh, fill, true, theme.CORNER_SMALL)
    M.rect(bx, by, bw, bh, open and theme.FOCUS or theme.BORDER_SOFT, false, theme.CORNER_SMALL)
    local cur = options[idx + 1] or options[1] or "-"
    M.text(bx + 6, by + math.floor((bh - 12) * 0.5), tostring(cur), theme.TEXT_ACTIVE, theme.FONT_SMALL)
    M.text(bx + bw - 13, by + math.floor((bh - 12) * 0.5), open and "^" or "v", open and theme.TEXT_ACTIVE or theme.TEXT_DIM, theme.FONT_SMALL)

    -- Header toggles open/closed (do not require clip hover - fixes "can't close")
    if ui_clicked(bx, by, bw, bh) then
        mark_interacted()
        if open then
            M.open_combo = nil
        else
            M.open_combo = id
            M.open_multi = nil
            M.open_color = nil
            M.open_bind_mode = nil
            M._list_scroll[id] = 0
        end
        open = M.open_combo == id
    end

    if open then
        local n = #options
        local off, max_off, vis = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)
        local list_h = vis * 18
        local list_y = by + bh
        apply_list_edge_scroll(id, n, M.LIST_MAX_VISIBLE, bx, list_y, bw, list_h)
        off = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)

        M.rect(bx + 2, by + bh + 2, bw, list_h, theme.SHADOW, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.OVERLAY, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.BORDER_HOT, false, theme.CORNER_SMALL)
        for row = 0, vis - 1 do
            local i = off + row + 1
            local opt = options[i]
            if not opt then break end
            local iy = by + bh + row * 18
            if input.hover(bx, iy, bw, 18) then
                M.rect(bx + 2, iy + 1, bw - 4, 16, theme.HOVER, true, theme.CORNER_SMALL)
            end
            if i - 1 == idx then
                M.rect(bx + 3, iy + 4, 2, 10, anim.checkbox_fill(), true, 1)
            end
            M.text(bx + 10, iy + 2, tostring(opt), (i - 1 == idx) and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
            if ui_clicked(bx, iy, bw, 18) then
                mark_interacted()
                state.set(id, i - 1)
                M.open_combo = nil
            end
        end
        if max_off > 0 then
            local thumb_h = math.max(10, list_h * (vis / n))
            local ty = by + bh + (list_h - thumb_h) * (off / math.max(1, max_off))
            M.rect(bx + bw - 4, by + bh, 3, list_h, theme.SLIDER_BG, true)
            anim.draw_scroll_thumb(bx + bw - 4, ty, 3, thumb_h)
        end
        if input.hover(bx, by, bw, bh + list_h) and input.lmb_click and not M.block_under then
            mark_interacted()
        end
        return h + list_h
    end
    return h
end

function M.multi(x, y, w, id, label, options, defaults)
    if id and not state.is_visible(id) then return 0 end
    defaults = defaults or {}
    local def = {}
    for i = 1, #options do
        def[i] = defaults[i] == true
    end
    state.define(id, def)
    local vals = state.get(id, def)
    if type(vals) ~= "table" then
        vals = def
        state.set(id, vals)
    end

    local h = theme.STACKED_ROW_H
    local open = M.open_multi == id
    if not in_clip(y, h) and not open then return h end

    local label_y, ctrl_y, ctrl_h = stacked_metrics(y)
    M.text(x + 4, label_y, label, theme.TEXT, theme.FONT)
    local bx, by, bw, bh = x + 4, ctrl_y, w - 8, ctrl_h
    local hovered = input.hover(bx, by, bw, bh)
    local fill = anim.interactive_fill("multi:" .. tostring(id), theme.BUTTON, hovered, open)
    M.rect(bx, by, bw, bh, fill, true, theme.CORNER_SMALL)
    M.rect(bx, by, bw, bh, open and theme.FOCUS or theme.BORDER_SOFT, false, theme.CORNER_SMALL)

    local parts = {}
    for i, opt in ipairs(options) do
        if vals[i] then parts[#parts + 1] = opt end
    end
    local summary = (#parts > 0) and table.concat(parts, ", ") or "None"
    if #summary > 28 then summary = summary:sub(1, 26) .. ".." end
    M.text(bx + 6, by + math.floor((bh - 12) * 0.5), summary, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_clicked(bx, by, bw, bh) then
        mark_interacted()
        if open then
            M.open_multi = nil
        else
            M.open_multi = id
            M.open_combo = nil
            M.open_color = nil
            M.open_bind_mode = nil
            M._list_scroll[id] = 0
        end
        open = M.open_multi == id
    end

    if open then
        local n = #options
        local off, max_off, vis = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)
        local list_h = vis * 18
        local list_y = by + bh
        apply_list_edge_scroll(id, n, M.LIST_MAX_VISIBLE, bx, list_y, bw, list_h)
        off = list_scroll_for(id, n, M.LIST_MAX_VISIBLE)

        M.rect(bx + 2, by + bh + 2, bw, list_h, theme.SHADOW, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.OVERLAY, true, theme.CORNER_SMALL)
        M.rect(bx, by + bh, bw, list_h, theme.BORDER_HOT, false, theme.CORNER_SMALL)
        for row = 0, vis - 1 do
            local i = off + row + 1
            local opt = options[i]
            if not opt then break end
            local iy = by + bh + row * 18
            local on = vals[i] == true
            if input.hover(bx, iy, bw, 18) then
                M.rect(bx + 2, iy + 1, bw - 4, 16, theme.HOVER, true, theme.CORNER_SMALL)
            end
            M.rect(bx + 5, iy + 3, 12, 12, theme.CHECK_OFF, true, 2)
            if on then
                M.rect(bx + 7, iy + 5, 8, 8, anim.checkbox_fill(), true, 2)
            end
            M.text(bx + 24, iy + 2, tostring(opt), on and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
            if ui_clicked(bx, iy, bw, 18) then
                mark_interacted()
                vals[i] = not on
                state.set(id, vals)
            end
        end
        if max_off > 0 then
            local thumb_h = math.max(10, list_h * (vis / n))
            local ty = by + bh + (list_h - thumb_h) * (off / math.max(1, max_off))
            M.rect(bx + bw - 4, by + bh, 3, list_h, theme.SLIDER_BG, true)
            anim.draw_scroll_thumb(bx + bw - 4, ty, 3, thumb_h)
        end
        if input.hover(bx, by, bw, bh + list_h) and input.lmb_click and not M.block_under then
            mark_interacted()
        end
        return h + list_h
    end
    return h
end

function M.button(x, y, w, id, label)
    if id and not state.is_visible(id) then return 0 end
    local h = 24
    if not in_clip(y, h) then return h end
    local hovered = input.hover(x, y, w, h)
    M.rect(x + 1, y + 2, w, h, theme.SHADOW, true, theme.CORNER_SMALL)
    M.rect(x, y, w, h, anim.interactive_fill("button:" .. tostring(id), theme.BUTTON, hovered, false), true, theme.CORNER_SMALL)
    M.rect(x, y, w, h, hovered and theme.BORDER_HOT or theme.BORDER_SOFT, false, theme.CORNER_SMALL)
    local tw = text_w(label, theme.FONT_SMALL)
    M.text(x + (w - tw) * 0.5, y + 6, label, theme.TEXT_ACTIVE, theme.FONT_SMALL)
    if interactive(x, y, w, h) and ui_clicked(x, y, w, h) then
        mark_interacted()
        state.fire_button(id)
    end
    return h
end

function M.label(x, y, w, text, dim)
    local h = theme.ROW_H - 4
    if not in_clip(y, h) then return h end
    M.text(x + 4, y + 3, text, dim and theme.TEXT_DIM or theme.TEXT_TITLE, theme.FONT_SMALL)
    return h
end

function M.separator(x, y, w)
    local h = 18
    if not in_clip(y, h) then return h end
    M.rect(x + 5, y + 9, w - 10, 1, theme.BORDER_SOFT, true)
    return h
end

function M.keybind(x, y, w, id, label, default_on, opts)
    opts = opts or {}
    if id and not state.is_visible(id) then return 0 end
    state.define(id, default_on == true)
    local mode_id = id .. "_mode"
    state.define(mode_id, 2) -- default Toggle (Always=0, Hold=1, Toggle=2)

    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    -- checkbox portion (leave room for key chip; mode is RMB popup)
    local chip_w = 56
    local cw = w - chip_w - 6
    local used = M.checkbox(x, y, cw, id, label, {
        default = default_on,
        color = opts.color or opts.colorpicker,
    })

    -- key chip: LMB bind, RMB mode (Always / Hold / Toggle)
    local kx = x + w - chip_w
    local ky = y + 3
    local listening = M.listening_key == id
    local vk = state.get_key(id)
    local klabel = listening and "..." or ("[" .. M.vk_name(vk) .. "]")
    local mode_open = M.open_bind_mode == id
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.ACCENT_DIM or theme.BUTTON, true, 8)
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.FOCUS or theme.BORDER_SOFT, false, 8)
    local tw = text_w(klabel, theme.FONT_SMALL)
    M.text(kx + (chip_w - tw) * 0.5, ky + 1, klabel, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_rmb_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.listening_key = nil
        open_bind_mode_popup(id, kx, ky, chip_w)
    elseif ui_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M.listening_key = listening and nil or id
    elseif mode_open then
        M._bind_mode_anchor = { id = id, x = kx, y = ky, w = chip_w }
    end

    return used
end

function M.aim_key_row(x, y, w, key_id, mode_id, label)
    if key_id and not state.is_visible(key_id) then return 0 end
    mode_id = mode_id or (key_id .. "_mode")
    state.define(mode_id, 1)

    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    local chip_w = 56
    M.text(x + 4, y + 3, label, theme.TEXT, theme.FONT)

    local kx = x + w - chip_w
    local ky = y + 3
    local listening = M.listening_key == key_id
    local vk = state.get_key(key_id)
    local klabel = listening and "..." or ("[" .. M.vk_name(vk) .. "]")
    local mode_open = M.open_bind_mode == key_id
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.ACCENT_DIM or theme.BUTTON, true, 8)
    M.rect(kx, ky, chip_w, 16, (listening or mode_open) and theme.FOCUS or theme.BORDER_SOFT, false, 8)
    local tw = text_w(klabel, theme.FONT_SMALL)
    M.text(kx + (chip_w - tw) * 0.5, ky + 1, klabel, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_rmb_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.listening_key = nil
        open_bind_mode_popup(key_id, kx, ky, chip_w)
    elseif ui_clicked(kx, ky, chip_w, 16) then
        mark_interacted()
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M.listening_key = listening and nil or key_id
    elseif mode_open then
        M._bind_mode_anchor = { id = key_id, x = kx, y = ky, w = chip_w }
    end

    return h
end

function M.hotkey_row(x, y, w, id, label, default_vk)
    if id and not state.is_visible(id) then return 0 end
    if state.get_key(id) == 0 and default_vk and default_vk ~= 0 then
        state.set_key(id, default_vk)
    end
    local mode_id = id .. "_mode"
    state.define(mode_id, 1) -- Always=0, Hold=1, Toggle=2

    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    local chip_w = 56
    M.text(x + 4, y + 4, label, theme.TEXT, theme.FONT)

    local kx = x + w - chip_w
    local ky = y + 4
    local listening = M.listening_key == id
    local vk = state.get_key(id)
    local klabel = listening and "..." or ("[" .. M.vk_name(vk) .. "]")
    local mode_open = M.open_bind_mode == id
    M.rect(kx, ky, chip_w, 18, (listening or mode_open) and theme.ACCENT_DIM or theme.BUTTON, true, 8)
    M.rect(kx, ky, chip_w, 18, (listening or mode_open) and theme.FOCUS or theme.BORDER_SOFT, false, 8)
    local tw = text_w(klabel, theme.FONT_SMALL)
    M.text(kx + (chip_w - tw) * 0.5, ky + 3, klabel, theme.TEXT_ACTIVE, theme.FONT_SMALL)

    if ui_rmb_clicked(kx, ky, chip_w, 18) then
        mark_interacted()
        M.listening_key = nil
        open_bind_mode_popup(id, kx, ky, chip_w)
    elseif ui_clicked(kx, ky, chip_w, 18) then
        mark_interacted()
        M.open_bind_mode = nil
        M._bind_mode_hit = nil
        M.listening_key = listening and nil or id
    elseif mode_open then
        M._bind_mode_anchor = { id = id, x = kx, y = ky, w = chip_w }
    end

    return h
end

function M.color_row(x, y, w, id, label, default_col)
    if id and not state.is_visible(id) then return 0 end
    state.define_color(id, default_col or { 1, 1, 1, 1 })
    local col = state.get_color(id, default_col)
    local h = theme.ROW_H
    if not in_clip(y, h) then return h end

    M.text(x + 4, y + 3, label, theme.TEXT, theme.FONT)
    local cx = x + w - 18
    M.rect(cx, y + 4, 12, 12, col, true, 3)
    M.rect(cx, y + 4, 12, 12, theme.BORDER, false, 3)

    if ui_clicked(cx - 2, y + 2, 16, 16) then
        mark_interacted()
        M._hue_cache[id] = select(1, rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1))
        open_color_popup(id, x, y, w)
    elseif M.open_color == id then
        M._color_anchor = { id = id, x = x, y = y, w = w }
    end
    return h
end

function M.draw_color_picker(px, py, pw, ph, id, col)
    M.rect(px, py, pw, ph, theme.OVERLAY, true, theme.CORNER)
    M.rect(px, py, pw, ph, theme.BORDER_HOT, false, theme.CORNER)

    local hue = M._hue_cache[id]
    if not hue then
        hue = select(1, rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1))
        M._hue_cache[id] = hue
    end
    local _, sat, val = rgb_to_hsv(col[1] or 1, col[2] or 1, col[3] or 1)
    local alpha = col[4] or 1

    local sq = 96
    local sx, sy = px + 8, py + 8
    -- Saturation / value square (sampled grid)
    local steps = 12
    local cell = sq / steps
    for iy = 0, steps - 1 do
        for ix = 0, steps - 1 do
            local s = ix / (steps - 1)
            local v = 1 - iy / (steps - 1)
            local r, g, b = hsv_to_rgb(hue, s, v)
            M.rect(sx + ix * cell, sy + iy * cell, cell + 0.5, cell + 0.5, { r, g, b, 1 }, true)
        end
    end
    M.rect(sx, sy, sq, sq, theme.BORDER, false, theme.CORNER_SMALL)

    -- Hue bar
    local hx, hy, hw, hh = sx + sq + 8, sy, 14, sq
    for i = 0, 23 do
        local t = i / 23
        local r, g, b = hsv_to_rgb(t, 1, 1)
        M.rect(hx, hy + i * (hh / 24), hw, hh / 24 + 0.5, { r, g, b, 1 }, true)
    end
    M.rect(hx, hy, hw, hh, theme.BORDER, false, theme.CORNER_SMALL)

    -- Alpha bar
    local ax, ay, aw, ah = sx, sy + sq + 8, sq + 22, 10
    M.rect(ax, ay, aw, ah, { 0.15, 0.15, 0.15, 1 }, true)
    M.rect(ax, ay, aw * clamp(alpha, 0, 1), ah, { col[1], col[2], col[3], 1 }, true)
    M.rect(ax, ay, aw, ah, theme.BORDER, false, theme.CORNER_SMALL)

    -- Preview
    local prx = ax + aw + 6
    M.rect(prx, ay - 2, 18, 14, { col[1], col[2], col[3], alpha }, true)
    M.rect(prx, ay - 2, 18, 14, theme.BORDER, false)

    local function apply(s, v, a, new_hue)
        if new_hue then
            M._hue_cache[id] = new_hue
            hue = new_hue
        end
        local r, g, b = hsv_to_rgb(hue, s, v)
        state.set_color(id, { r, g, b, a })
        if id == "june_ui_accent" then
            anim.sync_theme()
        end
    end

    if input.lmb and input.hover(sx, sy, sq, sq) then
        M.popup_used_click = true
        local ns = clamp((input.mx - sx) / sq, 0, 1)
        local nv = clamp(1 - (input.my - sy) / sq, 0, 1)
        apply(ns, nv, alpha, nil)
    elseif input.lmb and input.hover(hx, hy, hw, hh) then
        M.popup_used_click = true
        local nh = clamp((input.my - hy) / hh, 0, 1)
        apply(sat, val, alpha, nh)
    elseif input.lmb and input.hover(ax, ay, aw, ah) then
        M.popup_used_click = true
        local na = clamp((input.mx - ax) / aw, 0, 1)
        apply(sat, val, na, nil)
    end

    if input.hover(px, py, pw, ph) and input.lmb_click then
        M.popup_used_click = true
    end

    -- Cursor marks
    local mx = sx + sat * sq
    local my = sy + (1 - val) * sq
    M.rect(mx - 2, my - 2, 4, 4, { 1, 1, 1, 1 }, false)
    M.rect(hx - 1, hy + hue * hh - 1, hw + 2, 3, { 1, 1, 1, 1 }, false)
end

function M.input_row(x, y, w, id, label, default)
    if id and not state.is_visible(id) then return 0 end
    state.define(id, default or "")
    local val = tostring(state.get(id, default or ""))
    local label_y, ctrl_y, ctrl_h, h = stacked_metrics(y)
    if not in_clip(y, h) then return h end
    M.text(x + 4, label_y, label, theme.TEXT, theme.FONT)
    local bx, by, bw, bh = x + 4, ctrl_y, w - 8, ctrl_h
    local focused = M.active_input == id
    local hot = input.hover(bx, by, bw, bh)
    if focused then
        M._active_input_rect = { x = bx, y = by, w = bw, h = bh }
    end
    M.rect(bx, by, bw, bh, anim.interactive_fill("input:" .. tostring(id), theme.BUTTON, hot, focused), true, theme.CORNER_SMALL)
    M.rect(bx, by, bw, bh, focused and theme.FOCUS or (hot and theme.BORDER_HOT or theme.BORDER_SOFT), false, theme.CORNER_SMALL)

    local shown = val
    local text_x = bx + 6
    local max_w = bw - 12
    local text_y = by + math.floor((bh - 12) * 0.5)
    if shown == "" then
        M.text(text_x, text_y, "...", theme.TEXT_DIM, theme.FONT_SMALL)
    else
        while #shown > 0 and text_w(shown, theme.FONT_SMALL) > max_w do
            shown = shown:sub(2)
        end
        M.text(text_x, text_y, shown, focused and theme.TEXT_ACTIVE or theme.TEXT, theme.FONT_SMALL)
    end

    if focused then
        local caret_x = text_x + text_w(shown ~= "" and shown or "", theme.FONT_SMALL)
        local now = tick_ms()
        if math.floor(now / 500) % 2 == 0 then
            M.rect(caret_x, by + math.floor((bh - 10) * 0.5), 1, 10, theme.TEXT_ACTIVE, true)
        end
    end

    if interactive(bx, by, bw, bh) and ui_clicked(bx, by, bw, bh) then
        mark_interacted()
        focus_input(id)
    end
    return h
end

function M.estimate_height(item)
    local t = item.type
    local extra = 0
    -- Color pickers overlay - they do not expand layout height
    if item.id and M.open_combo == item.id and item.options then
        extra = math.min(#item.options, M.LIST_MAX_VISIBLE) * 18
    elseif item.id and M.open_multi == item.id and item.options then
        extra = math.min(#item.options, M.LIST_MAX_VISIBLE) * 18
    end
    if t == "slider" then
        return theme.SLIDER_ROW_H + extra
    elseif t == "combo" or t == "multi" or t == "input" then
        return theme.STACKED_ROW_H + extra
    elseif t == "separator" then
        return 18
    elseif t == "button" then
        return 24
    elseif t == "label" then
        return theme.ROW_H - 4
    elseif t == "color" then
        return theme.ROW_H
    elseif t == "checkbox" or t == "keybind" or t == "aim_key" or t == "hotkey" then
        return theme.ROW_H
    end
    return theme.ROW_H + extra
end

function M.draw_item(item, x, y, w)
    local t = item.type
    if t == "checkbox" then
        return M.checkbox(x, y, w, item.id, item.label, item)
    elseif t == "keybind" then
        return M.keybind(x, y, w, item.id, item.label, item.default, item)
    elseif t == "aim_key" then
        return M.aim_key_row(x, y, w, item.id, item.mode_id, item.label)
    elseif t == "hotkey" then
        return M.hotkey_row(x, y, w, item.id, item.label, item.default)
    elseif t == "slider" then
        return M.slider(x, y, w, item.id, item.label, item.min, item.max, item.default, item)
    elseif t == "combo" then
        return M.combo(x, y, w, item.id, item.label, item.options, item.default)
    elseif t == "multi" then
        return M.multi(x, y, w, item.id, item.label, item.options, item.defaults)
    elseif t == "button" then
        return M.button(x + 4, y, w - 8, item.id, item.label)
    elseif t == "label" then
        return M.label(x, y, w, item.label, item.dim)
    elseif t == "separator" then
        return M.separator(x, y, w)
    elseif t == "color" then
        return M.color_row(x, y, w, item.id, item.label, item.default)
    elseif t == "input" then
        return M.input_row(x, y, w, item.id, item.label, item.default)
    end
    return 0
end

return M

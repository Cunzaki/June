--[[
  Neverlose-style custom menu for June.
  INSERT toggles by default (rebindable in Main -> Menu).
  Scroll: mouse wheel when Vector exposes a reader; else edge-hover (top/bottom of column).
]]

local theme = June.require("ui.gs_theme")
local gin = June.require("ui.gs_input")
local widgets = June.require("ui.gs_widgets")
local anim = June.require("ui.gs_anim")
local icons = June.require("ui.gs_icons")
local catalog = June.require("ui.catalog")
local state = June.require("ui.gs_state")

local M = {}

local TOGGLE_VK_DEFAULT = 0x2D

local function menu_toggle_vk()
    local vk = state.get_key("june_ui_menu_key")
    if not vk or vk == 0 then
        vk = TOGGLE_VK_DEFAULT
    end
    return vk
end
local open = true
local tab_index = 1
local win_x, win_y = 80, 80
local scroll = { left = 0, right = 0 }

local SCROLL_EDGE = 36
local SCROLL_SPEED = 5
local WHEEL_STEP = 48
local PAGE_STEP = 90
local VK_PRIOR, VK_NEXT = 0x21, 0x22

local function screen_size()
    if draw and draw.get_screen_size then
        return draw.get_screen_size()
    end
    if utility and utility.get_screen_size then
        return utility.get_screen_size()
    end
    return 1920, 1080
end

local function clamp_window()
    local sw, sh = screen_size()
    win_x = math.max(0, math.min(win_x, sw - theme.WINDOW_W))
    win_y = math.max(0, math.min(win_y, sh - 40))
end

local function master_on(id)
    if not id then return true end
    return state.get(id, false) == true
end

local function combo_value(id)
    if not id then return nil end
    local v = state.get(id)
    if v == nil and menu and menu.get then
        v = menu.get(id)
    end
    return tonumber(v)
end

local function color_override_on(idx)
    if not idx then return true end
    local t = state.get("june_ui_color_overrides")
    if type(t) ~= "table" then return false end
    local v = t[idx]
    if v == nil and idx >= 1 then
        v = t[idx - 1]
    end
    return v == true or v == 1
end

local function item_visible(item, group)
    if group and group.master then
        if item.id == group.master then
            return true
        end
        if not master_on(group.master) then
            return false
        end
    end
    if item.gate and not master_on(item.gate) then
        return false
    end
    if item.gate2 and not master_on(item.gate2) then
        return false
    end
    if item.gate_combo then
        local cur = combo_value(item.gate_combo)
        local want = tonumber(item.gate_combo_value) or 0
        if cur ~= want then
            return false
        end
    end
    -- Show if ANY (combo_id, value) pair matches. pair = { id, value } or { id, {v1,v2} }
    if item.gate_any_combo then
        local ok = false
        for _, pair in ipairs(item.gate_any_combo) do
            local cid = pair[1] or pair.id
            local want = pair[2] or pair.value
            local cur = combo_value(cid)
            if type(want) == "table" then
                for _, w in ipairs(want) do
                    if cur == w then ok = true; break end
                end
            elseif cur == want then
                ok = true
            end
            if ok then break end
        end
        if not ok then return false end
    end
    if item.color_override_idx and not color_override_on(item.color_override_idx) then
        return false
    end
    if item.id and not state.is_visible(item.id) then
        return false
    end
    return true
end

local function content_height(items, group)
    local h = 0
    local count = 0
    for _, item in ipairs(items) do
        if item_visible(item, group) then
            h = h + widgets.estimate_height(item)
            count = count + 1
        end
    end
    if count > 1 then
        h = h + (count - 1) * theme.ITEM_GAP
    end
    return h + 20
end

local function group_visible(group)
    local items = group.items or {}
    for _, item in ipairs(items) do
        if item_visible(item, group) then
            return true
        end
    end
    return false
end

local function draw_sidebar(x, y, h)
    widgets.rect(x, y, theme.SIDEBAR_W, h, theme.SIDEBAR, true)
    widgets.rect(x + theme.SIDEBAR_W - 1, y, 1, h, theme.BORDER_SOFT, true)

    local tabs = catalog.TABS
    local cy = y + 10
    local last_section = nil

    for i, tab in ipairs(tabs) do
        local section = tab.section or ""
        if section ~= last_section then
            if last_section ~= nil then
                cy = cy + (theme.SECTION_GAP or 10)
            end
            widgets.text(x + 16, cy + 2, string.upper(section), theme.TEXT_SECTION or theme.TEXT_DIM, theme.FONT_SECTION or 11)
            cy = cy + (theme.SECTION_LABEL_H or 18)
            last_section = section
        end

        local row_h = theme.TAB_H
        local active = i == tab_index
        local hot = gin.hover(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4)
        local emphasis = anim.transition("tab:" .. tab.id, active or hot, 14)

        if active then
            widgets.rect(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4, theme.SIDEBAR_ACTIVE, true, theme.CORNER)
            widgets.rect(x + 8, cy, 3, row_h - 4, anim.tab_icon_color(), true, 2)
        elseif emphasis > 0.01 then
            widgets.rect(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4,
                theme.alpha(theme.HOVER, emphasis * 0.55), true, theme.CORNER)
        end

        local col = active and (anim.tab_icon_color and anim.tab_icon_color() or theme.ACCENT) or anim.mix(theme.TEXT_DIM, theme.TEXT, emphasis * 0.55)
        local icon_cx = x + 26
        local icon_cy = cy + (row_h - 4) * 0.5
        icons.draw(tab.icon or tab.id, icon_cx, icon_cy, col)
        widgets.text(x + 44, cy + 8, tab.title, col, theme.FONT)

        if gin.clicked(x + 8, cy, theme.SIDEBAR_W - 16, row_h - 4) then
            tab_index = i
            scroll.left = 0
            scroll.right = 0
            widgets.open_combo = nil
            widgets.open_multi = nil
        end

        cy = cy + row_h
    end
end

local function clamp_scroll(key, content_h, view_h)
    local max_scroll = math.max(0, content_h - view_h)
    if scroll[key] < 0 then scroll[key] = 0 end
    if scroll[key] > max_scroll then scroll[key] = max_scroll end
    return max_scroll
end

local function draw_scrollbar(x, y, h, content_h, scroll_key)
    local max_scroll = clamp_scroll(scroll_key, content_h, h)
    if max_scroll <= 0 then
        scroll[scroll_key] = 0
        return
    end

    local thumb_h = math.max(34, h * (h / content_h))
    local t = scroll[scroll_key] / max_scroll
    local thumb_y = y + t * (h - thumb_h)

    widgets.rect(x, y, 4, h, { 0, 0, 0, 0.26 }, true)
    widgets.rect(x + 1, y + 1, 2, h - 2, theme.SLIDER_BG, true)
    anim.draw_scroll_thumb(x, thumb_y, 4, thumb_h)
end

local function handle_column_scroll(x, y, w, h, scroll_key, content_h)
    local max_scroll = clamp_scroll(scroll_key, content_h, h)
    if max_scroll <= 0 then return end

    local hot = gin.hover(x, y, w + 14, h)
    if not hot and scroll_key == "left" then
        hot = gin.hover(gin.ui_x, y, theme.SIDEBAR_W + 8, h)
    end
    if not hot then return end

    -- Prefer real wheel when any probe delivers notches this frame.
    -- Open dropdowns consume the wheel first (see gs_widgets).
    if gin.wheel ~= 0 and not widgets.wheel_consumed then
        scroll[scroll_key] = scroll[scroll_key] - gin.wheel * WHEEL_STEP
        clamp_scroll(scroll_key, content_h, h)
        widgets.wheel_consumed = true
        return
    end

    -- Page Up / Page Down while hovering a column (documented IsKeyDown path).
    if gin.key_pressed(VK_PRIOR) then
        scroll[scroll_key] = scroll[scroll_key] - PAGE_STEP
        clamp_scroll(scroll_key, content_h, h)
        return
    end
    if gin.key_pressed(VK_NEXT) then
        scroll[scroll_key] = scroll[scroll_key] + PAGE_STEP
        clamp_scroll(scroll_key, content_h, h)
        return
    end

    -- Fallback: edge hover (only when wheel isn't available / not moving).
    if gin.my < y + SCROLL_EDGE then
        scroll[scroll_key] = scroll[scroll_key] - SCROLL_SPEED
        clamp_scroll(scroll_key, content_h, h)
    elseif gin.my > y + h - SCROLL_EDGE then
        scroll[scroll_key] = scroll[scroll_key] + SCROLL_SPEED
        clamp_scroll(scroll_key, content_h, h)
    end
end

local function draw_group_title(x, box_top, title)
    widgets.text(x + 12, box_top + 7, string.upper(tostring(title or "")), theme.TEXT_SECTION or theme.TEXT_DIM, theme.FONT_CAPTION or 11)
end

local function draw_group_column(groups, x, y, w, h, scroll_key)
    local pad = theme.GROUP_PAD
    local visible_groups = {}
    for _, group in ipairs(groups) do
        if group_visible(group) then
            visible_groups[#visible_groups + 1] = group
        end
    end

    local total = 0
    for _, group in ipairs(visible_groups) do
        total = total + content_height(group.items or {}, group) + theme.GROUP_HEADER_H + theme.GROUP_GAP
    end

    clamp_scroll(scroll_key, total, h)

    local gy = y + pad - scroll[scroll_key]
    widgets.clip = { x = x, y = y, w = w, h = h }

    for _, group in ipairs(visible_groups) do
        local items = group.items or {}
        local inner_h = content_height(items, group)
        local box_h = inner_h + theme.GROUP_HEADER_H

        local box_top = gy
        local box_bot = gy + box_h
        if box_bot > y and box_top < y + h then
            local vis_y = math.max(box_top, y)
            local vis_b = math.min(box_bot, y + h)
            local vis_h = vis_b - vis_y
            if vis_h > 1 then
                widgets.rect(x + 2, vis_y + 2, w, vis_h, theme.SHADOW, true)
                widgets.rect(x, vis_y, w, vis_h, theme.PANEL, true)
                widgets.rect(x, vis_y, w, vis_h, theme.BORDER_SOFT, false)
                if box_top >= y - 2 and box_top < y + h then
                    widgets.rect(x + 1, box_top + 2, w - 2, theme.GROUP_HEADER_H - 3, theme.PANEL_ALT, true)
                    anim.draw_section_top(x + 1, box_top, w - 2)
                    draw_group_title(x, box_top, group.title)
                end
            end

            local iy = gy + theme.GROUP_HEADER_H + 6
            local ix = x + 7
            local iw = w - 16
            for _, item in ipairs(items) do
                if item_visible(item, group) then
                    local est = widgets.estimate_height(item)
                    if iy >= y and iy + est <= y + h then
                        local ok, used = pcall(widgets.draw_item, item, ix, iy, iw)
                        if not ok then
                            used = est
                        elseif type(used) ~= "number" or used < 1 then
                            used = est
                        end
                        iy = iy + used + theme.ITEM_GAP
                    else
                        iy = iy + est + theme.ITEM_GAP
                    end
                end
            end
        end

        gy = gy + box_h + theme.GROUP_GAP
    end

    widgets.clip = nil
    handle_column_scroll(x, y, w, h, scroll_key, total)
    draw_scrollbar(x + w + 2, y, h, total, scroll_key)
end

local function split_groups(groups, tab_id)
    if (tab_id == "aimbot" or tab_id == "main" or tab_id == "players" or tab_id == "world") and #groups >= 2 then
        return { groups[1] }, { groups[2] }
    end
    if tab_id == "config" and #groups >= 2 then
        return { groups[1] }, { groups[2] }
    end
    if #groups == 2 then
        return { groups[1] }, { groups[2] }
    end
    if #groups == 1 then
        return { groups[1] }, {}
    end
    local left, right = {}, {}
    for i, g in ipairs(groups) do
        if i % 2 == 1 then
            left[#left + 1] = g
        else
            right[#right + 1] = g
        end
    end
    return left, right
end

function M.init()
    state.define("june_ui_custom_colors", false)
    state.define("june_ui_custom_anim", false)
    state.define("june_ui_per_element", false)
    state.define("june_ui_show_cursor_dot", true)
    state.define("june_ui_accent", theme.ACCENT)
    state.define_color("june_ui_accent", theme.ACCENT)
    state.define("june_ui_accent_anim", 1)
    state.define("june_ui_anim_speed", 40)
    state.define("june_ui_bg_dim", 0)
    state.define("june_ui_menu_fade", false)
    state.define("june_ui_anim_targets", {
        true, true, true, true, true, true, true, true,
    })
    state.define("june_ui_color_overrides", {})
    state.define("june_ui_style_title", 0)
    state.define("june_ui_style_section", 0)
    state.define("june_ui_style_slider", 0)
    state.define("june_ui_style_scroll", 0)
    state.define("june_ui_style_sidebar", 0)
    state.define("june_ui_style_checkbox", 0)
    state.define("june_ui_style_overlay", 0)
    state.define_color("june_ui_col_title", theme.ACCENT)
    state.define_color("june_ui_col_section", theme.ACCENT)
    state.define_color("june_ui_col_slider", theme.ACCENT)
    state.define_color("june_ui_col_scroll", theme.ACCENT)
    state.define_color("june_ui_col_sidebar", theme.ACCENT)
    state.define_color("june_ui_col_checkbox", theme.ACCENT)
    state.define_color("june_ui_col_overlay", theme.ACCENT)
    if state.get_key("june_ui_menu_key") == 0 then
        state.set_key("june_ui_menu_key", TOGGLE_VK_DEFAULT)
    end
    local sw, sh = screen_size()
    win_x = math.floor((sw - theme.WINDOW_W) * 0.5)
    win_y = math.floor((sh - theme.WINDOW_H) * 0.3)
end

function M.is_open()
    return open
end

function M.draw()
    if not draw then return end

    gin.begin_frame()
    anim.sync_theme()
    widgets.begin_popups()

    if gin.key_pressed(menu_toggle_vk()) and not widgets.listening_key and not widgets.active_input then
        open = not open
        gin.set_menu_open(open)
    end

    widgets.tick_key_listen()
    widgets.tick_text_input()

    if not open then
        if gin._menu_open or gin._game_cursor_hidden then
            gin.set_menu_open(false)
        end
        return
    end

    gin.set_menu_open(true)
    clamp_window()

    local x, y = win_x, win_y
    local w, h = theme.WINDOW_W, theme.WINDOW_H
    gin.set_ui_rect(x, y, w, h)

    -- Frame
    local fade = anim.menu_fade()
    widgets.rect(x, y, w, h, theme.alpha(anim.panel_bg(), fade), true)
    widgets.rect(x, y, w, h, theme.BORDER, false)
    widgets.rect(x + 1, y + 1, w - 2, 1, theme.BORDER_HOT, true)
    anim.draw_title_bar(x + 1, y + 1, w - 2, 2)

    local title_h = 28
    widgets.rect(x + 1, y + 3, w - 2, title_h, theme.BG_INNER, true)
    widgets.rect(x + 1, y + title_h + 3, w - 2, 1, theme.BORDER_SOFT, true)
    local tab = catalog.TABS[tab_index]
    -- Brand lives in the top bar so the page title doesn't look orphaned.
    widgets.text(x + 14, y + 9, "JUNE", theme.TEXT_ACTIVE, theme.FONT_BRAND or 15)
    local brand_w = 52
    if draw and draw.get_text_size then
        local tw = draw.get_text_size("JUNE", theme.FONT_BRAND or 15)
        if type(tw) == "number" then brand_w = tw + 10 end
    end
    widgets.text(x + 14 + brand_w, y + 11, "/  " .. (tab and tab.title or "Menu"), theme.TEXT_TITLE, theme.FONT_TITLE)

    if gin.lmb_click and gin.hover(x, y, w, title_h + 5)
        and not widgets.active_slider and not widgets.listening_key
        and not widgets.active_input
        and not widgets.block_under
        and not widgets.open_combo and not widgets.open_multi and not widgets.open_color
        and not widgets.open_bind_mode then
        widgets.dragging_window = true
        widgets.drag_offset_x = gin.mx - win_x
        widgets.drag_offset_y = gin.my - win_y
    end
    if widgets.dragging_window then
        if gin.lmb then
            win_x = gin.mx - widgets.drag_offset_x
            win_y = gin.my - widgets.drag_offset_y
            clamp_window()
        else
            widgets.dragging_window = false
        end
    end

    local body_y = y + title_h + 6
    local body_h = h - title_h - 10

    draw_sidebar(x + 1, body_y, body_h)

    local content_x = x + theme.SIDEBAR_W + 12
    local content_w = w - theme.SIDEBAR_W - 30
    local groups = catalog.groups_for(tab and tab.id or "aimbot")
    local left_groups, right_groups = split_groups(groups, tab and tab.id or "aimbot")
    local dual = #right_groups > 0
    local col_w = dual and math.floor((content_w - 16) * 0.5) or (content_w - 8)

    draw_group_column(left_groups, content_x, body_y + 2, col_w, body_h - 4, "left")
    if dual then
        draw_group_column(right_groups, content_x + col_w + 12, body_y + 2, col_w, body_h - 4, "right")
    end

    -- Floating popups above all sections
    widgets.draw_color_overlay()
    widgets.draw_bind_mode_overlay()
    widgets.end_popups()

    gin.draw_cursor()
end

return M

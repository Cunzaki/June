--[[
  Neverlose-layout catalog for June.
  Values / callbacks come from menu_defs + config via ui.menu_shim.

  Visibility:
    - group.master  → only that toggle shows until enabled; then children appear
    - item.gate     → nested child (also needs parent/master on)
    - item.gate2    → second required toggle
]]

local M = {}

local function cb(id, label, default, color, gate)
    return { type = "checkbox", id = id, label = label, default = default == true, color = color, gate = gate }
end

local function kb(id, label, default, gate, color)
    return { type = "keybind", id = id, label = label, default = default == true, gate = gate, color = color }
end

local function sl(id, label, minv, maxv, default, float, gate, extra)
    local item = {
        type = "slider",
        id = id,
        label = label,
        min = minv,
        max = maxv,
        default = default,
        float = float == true,
        fmt = float and "%.2f" or "%d",
        gate = gate,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do item[k] = v end
    end
    return item
end

local function combo(id, label, options, default, gate, gate2)
    return { type = "combo", id = id, label = label, options = options, default = default or 0, gate = gate, gate2 = gate2 }
end

local function multi(id, label, options, defaults, gate)
    return { type = "multi", id = id, label = label, options = options, defaults = defaults, gate = gate }
end

local function btn(id, label, gate)
    return { type = "button", id = id, label = label, gate = gate }
end

local function sep(gate)
    return { type = "separator", gate = gate }
end

local function label(text, dim, gate)
    return { type = "label", label = text, dim = dim, gate = gate }
end

local function hk(id, label, gate, default_vk)
    return { type = "hotkey", id = id, label = label, gate = gate, default = default_vk or 0x02 }
end

local function ak(key_id, label, gate)
    return { type = "aim_key", id = key_id, mode_id = key_id .. "_mode", label = label, gate = gate }
end

local function input(id, label_text, default, gate)
    return { type = "input", id = id, label = label_text, default = default or "", gate = gate }
end

local function color(id, label_text, default, gate, override_idx)
    return {
        type = "color",
        id = id,
        label = label_text,
        default = default,
        gate = gate,
        color_override_idx = override_idx,
    }
end

M.TABS = {
    { id = "aimbot", icon = "aim", title = "Aimbot", section = "Aimbot" },
    { id = "players", icon = "visuals", title = "Players", section = "Visuals" },
    { id = "world", icon = "world", title = "World", section = "Visuals" },
    { id = "main", icon = "misc", title = "Main", section = "Miscellaneous" },
    { id = "config", icon = "config", title = "Configs", section = "Miscellaneous" },
}

M.SECTIONS = { "Aimbot", "Visuals", "Miscellaneous" }

local BONE_OPTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Closest" }
local FOV_STYLES = { "Circle", "Filled Circle", "Dotted", "Square", "Filled Square", "Dashed" }
local LINE_STYLES = { "Solid", "Dashed", "Dotted" }
local ENDPOINTS = { "Filled Circle", "Outline Circle", "Dot", "Square", "Cross", "None" }
local BOX_TYPES = { "2D", "Corner", "3D" }
local VIEW_STYLES = { "Solid", "Dashed", "Fade" }
local TRACER_ORIGINS = { "Bottom", "Center", "Mouse" }
local TRACER_STYLES = { "Solid", "Dashed", "Dotted" }
local CROSS_STYLES = { "Cross", "Dot", "Circle", "Plus" }
local ANIM_MODES = { "Static", "Rainbow", "Pulse", "Wave", "Flow" }
local ELEM_MODES = { "Default", "Static", "Rainbow", "Pulse", "Wave", "Flow" }

local GADGET_BLACKLIST = {
    "Drone", "Claymore", "C4", "Jammer", "Sticky Cam", "BP Cam", "Map Cam",
    "Breach", "Hard Breach", "Prox Alarm", "Barbed Wire", "Shield", "Thermite",
    "Shock Bat", "Inc Canister", "Needle Mine", "Toxic",
}

local ACCENT = { 0.294, 0.549, 0.957, 1 }

local function build_aimbot()
    local AIM = "aimbot_enabled"
    local SIL = "silent_aim_enabled"

    local aim = {
        title = "Aimbot",
        master = AIM,
        items = {
            kb(AIM, "Enable Aimbot", false),
            ak("aimbot_key", "Aim Key"),
            sep(),
            label("Targeting", false),
            combo("aimbot_target_type", "Target Type", { "Crosshair", "Distance" }, 0),
            combo("aimbot_bone", "Hitbox", BONE_OPTS, 0),
            sl("aimbot_fov", "Field Of View", 1, 500, 125),
            sl("aimbot_smooth", "Smoothing", 1, 20, 5),
            sl("aimbot_max_distance", "Max Distance", 1, 500, 500),
            sep(),
            label("Options", false),
            cb("aimbot_sticky", "Sticky Aim", false),
            cb("aimbot_vischeck", "Visibility Check", false),
            combo("vis_check_priority", "Vis Priority", { "Distance", "Crosshair" }, 0, "aimbot_vischeck"),
            cb("aimbot_team_check", "Team Check", false),
            cb("aimbot_filter_health", "Health Check", false),
            cb("aimbot_prediction", "Prediction", false),
            sl("aimbot_prediction_val", "Prediction Strength", 0, 500, 50, false, "aimbot_prediction"),
            sep(),
            label("Gadget Aim", false),
            cb("utilities_aimbot", "Gadget Aim", false),
            cb("aimbot_players_priority", "Players Over Gadgets", false, nil, "utilities_aimbot"),
            sl("utilities_max_distance", "Gadget Max Distance", 1, 250, 75, false, "utilities_aimbot"),
            cb("aimbot_gadget_team_check", "Gadget Team Check", false, nil, "utilities_aimbot"),
            sep(),
            label("Visuals", false),
            cb("aimbot_fov_visible", "FOV Circle", false, { 1, 1, 1, 1 }),
            cb("aimbot_fov_fill", "FOV Fill", false, { 1, 1, 1, 0.08 }, "aimbot_fov_visible"),
            combo("aimbot_fov_style", "FOV Style", FOV_STYLES, 0, "aimbot_fov_visible"),
            cb("aimbot_target_line", "Target Line", false, { 1, 0, 0, 1 }),
            combo("target_line_style", "Line Style", LINE_STYLES, 0, "aimbot_target_line"),
            combo("target_line_endpoint", "Line Endpoint", ENDPOINTS, 5, "aimbot_target_line"),
        },
    }

    local silent = {
        title = "Silent Aim",
        master = SIL,
        items = {
            kb(SIL, "Enable Silent Aim", false),
            sep(),
            label("Targeting", false),
            combo("silent_target_type", "Target Type", { "Crosshair", "Distance" }, 0),
            combo("silent_bone", "Hitbox", BONE_OPTS, 0),
            sl("silent_fov", "Field Of View", 1, 500, 150),
            sl("silent_max_dist", "Max Distance", 1, 500, 250),
            sep(),
            label("Options", false),
            cb("silent_sticky", "Sticky Aim", false),
            cb("silent_filter_visible", "Visibility Check", false),
            combo("vis_check_priority", "Vis Priority", { "Distance", "Crosshair" }, 0, "silent_filter_visible"),
            cb("silent_filter_team", "Team Check", false),
            cb("silent_filter_health", "Health Check", false),
            cb("silent_hitscan", "Hitscan", false),
            sep(),
            label("Gadget Aim", false),
            cb("silent_gadget_aim", "Gadget Aim", false),
            cb("silent_players_priority", "Players Over Gadgets", false, nil, "silent_gadget_aim"),
            sl("silent_gadget_max_distance", "Gadget Max Distance", 1, 250, 75, false, "silent_gadget_aim"),
            cb("silent_gadget_team_check", "Gadget Team Check", false, nil, "silent_gadget_aim"),
            sep(),
            label("Visuals", false),
            cb("silent_draw_fov", "FOV Circle", false, { 0.55, 0.2, 1, 1 }),
            cb("silent_fov_fill", "FOV Fill", false, { 0.55, 0.2, 1, 0.08 }, "silent_draw_fov"),
            combo("silent_fov_style", "FOV Style", FOV_STYLES, 0, "silent_draw_fov"),
            cb("silent_target_line", "Target Line", false, { 1, 0.25, 0.25, 1 }),
            combo("silent_target_line_style", "Line Style", LINE_STYLES, 0, "silent_target_line"),
            combo("silent_target_line_endpoint", "Line Endpoint", ENDPOINTS, 5, "silent_target_line"),
        },
    }

    return { aim, silent }
end

local function build_players()
    local P = "players_enabled"
    return {
        {
            title = "ESP",
            master = P,
            items = {
                kb(P, "Enable Player Visuals", false, nil, { 1, 1, 1, 1 }),
                sep(),
                label("Box", false),
                cb("players_box", "Player Box", true),
                combo("box_type", "Box Type", BOX_TYPES, 0, "players_box"),
                cb("box_fill", "Box Fill", false, nil, "players_box"),
                sl("box_fill_opacity", "Fill Opacity", 0, 100, 25, false, "box_fill"),
                color("box_fill_color", "Fill Color", { 1, 1, 1, 0.3 }, "box_fill"),
                sep(),
                label("Info", false),
                cb("players_name", "Name", false, { 1, 1, 1, 1 }),
                cb("players_weapon", "Weapon", false, { 1, 0.5, 0.2, 1 }),
                cb("players_distance", "Distance", false, { 0.7, 0.7, 0.7, 1 }),
                cb("players_healthbar", "Health Bar", false),
                cb("players_team", "Show Teammates", false),
            },
        },
        {
            title = "Extras",
            master = P,
            items = {
                -- Master lives in ESP column; this column only appears when ESP is on.
                label("Extras", false),
                cb("players_skeleton", "Skeleton", false, { 1, 0.8, 0.2, 1 }),
                cb("players_head_dot", "Head Dot", false, { 1, 0.8, 0.2, 1 }),
                cb("players_view_line", "View Line", false, { 1, 0.8, 0.2, 1 }),
                sl("view_line_length", "View Line Length", 1, 10, 5, false, "players_view_line"),
                combo("view_line_style", "View Line Style", VIEW_STYLES, 0, "players_view_line"),
                cb("players_tracers", "Tracers", false, { 1, 1, 1, 1 }),
                combo("tracer_origin", "Tracer Origin", TRACER_ORIGINS, 0, "players_tracers"),
                combo("tracer_style", "Tracer Style", TRACER_STYLES, 0, "players_tracers"),
                sep(),
                label("Overrides", false),
                cb("players_visible_override", "Visible Color Override", false, { 0, 1, 0.3, 1 }),
                cb("players_target_override", "Target Color Override", false, { 1, 0.2, 0.2, 1 }),
            },
        },
    }
end

local function build_world()
    local W = "world_enabled"
    return {
        {
            title = "World",
            master = W,
            items = {
                kb(W, "Enable World Visuals", false),
                sep(),
                cb("world_team_check", "Gadget Team Check", false),
                multi("world_display_options", "Display Options", { "Text", "Distance", "3D Box" }, { false, false, false }),
                sl("world_max_distance", "Max Distance", 1, 500, 250),
                sep(),
                label("Gadget Aim Blacklist", false),
                multi("gadget_aim_blacklist", "Blacklist", GADGET_BLACKLIST, {
                    false, false, false, false, false, false, false, false, false, false,
                    false, false, false, false, false, false, false,
                }),
            },
        },
        {
            title = "Gadgets",
            master = W,
            items = {
                label("Show Gadgets", false),
                cb("bomb_enabled", "Bomb", false, { 1, 0.2, 0.2, 1 }),
                cb("defuser_enabled", "Defuser", false, { 0.2, 0.8, 1, 1 }),
                cb("claymore_enabled", "Claymore", false, { 1, 0.5, 0, 1 }),
                cb("drone_enabled", "Drone", false, { 0.5, 1, 0.5, 1 }),
                cb("default_camera_enabled", "Map Cameras", false, { 0.8, 0.8, 1, 1 }),
                cb("stun_grenade_enabled", "Flash / Stun", false, { 1, 1, 0, 1 }),
                cb("breach_charge_enabled", "Breach Charge", false, { 1, 0.4, 0.4, 1 }),
                cb("remotec4_enabled", "Remote C4", false, { 1, 0.2, 0.2, 1 }),
                cb("fraggrenade_enabled", "Frag Grenade", false, { 1, 0.6, 0.2, 1 }),
                cb("stickycamera_enabled", "Sticky Cameras", false, { 0.5, 0.5, 1, 1 }),
                cb("signaldisruptor_enabled", "Signal Disruptor", false, { 0.6, 0.3, 0.9, 1 }),
                cb("hardbreachcharge_enabled", "Hard Breach", false, { 1, 0.3, 0.1, 1 }),
                cb("proximityalarm_enabled", "Proximity Alarm", false, { 1, 0.8, 0, 1 }),
                cb("barbedwire_enabled", "Barbed Wire", false, { 0.6, 0.6, 0.6, 1 }),
                cb("incendiarygrenade_enabled", "Incendiary Grenade", false, { 1, 0.4, 0, 1 }),
                cb("bulletproofcamera_enabled", "BP Cameras", false, { 0.3, 0.7, 1, 1 }),
                cb("deployableshield_enabled", "Deployable Shield", false, { 0.4, 0.4, 0.8, 1 }),
                cb("smoke_grenade_enabled", "Smoke Grenade", false, { 0.7, 0.7, 0.7, 1 }),
                cb("emp_grenade_enabled", "EMP Grenade", false, { 0.4, 0.8, 1, 1 }),
                cb("impact_grenade_enabled", "Impact Grenade", false, { 1, 0.5, 0.3, 1 }),
                cb("thermite_charge_enabled", "Thermite Charge", false, { 1, 0.35, 0.1, 1 }),
                cb("incendiary_canister_enabled", "Incendiary Canister", false, { 1, 0.45, 0.1, 1 }),
                cb("shock_battery_enabled", "Shock Battery", false, { 0.3, 0.9, 1, 1 }),
                cb("needle_mine_enabled", "Needle Mine", false, { 0.9, 0.2, 0.9, 1 }),
                cb("toxic_charge_enabled", "Toxic Charge", false, { 0.2, 0.9, 0.3, 1 }),
                cb("metal_barricade_enabled", "Metal Barricade", false, { 0.55, 0.55, 0.55, 1 }),
            },
        },
    }
end

local function build_main()
    local COL = "june_ui_custom_colors"
    local ANM = "june_ui_custom_anim"
    local ELS = "june_ui_per_element"
    local XH = "crosshair_enabled"
    return {
        {
            title = "Overlay",
            items = {
                label("Fonts", false),
                sl("font_size_name", "Name Font Size", 8, 24, 14),
                sl("font_size_weapon", "Weapon Font Size", 8, 24, 12),
                sl("font_size_distance", "Distance Font Size", 8, 24, 12),
                sl("font_size_world", "World Item Font Size", 8, 24, 14),
                sep(),
                cb("keybind_window_enabled", "Enable Keybind List", false),
                sep(),
                cb(XH, "Crosshair", false, { 1, 1, 1, 1 }),
                combo("crosshair_style", "Crosshair Style", CROSS_STYLES, 0, XH),
                sl("crosshair_size", "Crosshair Size", 2, 30, 8, false, XH),
                sl("crosshair_gap", "Crosshair Gap", 0, 20, 3, false, XH),
            },
        },
        {
            title = "Menu",
            items = {
                hk("june_ui_menu_key", "Menu Toggle Key", nil, 0x2D),
                cb("june_ui_show_cursor_dot", "Show Cursor Dot", true),
                sep(),
                cb(COL, "Color Options", false),
                label("Colors", false, COL),
                color("june_ui_accent", "Accent", ACCENT, COL),
                sl("june_ui_bg_dim", "Background Dim", 0, 40, 0, false, COL),
                cb("june_ui_menu_fade", "Menu Fade Pulse", false, nil, COL),
                multi("june_ui_color_overrides", "Override Colors For", {
                    "Title Bar", "Section Tops", "Sliders", "Scrollbars", "Sidebar", "Checkboxes", "Overlay Panels",
                }, {}, COL),
                color("june_ui_col_title", "Title Bar Color", ACCENT, COL, 1),
                color("june_ui_col_section", "Section Top Color", ACCENT, COL, 2),
                color("june_ui_col_slider", "Slider Color", ACCENT, COL, 3),
                color("june_ui_col_scroll", "Scrollbar Color", ACCENT, COL, 4),
                color("june_ui_col_sidebar", "Sidebar Color", ACCENT, COL, 5),
                color("june_ui_col_checkbox", "Checkbox Color", ACCENT, COL, 6),
                color("june_ui_col_overlay", "Overlay Panel Color", ACCENT, COL, 7),
                sep(),
                cb(ANM, "Animation Options", false),
                label("Animation", false, ANM),
                combo("june_ui_accent_anim", "Style", ANIM_MODES, 1, ANM),
                sl("june_ui_anim_speed", "Speed", 1, 100, 40, false, ANM),
                multi("june_ui_anim_targets", "Animate", {
                    "Title Bar", "Section Tops", "Sliders", "Scrollbars", "Sidebar", "Checkboxes", "Hover", "Overlay Panels",
                }, { true, true, true, true, true, true, true, true }, ANM),
                cb(ELS, "Individual Styles", false, nil, ANM),
                combo("june_ui_style_title", "Title Bar", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_section", "Section Tops", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_slider", "Sliders", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_scroll", "Scrollbars", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_sidebar", "Sidebar", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_checkbox", "Checkboxes", ELEM_MODES, 0, ANM, ELS),
                combo("june_ui_style_overlay", "Overlay Panels", ELEM_MODES, 0, ANM, ELS),
            },
        },
    }
end

local function build_config()
    return {
        {
            title = "Config",
            items = {
                label("Profiles", false),
                input("config_name_input", "Config Name", "default"),
                btn("save_cfg_btn", "Save Config"),
                btn("load_cfg_btn", "Load Config"),
                sep(),
                cb("config_autoload_enabled", "Save as Autoload", false),
                label("Files: %LOCALAPPDATA%\\Project Vector\\Scripts", true),
            },
        },
    }
end

function M.groups_for(tab_id)
    if tab_id == "aimbot" then return build_aimbot() end
    if tab_id == "players" then return build_players() end
    if tab_id == "world" then return build_world() end
    if tab_id == "main" then return build_main() end
    if tab_id == "config" then return build_config() end
    return {}
end

return M

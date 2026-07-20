--[[
  Replaces Vector's menu.* API with a store backed by ui.gs_state.
  Feature register_menu() code keeps working; nothing is added to the Vector UI.
]]

local state = June.require("ui.gs_state")

local M = {}
M.installed = false
M._real = nil

local function as_bool_default(default)
    return default == true
end

local shim = {}

function shim.add_tab() end
function shim.add_group() end
function shim.add_separator() end
function shim.add_label() end

function shim.add_checkbox(_T, _G, id, _label, default, opts)
    state.define(id, as_bool_default(default))
    opts = opts or {}
    if opts.colorpicker then
        state.define_color(id, opts.colorpicker)
    end
    if opts.key and opts.key ~= 0 then
        if state.get_key(id) == 0 then
            state.set_key(id, opts.key)
        end
    end
end

function shim.add_slider_int(_T, _G, id, _label, _min, _max, default, _opts)
    -- Some call sites pass format string as 8th arg then opts
    state.define(id, tonumber(default) or 0)
end

function shim.add_slider_float(_T, _G, id, _label, _min, _max, default, _fmt, _opts)
    state.define(id, tonumber(default) or 0)
end

function shim.add_combo(_T, _G, id, _label, _options, default, _opts)
    state.define(id, tonumber(default) or 0)
end

function shim.add_multicombo(_T, _G, id, _label, options, defaults, _opts)
    local def = {}
    local n = type(options) == "table" and #options or 0
    for i = 1, n do
        def[i] = defaults and defaults[i] == true
    end
    state.define(id, def)
end

function shim.add_colorpicker(_T, _G, id, _label, default, _opts)
    state.define_color(id, default or { 1, 1, 1, 1 })
    -- Also mirror as value for config dumps that read get()
    state.define(id, default or { 1, 1, 1, 1 })
end

function shim.add_input(_T, _G, id, _label, default)
    state.define(id, default or "")
end

function shim.add_button(_T, _G, id, _label, callback)
    if type(callback) == "function" then
        state.set_button(id, callback)
    end
end

function shim.add_hotkey(_T, _G, id, _label, default_vk, opts)
    opts = opts or {}
    if default_vk and default_vk ~= 0 and state.get_key(id) == 0 then
        state.set_key(id, default_vk)
    end
    local mode_id = id .. "_mode"
    state.define(mode_id, opts.default_mode or opts.mode_default or 1)
end

function shim.get(id)
    return state.get(id, nil)
end

function shim.set(id, value)
    state.set(id, value)
end

function shim.get_color(id)
    return state.get_color(id, nil)
end

function shim.set_color(id, color)
    state.set_color(id, color)
end

function shim.get_key(id)
    return state.get_key(id)
end

function shim.set_key(id, vk)
    state.set_key(id, vk)
end

function shim.set_callback(id, fn)
    state.set_menu_callback(id, fn)
end

function shim.set_visible(id, show)
    state.set_visible(id, show)
end

-- PascalCase / camelCase aliases (Vector registers all three styles)
local aliases = {
    AddTab = "add_tab",
    AddGroup = "add_group",
    AddSeparator = "add_separator",
    AddLabel = "add_label",
    AddCheckbox = "add_checkbox",
    AddSliderInt = "add_slider_int",
    AddSliderFloat = "add_slider_float",
    AddCombo = "add_combo",
    AddMulticombo = "add_multicombo",
    AddColorpicker = "add_colorpicker",
    AddInput = "add_input",
    AddButton = "add_button",
    AddHotkey = "add_hotkey",
    Get = "get",
    Set = "set",
    GetColor = "get_color",
    SetColor = "set_color",
    GetKey = "get_key",
    SetKey = "set_key",
    SetCallback = "set_callback",
    SetVisible = "set_visible",
    addTab = "add_tab",
    addGroup = "add_group",
    addCheckbox = "add_checkbox",
    addSliderInt = "add_slider_int",
    addSliderFloat = "add_slider_float",
    addCombo = "add_combo",
    addMulticombo = "add_multicombo",
    addColorpicker = "add_colorpicker",
    addInput = "add_input",
    addButton = "add_button",
    addHotkey = "add_hotkey",
    getColor = "get_color",
    setColor = "set_color",
    getKey = "get_key",
    setKey = "set_key",
    setCallback = "set_callback",
    setVisible = "set_visible",
}

for alias, real in pairs(aliases) do
    shim[alias] = shim[real]
end

function M.install()
    if M.installed then return true end
    -- Vector sandbox has no rawget; keep a reference then replace the global.
    M._real = menu
    if June then
        June._vector_menu = M._real
        June.custom_ui = true
    end
    menu = shim
    M.installed = true
    return true
end

function M.api()
    return shim
end

return M

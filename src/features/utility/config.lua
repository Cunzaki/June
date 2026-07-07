local menu_defs = June.require("menu.menu_defs")
local menu_util = June.require("core.menu_util")

local M = {}
local menu_items = menu_defs.menu_items

local AUTOLOAD_FILE = 'JuneAutoload.txt'

local function cfg_path(name)
    if not name or name == '' then name = 'default' end
    if not name:lower():find('[.]') then
        name = name .. '.txt'
    end
    return name
end

local function save_cfg(name)
    local cfg_name = name or menu.get('config_name_input') or 'default'
    local path = cfg_path(cfg_name)
    local f = io.open(path, 'w')
    if not f then
        print('[June] Save failed - could not open: ' .. path)
        return false
    end
    for _, m in ipairs(menu_items) do
        if not m.id then
            goto continue
        end
        if m.t == 'checkbox' then
            local v = menu.get(m.id)
            if v ~= nil then
                f:write(m.id .. '=' .. (v and '1' or '0') .. '\n')
            end
        elseif m.t == 'slider_int' or m.t == 'slider_float' or m.t == 'combo' then
            local v = menu.get(m.id)
            if v ~= nil then f:write(m.id .. '=' .. tostring(v) .. '\n') end
        elseif m.t == 'multicombo' then
            local v = menu.get(m.id)
            if v then
                local parts = {}
                for i, val in ipairs(v) do parts[i] = val and '1' or '0' end
                f:write(m.id .. '=' .. table.concat(parts, ',') .. '\n')
            end
        elseif m.t == 'hotkey' then
            local k = menu.get_key(m.id)
            if k then f:write(m.id .. '=' .. tostring(k) .. '\n') end
        elseif m.t == 'colorpicker' then
            local c = menu.get_color(m.id)
            if c and #c >= 4 then
                f:write(string.format('%s=%.4f,%.4f,%.4f,%.4f\n', m.id, c[1], c[2], c[3], c[4]))
            end
        end
        -- Inline colorpicker attached to a non-colorpicker item
        if m.c and m.t ~= 'colorpicker' then
            local c = menu.get_color(m.id)
            if c and #c >= 4 then
                f:write(string.format('%s_color=%.4f,%.4f,%.4f,%.4f\n', m.id, c[1], c[2], c[3], c[4]))
            end
        end
        ::continue::
    end
    f:close()
    -- Always write autoload marker
    local af = io.open(AUTOLOAD_FILE, 'w')
    if af then af:write(cfg_name) af:close() end
    print('[June] Config saved: ' .. path)
    return true
end

local function load_cfg(name)
    local cfg_name = name or menu.get('config_name_input') or 'default'
    local path = cfg_path(cfg_name)
    local f = io.open(path, 'r')
    if not f then
        -- Silently fail if file doesn't exist (normal on first run)
        return false
    end
    local data = {}
    for line in f:lines() do
        local k, v = line:match('^([^=]+)=(.-)%s*$')
        if k then data[k] = v end
    end
    f:close()
    local count = 0
    for _, m in ipairs(menu_items) do
        if not m.id then
            goto continue
        end
        if data[m.id] ~= nil then
            if m.t == 'checkbox' then
                menu.set(m.id, data[m.id] == '1')
                count = count + 1
            elseif m.t == 'slider_int' or m.t == 'slider_float' then
                local n = tonumber(data[m.id])
                if n then menu.set(m.id, n) count = count + 1 end
            elseif m.t == 'combo' then
                local n = tonumber(data[m.id])
                if n then menu.set(m.id, n) count = count + 1 end
            elseif m.t == 'multicombo' then
                local vals = {}
                for val in data[m.id]:gmatch('[^,]+') do
                    vals[#vals+1] = val == '1'
                end
                menu.set(m.id, vals)
                count = count + 1
            elseif m.t == 'hotkey' then
                local k = tonumber(data[m.id])
                if k then menu.set_key(m.id, k) count = count + 1 end
            elseif m.t == 'colorpicker' then
                local r,g,b,a = data[m.id]:match('([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)')
                if r then
                    menu.set_color(m.id, {tonumber(r),tonumber(g),tonumber(b),tonumber(a)})
                    count = count + 1
                end
            end
        end
        -- Inline colorpicker
        if m.c and m.t ~= 'colorpicker' then
            local ckey = m.id .. '_color'
            if data[ckey] then
                local r,g,b,a = data[ckey]:match('([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)')
                if r then
                    menu.set_color(m.id, {tonumber(r),tonumber(g),tonumber(b),tonumber(a)})
                end
            end
        end
        ::continue::
    end
    if count > 0 then
        print('[June] Config loaded: ' .. path .. ' (' .. count .. ' values)')
    end
    return true
end

function M.register_menu()
    menu_util.ensure_groups()
    menu.add_separator(menu_util.TAB, menu_util.G.SETTINGS)
    menu.add_label(menu_util.TAB, menu_util.G.SETTINGS, "Config")
    menu.add_input(menu_util.TAB, menu_util.G.SETTINGS, "config_name_input", "Config Name", "default")
    menu.add_button(menu_util.TAB, menu_util.G.SETTINGS, "save_cfg_btn", "Save Config", function()
        save_cfg(menu.get("config_name_input"))
    end)
    menu.add_button(menu_util.TAB, menu_util.G.SETTINGS, "load_cfg_btn", "Load Config", function()
        load_cfg(menu.get("config_name_input"))
    end)
    menu.add_label(menu_util.TAB, menu_util.G.SETTINGS, "Configs: %LOCALAPPDATA%\\Project Vector\\Scripts")
    menu.add_checkbox(menu_util.TAB, menu_util.G.SETTINGS, "config_autoload_enabled", "Save as Autoload", false)
end

function M.autoload()
    -- Autoload on startup: try JuneAutoload.txt first, then fallback to default
    local _af = io.open(AUTOLOAD_FILE, 'r')
    if _af then
        local _aname = _af:read('*l')
        _af:close()
        if _aname and _aname ~= '' then
            if load_cfg(_aname) then
                menu.set('config_name_input', _aname)
            end
        end
    else
        load_cfg('default')
    end
end

M.save_cfg = save_cfg
M.load_cfg = load_cfg

return M

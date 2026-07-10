local menu_defs = June.require("menu.menu_defs")
local world_items = June.require("game.world_items")

local M = {}
M.s = {}

local _callbacks = {}

function M.on_change(id, fn)
    if not id or not fn then
        return
    end
    _callbacks[id] = _callbacks[id] or {}
    _callbacks[id][#_callbacks[id] + 1] = fn
    if menu and menu.set_callback then
        menu.set_callback(id, function(new_val)
            for _, cb in ipairs(_callbacks[id] or {}) do
                pcall(cb, new_val)
            end
        end)
    end
end

function M.get(id, default)
    if menu and menu.get then
        local v = menu.get(id)
        if v ~= nil then
            return v
        end
    end
    if M.s[id] ~= nil then
        return M.s[id]
    end
    return default
end

function M.enabled(id)
    local v = M.get(id)
    if v == nil or v == false or v == 0 or v == "false" then
        return false
    end
    return v == true or v == 1
end

function M.num(id, default)
    return tonumber(M.get(id, default)) or default or 0
end

function M.combo_index(id, labels, default)
    default = default or 0
    local v = M.get(id, default)
    if type(v) == "string" then
        local lower = v:lower()
        for i, label in ipairs(labels or {}) do
            if label:lower() == lower then
                return i - 1
            end
        end
        return default
    end
    local n = tonumber(v)
    if n == nil then
        return default
    end
    if labels and #labels > 0 then
        if n < 0 then
            return default
        end
        if n >= #labels then
            return #labels - 1
        end
    end
    return n
end

function M.sync_settings()
    local s = M.s
    local menu_items = menu_defs.menu_items
    for _, m in ipairs(menu_items) do
        if not m.id then
            goto continue
        end
        if m.t == "colorpicker" then
            s[m.id] = menu.get(m.id)
        else
            s[m.id] = menu.get(m.id)
            if m.c then
                s[m.id .. "_color"] = menu.get_color(m.id)
            end
        end
        ::continue::
    end
    for _, item in ipairs(world_items.world_items) do
        s[item.enabled .. "_color"] = menu.get_color(item.enabled)
    end
end

return M

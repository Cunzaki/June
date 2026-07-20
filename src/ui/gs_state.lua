-- Shared settings store for the custom UI (backs menu shim + settings reads).
local M = {}

M.values = {}
M.defaults = {}
M.colors = {}
M.keys = {}
M.callbacks = {}
M.menu_callback = {} -- id -> single fn (menu.set_callback replaces)
M.buttons = {}
M.visible = {} -- id -> bool (parent gating); nil means visible

local function copy_table(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

function M.define(id, default)
    if id == nil then return end
    if M.defaults[id] == nil then
        M.defaults[id] = copy_table(default)
    end
    if M.values[id] == nil then
        M.values[id] = copy_table(default)
    end
end

function M.get(id, fallback)
    local v = M.values[id]
    if v == nil then
        return fallback
    end
    return v
end

local function fire_change(id, value)
    local menu_cb = M.menu_callback[id]
    if menu_cb then
        pcall(menu_cb, value)
    end
    local cbs = M.callbacks[id]
    if cbs then
        for i = 1, #cbs do
            pcall(cbs[i], value)
        end
    end
end

function M.set(id, value)
    if id == nil then return end
    M.values[id] = value
    fire_change(id, value)
end

function M.toggle(id)
    local v = not M.get(id, false)
    M.set(id, v)
    return v
end

function M.define_color(id, color)
    if id == nil then return end
    if M.colors[id] == nil then
        M.colors[id] = copy_table(color or { 1, 1, 1, 1 })
    end
end

function M.get_color(id, fallback)
    return M.colors[id] or fallback or { 1, 1, 1, 1 }
end

function M.set_color(id, color)
    if id == nil or type(color) ~= "table" then return end
    M.colors[id] = copy_table(color)
    fire_change(id, color)
end

function M.get_key(id)
    return tonumber(M.keys[id]) or 0
end

function M.set_key(id, vk)
    if id == nil then return end
    M.keys[id] = tonumber(vk) or 0
end

function M.on_change(id, fn)
    if not id or not fn then return end
    M.callbacks[id] = M.callbacks[id] or {}
    M.callbacks[id][#M.callbacks[id] + 1] = fn
end

function M.set_menu_callback(id, fn)
    if id then
        M.menu_callback[id] = fn
    end
end

function M.set_button(id, fn)
    if id then
        M.buttons[id] = fn
    end
end

function M.fire_button(id)
    local fn = M.buttons[id]
    if fn then
        pcall(fn)
        return true
    end
    return false
end

function M.set_visible(id, show)
    if id then
        M.visible[id] = show and true or false
    end
end

function M.is_visible(id)
    local v = M.visible[id]
    if v == nil then return true end
    return v
end

function M.reset(id)
    local d = M.defaults[id]
    if d == nil then return end
    M.set(id, copy_table(d))
end

return M

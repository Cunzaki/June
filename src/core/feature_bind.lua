-- Always / Hold / Toggle for feature master checkboxes with attached keys.
local settings = June.require("core.settings")

local M = {}

M.MODES = { "Always", "Hold", "Toggle" }

local registry = {}
local last_down = {}

function M.register(spec)
    if not spec or not spec.id then return end
    local mode_id = spec.mode_id or (spec.id .. "_mode")
    registry[spec.id] = {
        id = spec.id,
        label = spec.label or spec.id,
        mode_id = mode_id,
        key_id = spec.key_id or spec.id,
    }
    if menu and menu.set then
        -- ensure mode value exists
        local cur = settings.get(mode_id, nil)
        if cur == nil then
            pcall(menu.set, mode_id, 2) -- default Toggle
        end
    end
end

function M.is_registered(id)
    return registry[id] ~= nil
end

function M.get_key(id)
    local e = registry[id]
    local key_id = e and e.key_id or id
    if menu and menu.get_key then
        local k = menu.get_key(key_id)
        if k and k > 0 then return k end
    end
    local ok, gs = pcall(function()
        return June.require("ui.gs_state")
    end)
    if ok and gs then
        local k = gs.get_key(key_id)
        if k and k > 0 then return k end
    end
    return 0
end

function M.mode_index(id)
    local e = registry[id]
    if not e then return 2 end
    return settings.combo_index(e.mode_id, M.MODES, 2)
end

function M.armed(id)
    return settings.bool(id, false)
end

function M.active(id)
    if not registry[id] then
        return settings.bool(id, false)
    end
    local mode = M.mode_index(id)
    if mode == 1 then -- Hold
        if not M.armed(id) then return false end
        local key = M.get_key(id)
        if key <= 0 then return false end
        return input and input.is_key_down and input.is_key_down(key)
    end
    return M.armed(id)
end

function M.tick()
    if not input or not input.is_key_down then return end

    for id in pairs(registry) do
        local mode = M.mode_index(id)
        local key = M.get_key(id)

        if mode == 0 or mode == 1 then
            if key > 0 then
                last_down[id] = input.is_key_down(key)
            end
        elseif key > 0 then
            local down = input.is_key_down(key)
            if down and not last_down[id] then
                local cur = settings.bool(id, false)
                if menu and menu.set then
                    pcall(menu.set, id, not cur)
                end
            end
            last_down[id] = down
        end
    end
end

return M

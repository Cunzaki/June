-- Aim-key state (Always / Hold / Toggle) separate from feature master toggle.
local settings = June.require("core.settings")

local M = {}

M.MODES = { "Always", "Hold", "Toggle" }

local toggled = {}
local last_down = {}

local function key_store()
    return June.require("ui.gs_state")
end

function M.mode_index(mode_id)
    return settings.combo_index(mode_id, M.MODES, 1) -- default Hold
end

function M.tick(key_id, mode_id)
    if not input or not input.is_key_down then return end
    local mode = M.mode_index(mode_id)
    local vk = key_store().get_key(key_id)
    if mode == 0 then
        if vk > 0 then last_down[key_id] = input.is_key_down(vk) end
        return
    end
    if vk <= 0 then return end
    local down = input.is_key_down(vk)
    if mode == 1 then
        last_down[key_id] = down
        return
    end
    if down and not last_down[key_id] then
        toggled[key_id] = not (toggled[key_id] == true)
    end
    last_down[key_id] = down
end

function M.active(key_id, mode_id)
    local mode = M.mode_index(mode_id)
    if mode == 0 then return true end
    local vk = key_store().get_key(key_id)
    if vk <= 0 then return mode == 0 end
    if mode == 1 then
        return input and input.is_key_down and input.is_key_down(vk)
    end
    return toggled[key_id] == true
end

function M.reset(key_id)
    toggled[key_id] = false
    last_down[key_id] = false
end

return M

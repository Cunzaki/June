local tabs = June.require("menu.tabs")
local debug = June.require("core.debug")
local custom_menu = June.require("ui.custom_menu")

local M = {}
local initialized = false

function M.init()
    if initialized then return true end
    initialized = tabs.init()
    if initialized then
        pcall(custom_menu.init)
        pcall(function()
            local fb = June.require("core.feature_bind")
            fb.register({ id = "aimbot_enabled", label = "Aimbot", key_id = "aimbot_enabled" })
            fb.register({ id = "silent_aim_enabled", label = "Silent Aim", key_id = "silent_aim_enabled" })
            fb.register({ id = "players_enabled", label = "Players", key_id = "players_enabled" })
            fb.register({ id = "world_enabled", label = "World", key_id = "world_enabled" })
        end)
    end
    return initialized
end

function M.on_frame()
    if not initialized then return end
    debug.tick_frame()

    pcall(function()
        June.require("core.feature_bind").tick()
    end)
    pcall(function()
        June.require("core.aim_key").tick("aimbot_key", "aimbot_key_mode")
    end)

    local dt = 0.016
    if utility and utility.get_delta_time then
        dt = utility.get_delta_time()
    end

    debug.guard("tabs.update", tabs.update, dt)
    debug.guard("tabs.draw", tabs.draw)
    debug.guard("custom_menu.draw", custom_menu.draw)
end

return M

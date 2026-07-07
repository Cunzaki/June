local settings = OperationOne.require("core.settings")

local M = {}
local s = settings.s

local function draw_keybind_window()
    if not s.keybind_window_enabled then
        return
    end
    local itms = {}
    if s.aimbot_enabled then
        itms[#itms + 1] = "Aimbot Key: " .. (input.is_key_down(menu.get_key("aimbot_key")) and "ON" or "OFF")
    end
    if s.utilities_aimbot and s.aimbot_enabled then
        itms[#itms + 1] = "Utilities Aimbot: ON"
    end
    if s.players_enabled then
        itms[#itms + 1] = "Player ESP: ON"
    end
    if s.world_enabled then
        itms[#itms + 1] = "World ESP: ON"
    end
    if s.silent_aim_enabled then
        itms[#itms + 1] = "Silent Aim: ON"
    end
    if #itms > 0 then
        draw.window(1500, 200, "keybind_list", " KEYBINDS ", itms)
    end
end

M.draw_keybind_window = draw_keybind_window

return M

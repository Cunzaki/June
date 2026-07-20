-- Mouse / key helpers. Raw cursor only - no windowed offset correction.
--
-- Wheel: Vector docs only expose utility.mouse_scroll() (inject). There is no
-- documented reader. We probe every known path and accumulate into M.wheel;
-- if none work, the menu keeps edge-hover scroll as fallback.

local M = {}

local prev_keys = {}
local prev_lmb = false
local prev_rmb = false
local prev_mmb = false

M.mx = 0
M.my = 0
M.raw_mx = 0
M.raw_my = 0
M.lmb = false
M.rmb = false
M.mmb = false
M.lmb_click = false
M.rmb_click = false
M.mmb_click = false
M.lmb_release = false
M.wheel = 0
M.wheel_source = nil -- "api" | "uis" | "mouse" | nil
M._wheel_accum = 0
M._scroll_ready = false
M._scroll_hook_tries = 0
M._api_readers = nil
M._game_cursor_hidden = false
M._menu_open = false
M.ui_x, M.ui_y, M.ui_w, M.ui_h = 0, 0, 0, 0

function M.set_ui_rect(x, y, w, h)
    M.ui_x, M.ui_y, M.ui_w, M.ui_h = x, y, w, h
end

function M.set_menu_open(open)
    M._menu_open = open == true
    M.set_game_cursor_visible(not M._menu_open)
end

local function pcall_get_service(name)
    local svc = nil
    if not game then return nil end
    pcall(function()
        if game.GetService then svc = game:GetService(name) end
    end)
    if not svc then
        pcall(function()
            if game.get_service then svc = game:get_service(name) end
        end)
    end
    return svc
end

local function on_wheel(dir, source)
    dir = tonumber(dir) or 0
    if dir == 0 then return end
    -- Normalize to ±1 notches (UIS Position.Z is often ±1).
    if dir > 0 then dir = 1 elseif dir < 0 then dir = -1 end
    M._wheel_accum = (M._wheel_accum or 0) + dir
    if source then M.wheel_source = source end
end

local function connect_signal(signal, fn)
    if not signal then return false end
    local connect = signal.Connect or signal.connect
    if type(connect) ~= "function" then return false end
    local ok = pcall(function()
        connect(signal, fn)
    end)
    return ok == true
end

local function collect_api_readers()
    if M._api_readers then return M._api_readers end
    local readers = {}
    local skip = {
        mouse_scroll = true,
        MouseScroll = true,
        mouseScroll = true,
    }
    local function scan(tbl, label)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "function" and type(k) == "string" then
                local name = k:lower()
                if (name:find("wheel", 1, true) or name:find("scroll", 1, true))
                    and not skip[k]
                    and not name:find("set", 1, true)
                    and not name:find("mouse_scroll", 1, true)
                then
                    readers[#readers + 1] = { fn = v, label = label .. "." .. k }
                end
            end
        end
    end
    pcall(scan, input, "input")
    pcall(scan, utility, "utility")
    M._api_readers = readers
    return readers
end

local function poll_api_readers()
    local readers = collect_api_readers()
    for i = 1, #readers do
        local ok, a, b = pcall(readers[i].fn)
        if ok then
            local v = tonumber(a)
            if (not v or v == 0) and b ~= nil then v = tonumber(b) end
            if v and v ~= 0 then
                on_wheel(v, "api")
                return
            end
        end
    end
end

local function try_hook_uis()
    local uis = pcall_get_service("UserInputService")
    if not uis then return false end

    local function handle(input_obj, _game_processed)
        if not input_obj then return end
        local type_name = nil
        pcall(function()
            local t = input_obj.UserInputType or input_obj.user_input_type
            if type(t) == "userdata" or type(t) == "table" then
                type_name = tostring(t.Name or t.name or t)
            else
                type_name = tostring(t)
            end
        end)
        if not type_name then return end
        local lower = type_name:lower()
        if not lower:find("mousewheel", 1, true) and lower ~= "mousewheel" then
            return
        end
        local z = 0
        pcall(function()
            local pos = input_obj.Position or input_obj.position
            if pos then z = pos.Z or pos.z or 0 end
        end)
        if z == 0 then
            pcall(function()
                z = input_obj.Delta and (input_obj.Delta.Z or input_obj.Delta.z) or 0
            end)
        end
        if z == 0 then z = 1 end
        on_wheel(z, "uis")
    end

    local hooked = false
    if connect_signal(uis.InputChanged or uis.input_changed, handle) then
        hooked = true
    end
    if connect_signal(uis.InputBegan or uis.input_began, handle) then
        hooked = true
    end
    return hooked
end

local function try_hook_player_mouse()
    local lp = nil
    pcall(function()
        if entity and entity.get_local_player then
            lp = entity.get_local_player()
        end
    end)
    if not lp then
        pcall(function()
            lp = game and (game.LocalPlayer or game.local_player)
        end)
    end
    if not lp then return false end

    local mouse = nil
    pcall(function()
        if lp.GetMouse then mouse = lp:GetMouse()
        elseif lp.get_mouse then mouse = lp:get_mouse()
        else mouse = lp.Mouse or lp.mouse
        end
    end)
    if not mouse then return false end

    local hooked = false
    if connect_signal(mouse.WheelForward or mouse.wheel_forward, function()
        on_wheel(1, "mouse")
    end) then
        hooked = true
    end
    if connect_signal(mouse.WheelBackward or mouse.wheel_backward, function()
        on_wheel(-1, "mouse")
    end) then
        hooked = true
    end
    return hooked
end

local function ensure_scroll_hooks()
    if M._scroll_ready then return end
    -- Retry a few frames - LocalPlayer / services may not exist at load.
    M._scroll_hook_tries = (M._scroll_hook_tries or 0) + 1
    if M._scroll_hook_tries > 120 then
        M._scroll_ready = true
        return
    end

    local ok_uis = try_hook_uis()
    local ok_mouse = try_hook_player_mouse()
    collect_api_readers()
    if ok_uis or ok_mouse or M._scroll_hook_tries >= 30 then
        M._scroll_ready = true
    end
end

function M.set_game_cursor_visible(visible)
    local sg = pcall_get_service("StarterGui")
    if sg then
        pcall(function()
            if sg.SetCore then sg:SetCore("MouseIconEnabled", visible) end
        end)
        pcall(function()
            if sg.set_core then sg:set_core("MouseIconEnabled", visible) end
        end)
    end

    local uis = pcall_get_service("UserInputService")
    if uis then
        pcall(function() uis.MouseIconEnabled = visible end)
        pcall(function() uis.mouse_icon_enabled = visible end)
    end

    pcall(function()
        local lp = game and game.local_player
        if not lp then return end
        local mouse = lp.GetMouse and lp:GetMouse() or (lp.get_mouse and lp:get_mouse())
        if not mouse then return end
        if not visible then
            mouse.Icon = "rbxassetid://0"
            if mouse.icon ~= nil then mouse.icon = "rbxassetid://0" end
        else
            mouse.Icon = ""
        end
    end)

    M._game_cursor_hidden = not visible
end

function M.mouse()
    return M.mx, M.my
end

function M.key_down(vk)
    return input and input.is_key_down and input.is_key_down(vk) or false
end

function M.key_pressed(vk)
    local down = M.key_down(vk)
    local was = prev_keys[vk] == true
    prev_keys[vk] = down
    return down and not was
end

function M.begin_frame()
    ensure_scroll_hooks()

    local amx, amy = 0, 0
    if utility and utility.get_mouse_pos then
        amx, amy = utility.get_mouse_pos()
    elseif input and input.get_mouse_pos then
        amx, amy = input.get_mouse_pos()
    elseif input and input.get_mouse_position then
        amx, amy = input.get_mouse_position()
    end
    amx = tonumber(amx) or 0
    amy = tonumber(amy) or 0
    M.raw_mx, M.raw_my = amx, amy
    M.mx, M.my = amx, amy

    M.lmb = M.key_down(0x01)
    M.rmb = M.key_down(0x02)
    M.mmb = M.key_down(0x04)
    M.lmb_click = M.lmb and not prev_lmb
    M.rmb_click = M.rmb and not prev_rmb
    M.mmb_click = M.mmb and not prev_mmb
    M.lmb_release = (not M.lmb) and prev_lmb
    prev_lmb = M.lmb
    prev_rmb = M.rmb
    prev_mmb = M.mmb

    -- Poll any getter-style APIs each frame, then drain event accumulators.
    poll_api_readers()
    M.wheel = M._wheel_accum or 0
    M._wheel_accum = 0
end

function M.hover(x, y, w, h)
    return M.mx >= x and M.my >= y and M.mx <= x + w and M.my <= y + h
end

function M.clicked(x, y, w, h)
    return M.lmb_click and M.hover(x, y, w, h)
end

function M.draw_cursor()
    if not draw then return end
    local show = true
    pcall(function()
        show = June.require("core.settings").bool("june_ui_show_cursor_dot", true)
    end)
    if not show then return end
    local x, y = M.mx, M.my
    local col = { 0.75, 0.15, 0.83, 1 }
    if draw.circle_filled then
        draw.circle_filled(x, y, 4.5, col, 14)
    end
    if draw.circle then
        draw.circle(x, y, 5.5, { 1, 1, 1, 0.9 }, 16, 1.4)
    end
end

return M

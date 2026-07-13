-- Fly / slowfall / speed boost — HRP velocity + physics desync bypass.

local settings = June.require("core.settings")
local env = June.require("core.env")
local move = June.require("core.cframe_move")
local bypass = June.require("core.movement_bypass")

local M = {}

local P_FLY = "june_fly_enabled"
local P_FLY_SPEED = "june_fly_speed"
local P_FLY_NOCLIP = "june_fly_noclip"
local P_SLOWFALL = "june_slowfall_enabled"
local P_SPEED_BOOST = "june_speed_boost_enabled"
local P_SPEED_MULT = "june_speed_boost_mult"
local P_DESYNC = "june_move_desync"

local tracked_char_id = nil
local last_ground_ms = 0
local bypass_active = false

local SPEED_SCALE = 12
local MAX_FLY_SPEED = 48
local VEL_BLEND = 0.22
local GROUND_STATE_MS = 50

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function char_id(char)
    if not char then return nil end
    return char.Address or char.address or tostring(char)
end

local function get_character(lp)
    if lp and lp.character then return lp.character end
    if game and game.local_player and game.local_player.character then
        return game.local_player.character
    end
    return nil
end

local function get_root(lp)
    local char = get_character(lp)
    if not char then return nil end
    return move.find_part(char, "HumanoidRootPart")
end

local function get_humanoid(lp)
    if lp and lp.humanoid and env.is_valid(lp.humanoid) then
        return lp.humanoid
    end
    local char = get_character(lp)
    if not char then return nil end
    return env.safe_call(function()
        if char.find_first_child_of_class then return char:find_first_child_of_class("Humanoid") end
        return char:FindFirstChildOfClass("Humanoid")
    end)
end

local function hum_alive(hum)
    if not hum then return false end
    local hp = hum.Health or hum.health
    if hp == nil then return true end
    return hp > 0
end

local function fly_speed()
    local raw = settings.num(P_FLY_SPEED, 3)
    raw = math.max(2, math.min(4, raw))
    local spd = raw * SPEED_SCALE
    if spd > MAX_FLY_SPEED then spd = MAX_FLY_SPEED end
    return spd
end

local function speed_boost_mult()
    local raw = settings.num(P_SPEED_MULT, 12)
    return 1 + (math.max(0, math.min(30, raw)) / 100)
end

local function movement_active()
    return settings.enabled(P_FLY)
        or settings.enabled(P_SLOWFALL)
        or settings.enabled(P_SPEED_BOOST)
end

local function want_desync()
    if settings.enabled(P_DESYNC) then return true end
    return movement_active()
end

local function sync_bypass(on)
    if not bypass.available() then return end
    if on then
        bypass.tick_movement(true, 0.1)
        bypass_active = true
    elseif bypass_active then
        bypass.tick_movement(false)
        bypass_active = false
    end
end

local function keep_grounded_for_shoot(hum)
    if not hum or not hum_alive(hum) then return end
    local now = tick_ms()
    if now - last_ground_ms < GROUND_STATE_MS then return end
    last_ground_ms = now

    pcall(function() hum.Jump = false end)
    pcall(function()
        if hum.ChangeState then hum:ChangeState(8)
        elseif hum.change_state then hum:change_state(8)
        else move.humanoid_state(hum, 8)
        end
    end)
end

local function tick_fly(root, hum, char, dt)
    if not hum_alive(hum) then return end
    if settings.enabled(P_FLY_NOCLIP) then
        move.set_character_noclip(char, root, true)
    end

    local mx, my, mz = move.read_fly_input()
    move.drive_root_velocity(root, mx, my, mz, fly_speed(), dt, {
        blend = VEL_BLEND,
        max_speed = fly_speed() * 1.05,
        cancel_gravity = true,
    })
    keep_grounded_for_shoot(hum)
end

local function tick_slowfall(root, hum, dt)
    local raw = settings.num("june_slowfall_speed", 5)
    local cap = -(1.2 + (math.max(1, raw) * 0.22))
    local vx, vy, vz = move.read_velocity(root)
    if vy < cap then
        local next_y = vy + (cap - vy) * math.min(1, dt * 8)
        move.set_velocity(root, vx, next_y, vz)
    end
    keep_grounded_for_shoot(hum)
end

local function tick_speed_boost(root, dt)
    if settings.enabled(P_FLY) then return end
    move.boost_ground_velocity(root, speed_boost_mult(), dt)
end

function M.tick(dt)
    dt = dt or move.delta_time()

    local active = movement_active()
    if want_desync() and (active or settings.enabled(P_DESYNC)) then
        sync_bypass(true)
    else
        sync_bypass(false)
    end

    if not active then return end

    local lp = env.get_local_player()
    if not lp then return end

    local char = get_character(lp)
    if not char or not env.is_valid(char) then return end

    local root = get_root(lp)
    local hum = get_humanoid(lp)
    if not root or not hum then return end

    if char_id(char) ~= tracked_char_id then
        tracked_char_id = char_id(char)
        last_ground_ms = 0
    end

    if settings.enabled(P_FLY) then
        tick_fly(root, hum, char, dt)
    else
        if settings.enabled(P_FLY_NOCLIP) then
            move.set_character_noclip(char, root, false)
        end
        if settings.enabled(P_SLOWFALL) then
            tick_slowfall(root, hum, dt)
        end
        if settings.enabled(P_SPEED_BOOST) then
            tick_speed_boost(root, dt)
        end
    end
end

function M.install()
    bypass.refresh()
end

function M.shutdown()
    bypass.tick_movement(false)
    bypass_active = false
end

return M

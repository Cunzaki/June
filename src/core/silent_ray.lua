local env = June.require("core.env")

local M = {}

local hook_ready = false
local armed = false
local SHOOT_VK = 0x01

M._last_origin = nil
M._last_target = nil
M._last_ok = false
M._last_track_key = nil

local function unpack_pos(v)
    if not v then return nil end
    if v.x ~= nil then return v.x, v.y, v.z end
    if v.X ~= nil then return v.X, v.Y, v.Z end
    return nil
end

local function make_vec3(x, y, z)
    if Vector3 and Vector3.new then
        return Vector3.new(x, y, z)
    end
    return { x = x, y = y, z = z }
end

local function shoot_key(vk)
    return vk or SHOOT_VK
end

local function lmb_down(vk)
    if not input or not input.is_key_down then
        return false
    end
    return input.is_key_down(shoot_key(vk)) == true
end

function M.available()
    return raycast
        and raycast.track_silent_target
        and raycast.stop_silent_tracking
end

function M.ensure_hook()
    if not M.available() then
        return false
    end
    if hook_ready or (raycast.is_silent_hook_active and raycast.is_silent_hook_active()) then
        hook_ready = true
        armed = true
        return true
    end
    if not raycast.enable_silent_hook then
        hook_ready = true
        armed = true
        return true
    end
    local ok = raycast.enable_silent_hook()
    hook_ready = ok == true
    armed = hook_ready
    return hook_ready
end

function M.is_armed()
    return armed
end

function M.is_tracking()
    return armed and M._last_ok
end

function M.get_camera_origin()
    if camera and camera.get_position then
        local ok, pos = pcall(camera.get_position)
        if ok and pos then
            local x, y, z = unpack_pos(pos)
            if x then
                return { x = x, y = y, z = z }
            end
        end
    end

    local ws = env.get_workspace()
    if ws then
        local cam = ws:FindFirstChild("Camera")
        if cam and cam.CFrame and cam.CFrame.Position then
            local pos = cam.CFrame.Position
            return { x = pos.X, y = pos.Y, z = pos.Z }
        end
    end

    return nil
end

function M.stop()
    M._last_origin = nil
    M._last_target = nil
    M._last_ok = false
    M._last_track_key = nil
    armed = false
    if not M.available() then
        return
    end
    pcall(raycast.stop_silent_tracking)
    if raycast.clear_silent_target then
        pcall(raycast.clear_silent_target)
    end
end

function M.last_segment()
    return M._last_origin, M._last_target
end

local function push_silent(origin_v, dir_v)
    if raycast.set_silent_target then
        return pcall(raycast.set_silent_target, origin_v, dir_v) == true
    end
    return false
end

local function push_track(origin_v, dir_v, key)
    if not raycast.track_silent_target then
        return false
    end
    local ok_call, ok = pcall(raycast.track_silent_target, origin_v, dir_v, key)
    return ok_call and ok == true
end

-- direction = target - origin (NOT normalized, NOT scaled).
function M.track(origin, aim_point, shoot_vk, hitpart, force)
    M._last_ok = false
    if not aim_point then
        return false
    end

    if not M.ensure_hook() then
        return false
    end

    origin = origin or M.get_camera_origin()
    if not origin then
        return false
    end

    local ox, oy, oz = unpack_pos(origin)
    local ax, ay, az = unpack_pos(aim_point)
    if not ox or not ax then
        return false
    end

    local dx, dy, dz = ax - ox, ay - oy, az - oz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    local dir

    if dist < 0.001 then
        local cam = M.get_camera_origin()
        if cam then
            dx, dy, dz = cam.x - ox, cam.y - oy, cam.z - oz
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        if not dist or dist < 0.001 then
            dir = make_vec3(0, 1, 0)
        else
            dir = make_vec3(dx, dy, dz)
        end
    else
        dir = make_vec3(dx, dy, dz)
    end

    M._last_origin = { x = ox, y = oy, z = oz }
    if hitpart and hitpart.x then
        M._last_target = { x = hitpart.x, y = hitpart.y, z = hitpart.z }
    else
        M._last_target = { x = ax, y = ay, z = az }
    end

    local key = shoot_key(shoot_vk)
    local firing = lmb_down(key)
    local track_key = string.format("%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", ox, oy, oz, ax, ay, az)
    if not force and not firing and M._last_track_key == track_key and M._last_ok then
        return true
    end

    local origin_v = make_vec3(ox, oy, oz)
    local pushed = push_silent(origin_v, dir)
    local tracked = false
    if force or firing then
        tracked = push_track(origin_v, dir, key)
    end

    M._last_ok = pushed or tracked
    armed = M._last_ok
    if M._last_ok then
        M._last_track_key = track_key
    end
    return M._last_ok
end

return M

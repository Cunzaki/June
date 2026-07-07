--[[ Silent raycast hook — Vector API track_silent_target (see docs/API.md). ]]

local M = {}

local hook_ready = false
local tracking = false
local MOUSE_RAY_LEN = 1024

M._last_origin = nil
M._last_target = nil
M._last_ok = false

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

function M.available()
    return raycast
        and raycast.track_silent_target
        and raycast.stop_silent_tracking
end

function M.ensure_hook()
    if not M.available() then return false end
    if hook_ready or (raycast.is_silent_hook_active and raycast.is_silent_hook_active()) then
        hook_ready = true
        return true
    end
    if not raycast.enable_silent_hook then
        hook_ready = true
        return true
    end
    local ok = raycast.enable_silent_hook()
    hook_ready = ok == true
    return hook_ready
end

function M.is_tracking()
    return tracking
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

    if game and game.Workspace then
        local cam = game.Workspace:FindFirstChild("Camera")
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
    tracking = false
    if not M.available() then return end
    pcall(raycast.stop_silent_tracking)
    if raycast.clear_silent_target then
        pcall(raycast.clear_silent_target)
    end
end

function M.last_segment()
    return M._last_origin, M._last_target
end

function M.track(origin, aim_point, shoot_vk)
    M._last_ok = false
    if not aim_point then return false end

    origin = origin or M.get_camera_origin()
    if not origin then return false end
    if not M.ensure_hook() then return false end

    local ox, oy, oz = unpack_pos(origin)
    local ax, ay, az = unpack_pos(aim_point)
    if not ox or not ax then return false end

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
            dir = make_vec3(0, MOUSE_RAY_LEN * 0.01, 0)
        else
            local inv = 1 / dist
            dir = make_vec3(dx * inv * MOUSE_RAY_LEN, dy * inv * MOUSE_RAY_LEN, dz * inv * MOUSE_RAY_LEN)
        end
    else
        local inv = 1 / dist
        dir = make_vec3(dx * inv * MOUSE_RAY_LEN, dy * inv * MOUSE_RAY_LEN, dz * inv * MOUSE_RAY_LEN)
    end

    M._last_origin = { x = ox, y = oy, z = oz }
    M._last_target = { x = ax, y = ay, z = az }

    local origin_v = make_vec3(ox, oy, oz)
    local key = shoot_vk or 0x01

    local ok = raycast.track_silent_target(origin_v, dir, key) == true
    if ok and raycast.set_silent_target then
        pcall(raycast.set_silent_target, origin_v, dir)
    end

    M._last_ok = ok
    tracking = ok
    return ok
end

return M

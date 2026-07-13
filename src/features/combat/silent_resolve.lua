local settings = June.require("core.settings")
local silent_ray = June.require("core.silent_ray")
local combat_origin = June.require("game.combat_origin")
local hitscan_ray = June.require("features.combat.hitscan_ray")

local M = {}

M.last_info = { state = "off", origin = nil, aim = nil, path = nil }

local BONE_NAMES = { [0] = "head", [1] = "torso", [2] = "arm1", [3] = "arm2", [4] = "leg1", [5] = "leg2" }

local function bone_name(idx)
    idx = tonumber(idx) or 0
    if idx == 6 then return nil end
    return BONE_NAMES[idx] or "head"
end

local function aim_past(origin, target, past)
    if not origin or not target then
        return nil
    end
    past = past or 3.0
    local dx = target.x - origin.x
    local dy = target.y - origin.y
    local dz = target.z - origin.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        return { x = target.x, y = target.y, z = target.z }
    end
    local scale = past / len
    return {
        x = target.x + dx * scale,
        y = target.y + dy * scale,
        z = target.z + dz * scale,
    }
end

function M.resolve_track(aim, bone_idx, opts)
    M.last_info = { state = "off", origin = nil, aim = nil, path = nil }
    if not aim then
        return nil, nil, nil
    end

    opts = opts or {}
    local s = settings.s
    local camera = silent_ray.get_camera_origin() or combat_origin.get_camera_origin()
    if not camera then
        return nil, nil, nil
    end

    combat_origin.invalidate()
    local muzzle = combat_origin.get_muzzle_origin() or camera
    local bone = bone_name(bone_idx or s.silent_bone)
    local center = hitscan_ray.target_center(aim, bone) or aim

    local use_hitscan = s.silent_hitscan == true

    if use_hitscan then
        local hs = hitscan_ray.resolve({
            camera = camera,
            hitpart = aim,
            bone = bone,
            muzzle = muzzle,
        })
        if hs and hs.origin and hs.aim then
            M.last_info = {
                state = "hitscan",
                origin = hs.origin,
                aim = hs.hitpart or center,
                path = hs.path,
            }
            return hs.origin, hs.aim, center
        end
    end

    -- Genuine silent aim: redirect engine ray from camera → hitpart.
    local aim_far = aim_past(camera, center, 3.0)
    if not aim_far then
        return nil, nil, nil
    end

    M.last_info = {
        state = "silent",
        origin = camera,
        aim = center,
        path = hitscan_ray.build_path(camera, center, muzzle),
    }
    return camera, aim_far, center
end

return M

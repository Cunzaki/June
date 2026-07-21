local settings = June.require("core.settings")
local silent_ray = June.require("core.silent_ray")
local combat_origin = June.require("game.combat_origin")
local hitscan_ray = June.require("features.combat.hitscan_ray")

local M = {}

local function aim_past(origin, target, past)
    if not origin or not target then
        return nil
    end
    past = past or 2.5
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
    if not aim then
        return nil, nil, nil
    end

    opts = opts or {}
    local s = settings.s
    local is_gadget = opts.is_gadget == true
    local camera = silent_ray.get_camera_origin() or combat_origin.get_camera_origin()
    if not camera then
        return nil, nil, nil
    end

    combat_origin.invalidate()
    local muzzle = combat_origin.get_muzzle_origin()
    local center = aim

    if s.silent_hitscan == true and not is_gadget then
        local hs = hitscan_ray.resolve({
            camera = camera,
            hitpart = center,
            muzzle = muzzle,
        })
        if hs and hs.origin and hs.aim then
            return hs.origin, hs.aim, hs.hitpart or center
        end
    end

    -- Silent: camera (or muzzle when armed) → through target.
    local origin = (muzzle and combat_origin.has_weapon()) and muzzle or camera
    local aim_far = aim_past(origin, center, 2.5)
    if not aim_far then
        return nil, nil, nil
    end

    return origin, aim_far, center
end

return M

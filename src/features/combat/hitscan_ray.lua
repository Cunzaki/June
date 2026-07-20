-- Operation One hitscan — ray origin along muzzle→target (validate_position style).

local combat_origin = June.require("game.combat_origin")

local M = {}

local BONE_CENTER_Y = {
    head = -0.55,
    torso = 0,
    arm1 = 0,
    arm2 = 0,
    leg1 = -0.15,
    leg2 = -0.15,
}

local function copy_pos(p)
    if not p then return nil end
    return { x = p.x, y = p.y, z = p.z }
end

local function unit(dx, dy, dz)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then return 0, 0, 0, 0 end
    local inv = 1 / len
    return dx * inv, dy * inv, dz * inv, len
end

function M.target_center(hitpart, bone)
    if not hitpart then return nil end
    local c = copy_pos(hitpart)
    local yoff = BONE_CENTER_Y[bone or "head"] or -0.4
    c.y = c.y + yoff
    return c
end

function M.build_path(origin, center, muzzle)
    if not origin or not center then return {} end
    local out = {}
    if muzzle then out[#out + 1] = copy_pos(muzzle) end
    out[#out + 1] = copy_pos(origin)
    out[#out + 1] = copy_pos(center)
    return out
end

-- Slide origin along muzzle→target to target depth (mimics Util.validate_position).
function M.resolve(opts)
    opts = opts or {}
    local camera = opts.camera or combat_origin.get_camera_origin()
    local hitpart = opts.hitpart
    if not hitpart or not camera then return nil end

    local bone = opts.bone or "head"
    local center = M.target_center(hitpart, bone)
    if not center then return nil end

    local muzzle = opts.muzzle or combat_origin.get_muzzle_origin() or camera
    local mx, my, mz, dist = unit(
        center.x - muzzle.x,
        center.y - muzzle.y,
        center.z - muzzle.z
    )
    if dist < 0.05 then
        return {
            origin = copy_pos(center),
            aim = copy_pos(center),
            hitpart = center,
            path = M.build_path(center, center, muzzle),
        }
    end

    local origin = {
        x = muzzle.x + mx * dist,
        y = muzzle.y + my * dist,
        z = muzzle.z + mz * dist,
    }

    local past = 3.0
    local aim = {
        x = center.x + mx * past,
        y = center.y + my * past,
        z = center.z + mz * past,
    }

    return {
        origin = origin,
        aim = aim,
        hitpart = center,
        path = M.build_path(origin, center, muzzle),
    }
end

return M

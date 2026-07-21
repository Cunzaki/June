-- Operation One hitscan — ray from muzzle through target (Vector silent hook).

local combat_origin = June.require("game.combat_origin")

local M = {}

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

function M.build_path(origin, center, muzzle)
    if not origin or not center then return {} end
    local out = {}
    if muzzle then out[#out + 1] = copy_pos(muzzle) end
    out[#out + 1] = copy_pos(origin)
    out[#out + 1] = copy_pos(center)
    return out
end

local function aim_past(from, target, past)
    past = past or 2.5
    local ux, uy, uz, len = unit(target.x - from.x, target.y - from.y, target.z - from.z)
    if len < 0.001 then
        return copy_pos(target)
    end
    return {
        x = target.x + ux * past,
        y = target.y + uy * past,
        z = target.z + uz * past,
    }
end

function M.resolve(opts)
    opts = opts or {}
    local center = opts.hitpart
    if not center then return nil end

    local camera = opts.camera or combat_origin.get_camera_origin()
    local muzzle = opts.muzzle or combat_origin.get_muzzle_origin()
    local origin = muzzle or camera
    if not origin then return nil end

    local aim = aim_past(origin, center, 2.5)
    return {
        origin = copy_pos(origin),
        aim = aim,
        hitpart = copy_pos(center),
        path = M.build_path(origin, center, muzzle),
    }
end

return M

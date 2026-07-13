-- Operation One bullet TP — ray origin on viewmodel hitbox, direction through center.
-- Game fires from validate_position(camera, muzzle) — silent hook overrides with origin+dir.

local combat_origin = June.require("game.combat_origin")

local M = {}

M.METHODS = {
    "Head Center",
    "Torso Center",
    "Bone Center",
    "Muzzle Line",
    "Behind Camera",
    "Ring Shuffle",
    "Dense Shuffle",
}

-- Viewmodel bone vertical offsets (R6 lowercase bones).
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

local function add_off(base, ox, oy, oz)
    return { x = base.x + ox, y = base.y + oy, z = base.z + oz }
end

local function toward(from, to)
    return unit(to.x - from.x, to.y - from.y, to.z - from.z)
end

local function toward_camera(origin, camera)
    if not camera then return 0, 0, 1, 1 end
    return toward(origin, camera)
end

local function aim_through(center, from, camera)
    local ux, uy, uz, len = toward(from, center)
    if len > 0.02 then
        return add_off(center, ux * 0.12, uy * 0.12, uz * 0.12)
    end
    local lx, ly, lz = toward_camera(center, camera)
    return add_off(center, lx * 0.12, ly * 0.12, lz * 0.12)
end

local function aim_past_target(center, from, past)
    past = past or 2.5
    local ux, uy, uz, len = toward(from, center)
    if len < 0.02 then return copy_pos(center) end
    return add_off(center, ux * past, uy * past, uz * past)
end

local function los_clear(from, to)
    if not from or not to then return false end
    if raycast and raycast.is_visible then
        return raycast.is_visible(from.x, from.y, from.z, to.x, to.y, to.z) == true
    end
    return true
end

function M.target_center(hitpart, bone)
    if not hitpart then return nil end
    local c = copy_pos(hitpart)
    local yoff = BONE_CENTER_Y[bone or "head"] or -0.4
    c.y = c.y + yoff
    return c
end

function M.build_path(tp_origin, center, muzzle)
    if not tp_origin or not center then return {} end
    local out = {}
    if muzzle then out[#out + 1] = copy_pos(muzzle) end
    out[#out + 1] = copy_pos(tp_origin)
    out[#out + 1] = copy_pos(center)
    return out
end

local function origin_head(center)
    return copy_pos(center)
end

local function origin_torso(center, _camera, _idx, bone)
    local c = copy_pos(center)
    if bone ~= "torso" then
        c.y = c.y + 0.35
    end
    return c
end

local function origin_bone(center)
    return copy_pos(center)
end

-- Mimics Util.validate_position: slide along camera→muzzle line to target depth.
local function origin_muzzle_line(center, camera, _idx, _bone, muzzle)
    muzzle = muzzle or camera
    if not muzzle or not camera or not center then return copy_pos(center) end

    local mx, my, mz = toward(muzzle, center)
    local dist = math.sqrt(
        (center.x - muzzle.x) ^ 2 + (center.y - muzzle.y) ^ 2 + (center.z - muzzle.z) ^ 2
    )
    if dist < 0.05 then return copy_pos(center) end

    local t = math.max(0.92, math.min(1.02, dist / math.max(dist, 1)))
    return {
        x = muzzle.x + mx * dist * t,
        y = muzzle.y + my * dist * t,
        z = muzzle.z + mz * dist * t,
    }
end

local function origin_behind_camera(center, camera)
    local lx, ly, lz = toward_camera(center, camera)
    local d = 0.35 + math.random() * 0.85
    return add_off(center, -lx * d, -ly * d, -lz * d)
end

local function origin_ring_shuffle(center, camera)
    for _ = 1, 8 do
        local ang = math.random() * math.pi * 2
        local r = 0.15 + math.random() * 0.45
        local cand = {
            x = center.x + math.cos(ang) * r,
            y = center.y + (math.random() - 0.5) * 0.3,
            z = center.z + math.sin(ang) * r,
        }
        if los_clear(cand, center) then
            return cand
        end
    end
    return copy_pos(center)
end

local function origin_dense_shuffle(center, camera)
    for _ = 1, 16 do
        local cand = origin_ring_shuffle(center, camera)
        if los_clear(cand, center) then
            return cand
        end
    end
    return copy_pos(center)
end

local ORIGIN_FN = {
    origin_head,
    origin_torso,
    origin_bone,
    origin_muzzle_line,
    origin_behind_camera,
    origin_ring_shuffle,
    origin_dense_shuffle,
}

function M.resolve(opts)
    opts = opts or {}
    local camera = opts.camera or combat_origin.get_camera_origin()
    local hitpart = opts.hitpart
    if not hitpart or not camera then return nil end

    local method_idx = math.floor(tonumber(opts.method) or 0)
    if method_idx < 0 then method_idx = 0 end
    if method_idx >= #M.METHODS then method_idx = 0 end

    local bone = opts.bone or "head"
    local center = M.target_center(hitpart, bone)
    if not center then return nil end

    local muzzle = opts.muzzle or combat_origin.get_muzzle_origin() or camera
    local pick = ORIGIN_FN[method_idx + 1] or origin_head
    local origin = pick(center, camera, method_idx, bone, muzzle)
    if not origin then return nil end

    -- Aim past target so the ray segment crosses the hitbox (not zero-length at center).
    local aim = aim_past_target(center, origin, 3.0)

    return {
        origin = origin,
        aim = aim,
        hitpart = center,
        method = M.METHODS[method_idx + 1],
        tp_path = M.build_path(origin, center, muzzle),
    }
end

return M

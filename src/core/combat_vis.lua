-- Visibility with soft/breakable penetration (Op One: Items_29757 parts_on_ray logic).

local M = {}

local MAX_PENETRATIONS = 16
local PENETRATE_ADVANCE = 0.08

local function part_of(inst, root)
    if not inst or not root then
        return false
    end
    local p = inst
    while p do
        if p == root then
            return true
        end
        p = p.Parent or p.parent
    end
    return false
end

local function attr_true(inst, name)
    if not inst then
        return false
    end
    if inst.GetAttribute then
        local ok, v = pcall(inst.GetAttribute, inst, name)
        if ok and v then
            return true
        end
    end
    if inst.getAttribute then
        local ok, v = pcall(inst.getAttribute, inst, name)
        if ok and v then
            return true
        end
    end
    return false
end

local function has_tag(inst, tag)
    if not inst or not tag then
        return false
    end
    if inst.HasTag then
        local ok, v = pcall(inst.HasTag, inst, tag)
        return ok and v == true
    end
    return false
end

function M.is_penetrable(inst)
    if not inst then
        return false
    end
    if attr_true(inst, "Soft") then
        return true
    end
    if has_tag(inst, "Breakable") then
        return true
    end
    local parent = inst.Parent or inst.parent
    if parent then
        if attr_true(parent, "Soft") then
            return true
        end
        if has_tag(parent, "Breakable") then
            return true
        end
    end
    if inst.CanCollide == false and inst.Transparency and inst.Transparency < 1 then
        return true
    end
    return false
end

function M.can_see(ox, oy, oz, tx, ty, tz, target_root, penetrate)
    if not raycast then
        return true
    end
    if raycast.is_ready and not raycast.is_ready() then
        return false
    end
    if not ox or not tx then
        return false
    end

    if not penetrate or not raycast.cast then
        if raycast.is_visible then
            return raycast.is_visible(ox, oy, oz, tx, ty, tz) == true
        end
        return true
    end

    local fx, fy, fz = ox, oy, oz
    for _ = 1, MAX_PENETRATIONS do
        local hit, _, dist, inst, is_terrain = raycast.cast(fx, fy, fz, tx, ty, tz)
        if not hit then
            return true
        end
        if is_terrain then
            return false
        end
        if target_root and inst and part_of(inst, target_root) then
            return true
        end
        if not M.is_penetrable(inst) then
            return false
        end

        local dx, dy, dz = tx - fx, ty - fy, tz - fz
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 0.02 then
            return false
        end
        local step = (tonumber(dist) or 0) + PENETRATE_ADVANCE
        if step >= len then
            return true
        end
        local inv = 1 / len
        fx = fx + dx * inv * step
        fy = fy + dy * inv * step
        fz = fz + dz * inv * step
    end

    return false
end

function M.can_see_player(cam_x, cam_y, cam_z, player, aim, penetrate, muzzle)
    if not player then
        return false
    end
    aim = aim or player.head_pos
    if not aim then
        return false
    end

    local tx, ty, tz = aim.x, aim.y, aim.z
    local vm = player.viewmodel

    if M.can_see(cam_x, cam_y, cam_z, tx, ty, tz, vm, penetrate) then
        return true
    end

    if muzzle then
        return M.can_see(muzzle.x, muzzle.y, muzzle.z, tx, ty, tz, vm, penetrate)
    end

    return false
end

return M

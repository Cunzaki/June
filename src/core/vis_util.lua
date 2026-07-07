--[[ Line-of-sight helpers — raycast.cast (fail-closed) with gadget target matching. ]]

local silent_ray = OperationOne.require("core.silent_ray")

local M = {}

function M.part_of(inst, root)
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

function M.ray_origin()
    local o = silent_ray.get_camera_origin()
    if o then
        return o.x, o.y, o.z
    end
    return nil
end

function M.aim_point(entry)
    if not entry then
        return nil
    end
    local anchor = entry.anchor
    if anchor and anchor.Position then
        local p = anchor.Position
        return p.X or p.x, p.Y or p.y, p.Z or p.z
    end
    if entry.x then
        return entry.x, entry.y, entry.z
    end
    return nil
end

function M.can_see_world_point(tx, ty, tz, target_root)
    if not raycast then
        return true
    end
    if raycast.is_ready and not raycast.is_ready() then
        return false
    end

    local ox, oy, oz = M.ray_origin()
    if not ox or not tx then
        return false
    end

    if raycast.cast then
        local hit, _, _, inst = raycast.cast(ox, oy, oz, tx, ty, tz)
        if not hit then
            return true
        end
        if target_root and inst and M.part_of(inst, target_root) then
            return true
        end
        return false
    end

    if raycast.is_visible then
        return raycast.is_visible(ox, oy, oz, tx, ty, tz) == true
    end

    return true
end

function M.can_see_entry(entry)
    if not entry then
        return false
    end
    local tx, ty, tz = M.aim_point(entry)
    if not tx then
        return false
    end
    return M.can_see_world_point(tx, ty, tz, entry.obj)
end

return M

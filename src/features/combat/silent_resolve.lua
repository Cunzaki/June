--[[ Silent ray origin — camera to target (hitscan). ]]

local silent_ray = June.require("core.silent_ray")

local M = {}

function M.resolve_track(aim)
    if not aim then
        return nil, nil
    end

    local camera = silent_ray.get_camera_origin()
    if not camera then
        return nil, nil
    end

    return camera, aim
end

return M

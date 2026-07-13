local settings = June.require("core.settings")

local M = {}
local s = settings.s

function M.process_fov_changer()
    if not s.fov_changer_enabled then
        return
    end
    if not camera or not camera.get_fov or not camera.set_fov then
        return
    end

    local target = tonumber(s.fov_changer_value) or 90
    if target > 90 then target = 90 end
    if target < 60 then target = 60 end
    local cur_fov = camera.get_fov()
    if not cur_fov then
        return
    end

    if math.abs(cur_fov - target) > 0.1 then
        camera.set_fov(target)
    end
end

M.process_fov_changer = M.process_fov_changer

return M

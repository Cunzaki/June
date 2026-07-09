local settings = June.require("core.settings")

local M = {}
local s = settings.s

local function process_fov_changer()
    if not s.fov_changer_enabled then
        return
    end

    local cur_fov = camera.get_fov()
    if not cur_fov then return end

    if math.abs(cur_fov - 90) > 0.1 then
        camera.set_fov(90)
    end
end

M.process_fov_changer = process_fov_changer

return M

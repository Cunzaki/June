local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")
local draw_util = OperationOne.require("core.draw_util")

local M = {}
local s = settings.s
local draw_part_hull = draw_util.draw_part_hull
local normalize_chams_style = draw_util.normalize_chams_style

local function render_viewmodel_chams()
    if not (s.vm_arms_chams or s.vm_weapon_chams) then return end
    
    local vms = cache.ws:FindFirstChild("Viewmodels")
    local local_vm = vms and vms:FindFirstChild("LocalViewmodel")
    if not local_vm then return end
    
    local arm_parts = {arm1=true, arm2=true, shoulder1=true, shoulder2=true, hand1=true, hand2=true}
    
    local function process_model(model)
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") then
                if s.vm_arms_chams and arm_parts[child.Name] then
                    draw_part_hull(child, s.vm_arms_chams_color, normalize_chams_style(s.vm_arms_style or 0))
                elseif s.vm_weapon_chams and not arm_parts[child.Name] then
                    draw_part_hull(child, s.vm_weapon_chams_color, normalize_chams_style(s.vm_weapon_style or 0))
                end
            elseif child:IsA("Model") then
                process_model(child)
            end
        end
    end
    
    process_model(local_vm)
end

M.render_viewmodel_chams = render_viewmodel_chams

return M

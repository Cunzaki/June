--[[ Gadget alive/broken rules derived from Operation One decompiled scripts.
    Cameras: Disabled attribute, Cam/Dot transparency (Breakable/Electronic states).
    Placeables/throwables: leave Workspace when destroyed (Garbage pool).
]]

local M = {}

local CAMERA_MODELS = {
    DefaultCamera = true,
    BulletproofCamera = true,
    StickyCamera = true,
}

local function is_valid(inst)
    if not inst then
        return false
    end
    if utility and utility.is_valid then
        return utility.is_valid(inst)
    end
    return true
end

local function get_attr(inst, name)
    if not inst or type(inst.GetAttribute) ~= "function" then
        return nil
    end
    return inst:GetAttribute(name)
end

local function part_visible(part)
    if not part or not is_valid(part) then
        return false
    end
    local pos = part.Position or part.position
    if not pos then
        return false
    end
    local tr = part.Transparency
    if tr ~= nil and tr >= 1 then
        return false
    end
    return true
end

local function is_pooled(obj)
    local parent = obj and (obj.Parent or obj.parent)
    if not parent then
        return false
    end
    local pname = parent.Name or parent.name or ""
    if pname == "Garbage" or pname == "Objects" then
        return true
    end
    if game and game.ReplicatedStorage then
        local garbage = game.ReplicatedStorage:FindFirstChild("Garbage")
        if garbage and parent == garbage then
            return true
        end
        local objects = game.ReplicatedStorage:FindFirstChild("Objects")
        if objects and parent == objects then
            return true
        end
    end
    return false
end

function M.is_camera_model(name)
    return CAMERA_MODELS[name] == true
end

function M.is_camera_broken(obj)
    if not is_valid(obj) then
        return true
    end
    if get_attr(obj, "Disabled") == true then
        return true
    end

    local dot = obj:FindFirstChild("Dot")
    if dot and dot.Transparency ~= nil and dot.Transparency >= 1 then
        return true
    end

    local cam = obj:FindFirstChild("Cam")
    if not part_visible(cam) then
        return true
    end

    return false
end

function M.is_map_camera_placed(obj, ws)
    if not is_valid(obj) or is_pooled(obj) then
        return false
    end
    local parent = obj.Parent or obj.parent
    while parent and parent ~= ws do
        if parent.Name == "DefaultCameras" then
            return true
        end
        parent = parent.Parent or parent.parent
    end
    return false
end

function M.is_workspace_placed(obj, ws)
    if not is_valid(obj) or is_pooled(obj) then
        return false
    end
    local parent = obj.Parent or obj.parent
    if ws then
        return parent == ws
    end
    return parent and (parent.ClassName == "Workspace" or parent == game.Workspace)
end

function M.is_broken(obj, item)
    if not obj then
        return true
    end

    local kind = (item and item.name) or obj.Name
    if M.is_camera_model(kind) then
        return M.is_camera_broken(obj)
    end

    if get_attr(obj, "Disabled") == true then
        return true
    end

    local anchor_name = (item and (item.anchor_part or item.priority_part)) or "Root"
    local anchor = obj:FindFirstChild(anchor_name)
    if anchor and not part_visible(anchor) then
        return true
    end

    return false
end

function M.is_trackable(obj, item, ws)
    if not obj or not item then
        return false
    end
    if item.map_only then
        return M.is_map_camera_placed(obj, ws) and not M.is_camera_broken(obj)
    end
    return M.is_workspace_placed(obj, ws) and not M.is_broken(obj, item)
end

function M.find_anchor(obj, item)
    if not is_valid(obj) then
        return nil
    end

    local names = {}
    if item then
        if item.anchor_part then
            names[#names + 1] = item.anchor_part
        end
        if item.priority_part and item.priority_part ~= item.anchor_part then
            names[#names + 1] = item.priority_part
        end
    end

    local kind = (item and item.name) or obj.Name
    if M.is_camera_model(kind) then
        names[#names + 1] = "Cam"
        names[#names + 1] = "Dot"
    else
        names[#names + 1] = "Root"
        names[#names + 1] = "Cam"
        names[#names + 1] = "Base"
        names[#names + 1] = "Handle"
        names[#names + 1] = "Primary"
    end

    local seen = {}
    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            local part = obj:FindFirstChild(name)
            if part_visible(part) then
                return part
            end
        end
    end

    if obj.PrimaryPart and part_visible(obj.PrimaryPart) then
        return obj.PrimaryPart
    end

    if obj.GetChildren then
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Part" or cn == "MeshPart" or cn == "UnionOperation" then
                if part_visible(child) then
                    return child
                end
            end
        end
    end

    return nil
end

function M.camera_status_label(obj, base_label)
    if not is_valid(obj) then
        return base_label
    end
    if get_attr(obj, "Disabled") == true then
        return base_label .. " (OFF)"
    end
    if M.is_camera_broken(obj) then
        return base_label .. " (BROKEN)"
    end
    return base_label
end

return M

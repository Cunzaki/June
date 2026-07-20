local env = June.require("core.env")
local cache = June.require("core.cache")

local M = {}

local frame = {t = 0, muzzle = nil, server = nil}

local MUZZLE_NAMES = {"Muzzle", "FlashPart", "Flash", "BarrelPart", "UpperBarrel", "Barrel", "Grip"}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function part_pos(part)
    if not part then
        return nil
    end
    local pos = part.Position or part.position
    if not pos then
        return nil
    end
    local x = pos.X or pos.x
    local y = pos.Y or pos.y
    local z = pos.Z or pos.z
    if not x then
        return nil
    end
    return {x = x, y = y, z = z}
end

local function find_named_part(root)
    if not root or not root.GetDescendants then
        return nil
    end
    for _, name in ipairs(MUZZLE_NAMES) do
        local direct = root:FindFirstChild(name)
        if direct and direct.Position then
            return direct
        end
    end
    for _, desc in ipairs(root:GetDescendants()) do
        for _, name in ipairs(MUZZLE_NAMES) do
            if desc.Name == name and desc.Position then
                return desc
            end
        end
    end
    return nil
end

local function local_viewmodel()
    if not cache.ws then
        return nil
    end
    local vms = cache.ws:FindFirstChild("Viewmodels")
    if not vms then
        return nil
    end
    return vms:FindFirstChild("LocalViewmodel")
end

local function find_weapon_model(vm)
    if not vm then
        return nil
    end
    for _, child in ipairs(vm:GetChildren()) do
        if child.ClassName == "Model" and not cache.body_part_names[child.Name] then
            if child:FindFirstChild("Magazine") or find_named_part(child) then
                return child
            end
        end
    end
    return nil
end

local function compute_muzzle()
    local vm = local_viewmodel()
    if vm then
        local weapon = find_weapon_model(vm)
        local part = find_named_part(weapon) or find_named_part(vm)
        local pos = part_pos(part)
        if pos then
            return pos
        end
        local head = vm:FindFirstChild("head")
        pos = part_pos(head)
        if pos then
            return pos
        end
    end

    if camera and camera.get_position then
        local ok, pos = pcall(camera.get_position)
        if ok and pos then
            local x = pos.X or pos.x
            local y = pos.Y or pos.y
            local z = pos.Z or pos.z
            if x then
                return {x = x, y = y, z = z}
            end
        end
    end

    return nil
end

local function compute_server()
    if entity and entity.get_local_player then
        local lp = entity.get_local_player()
        if lp and lp.position then
            local p = lp.position
            local x = p.X or p.x
            local y = p.Y or p.y
            local z = p.Z or p.z
            if x then
                return {x = x, y = y, z = z}
            end
        end
    end

    local lp = env.get_local_player()
    if lp then
        local char = lp.character or lp.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local pos = part_pos(hrp)
            if pos then
                return pos
            end
        end
    end

    return nil
end

function M.invalidate()
    frame.t = 0
    frame.muzzle = nil
    frame.server = nil
end

function M.sync()
    local now = tick_ms()
    if frame.t == now and frame.muzzle and frame.server then
        return
    end
    frame.t = now
    frame.muzzle = compute_muzzle()
    frame.server = compute_server()
end

function M.get_muzzle_origin()
    M.sync()
    return frame.muzzle
end

function M.get_server_origin()
    M.sync()
    return frame.server
end

function M.has_weapon()
    return find_weapon_model(local_viewmodel()) ~= nil
end

function M.get_camera_origin()
    if camera and camera.get_position then
        local ok, pos = pcall(camera.get_position)
        if ok and pos then
            local x = pos.X or pos.x
            local y = pos.Y or pos.y
            local z = pos.Z or pos.z
            if x then
                return {x = x, y = y, z = z}
            end
        end
    end
    return nil
end

return M

--[[ Gadget + camera discovery for world ESP / utilities aimbot. ]]

local draw_util = June.require("core.draw_util")
local world_items = June.require("game.world_items")

local M = {}

local get_model_bbox = draw_util.get_model_bbox
local bbox_center = draw_util.bbox_center
local bbox_from_part = draw_util.bbox_from_part
local get_world_item_position = draw_util.get_world_item_position

local CAMERA_PART_NAMES = {"Cam", "CameraPart", "Root", "Base", "Dot"}
local GADGET_BBOX_MAX_PARTS = 8

local map_camera_folders = nil
local map_camera_folders_at = 0
local MAP_CAMERA_FOLDER_MS = 5000

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function is_valid(inst)
    if not inst then
        return false
    end
    if utility and utility.is_valid then
        return utility.is_valid(inst)
    end
    return true
end

local function unpack_pos(pos)
    if not pos then
        return nil
    end
    local x = pos.X or pos.x
    local y = pos.Y or pos.y
    local z = pos.Z or pos.z
    if not x then
        return nil
    end
    return x, y, z
end

local function is_geometry(inst)
    if not inst then
        return false
    end
    if inst.IsA then
        if inst:IsA("BasePart") or inst:IsA("UnionOperation") or inst:IsA("MeshPart") then
            return true
        end
    end
    if inst.is_a then
        if inst:is_a("BasePart") or inst:is_a("UnionOperation") or inst:is_a("MeshPart") then
            return true
        end
    end
    local cn = inst.ClassName or inst.class_name
    return cn == "Part" or cn == "MeshPart" or cn == "UnionOperation"
end

local function find_anchor_part(model)
    if not is_valid(model) then
        return nil
    end
    for _, name in ipairs(CAMERA_PART_NAMES) do
        local part = model:FindFirstChild(name)
        if is_geometry(part) then
            return part
        end
    end
    if model.GetChildren then
        for _, child in ipairs(model:GetChildren()) do
            if is_geometry(child) then
                return child
            end
        end
    end
    return nil
end

function M.get_map_camera_folders(ws)
    local now = tick_ms()
    if map_camera_folders and now - map_camera_folders_at < MAP_CAMERA_FOLDER_MS then
        return map_camera_folders
    end

    local folders = {}
    if not is_valid(ws) then
        map_camera_folders = folders
        map_camera_folders_at = now
        return folders
    end

    local model_root = ws:FindFirstChild("Model")
    if model_root and is_valid(model_root) then
        for _, map_child in ipairs(model_root:GetChildren()) do
            if is_valid(map_child) then
                local cams = map_child:FindFirstChild("DefaultCameras")
                if cams and is_valid(cams) then
                    folders[#folders + 1] = cams
                end
            end
        end
    end

    map_camera_folders = folders
    map_camera_folders_at = now
    return folders
end

function M.invalidate_map_camera_cache()
    map_camera_folders = nil
    map_camera_folders_at = 0
end

function M.resolve_entry(obj, item, s)
    if not is_valid(obj) or not item then
        return nil
    end

    local bbox = get_model_bbox(obj, GADGET_BBOX_MAX_PARTS)
    local pos, sz = nil, nil

    if bbox then
        local center = bbox_center(bbox)
        if center then
            pos = {X = center.x, Y = center.y, Z = center.z}
            sz = {
                X = bbox[4] - bbox[1],
                Y = bbox[5] - bbox[2],
                Z = bbox[6] - bbox[3],
            }
        end
    end

    if not pos then
        pos, sz = get_world_item_position(obj, item)
    end

    if not pos then
        local anchor = find_anchor_part(obj)
        if anchor then
            local x, y, z = unpack_pos(anchor.Position or anchor.position)
            if x then
                pos = {X = x, Y = y, Z = z}
                bbox = bbox or bbox_from_part(anchor)
                local size = anchor.Size or anchor.size
                if size then
                    sz = size
                end
            end
        end
    end

    if not pos then
        return nil
    end

    local px, py, pz = unpack_pos(pos)
    if not px then
        return nil
    end

    local color = s[item.enabled .. "_color"] or {1, 1, 1, 1}
    local anchor = find_anchor_part(obj)
    return {
        x = px,
        y = py,
        z = pz,
        size = sz,
        bbox = bbox,
        label = item.label,
        color = color,
        obj = obj,
        item = item,
        anchor = anchor,
        is_esp = s[item.enabled] == true,
        kind = item.name or item.model_name,
    }
end

function M.should_scan_gadget(item, s, utilities_active, targetable_utilities)
    if s[item.enabled] then
        return true
    end
    if utilities_active and targetable_utilities[item.label] then
        return true
    end
    return false
end

function M.scan_workspace_children_batch(state, batch, s, utilities_active, targetable_utilities, max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache)
    local lookup = world_items.world_items_by_name
    local processed = 0
    local children = state.children
    local wi = state.wi

    while wi <= #children and processed < batch do
        local child = children[wi]
        wi = wi + 1
        processed = processed + 1
        if is_valid(child) then
            local item = lookup[child.Name]
            if item and M.should_scan_gadget(item, s, utilities_active, targetable_utilities) then
                local entry = M.resolve_entry(child, item, s)
                if entry then
                    local dsq = dist3d_sq(entry.x, entry.y, entry.z, cam_x, cam_y, cam_z)
                    if dsq <= max_sq and dsq > DIST.ESP_HIDE_SQ and not cache.world_lookup[child] then
                        state.count = state.count + 1
                        entry.dist = sqrt(dsq)
                        cache.world[state.count] = entry
                        cache.world_lookup[child] = entry
                    end
                end
            end
        end
    end

    state.wi = wi
    return wi > #children
end

function M.scan_workspace_children(ws, s, utilities_active, targetable_utilities, max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count)
    local lookup = world_items.world_items_by_name
    for _, child in ipairs(ws:GetChildren()) do
        if is_valid(child) then
            local item = lookup[child.Name]
            if item and M.should_scan_gadget(item, s, utilities_active, targetable_utilities) then
                local entry = M.resolve_entry(child, item, s)
                if entry then
                    local dsq = dist3d_sq(entry.x, entry.y, entry.z, cam_x, cam_y, cam_z)
                    if dsq <= max_sq and dsq > DIST.ESP_HIDE_SQ and not cache.world_lookup[child] then
                        count = count + 1
                        entry.dist = sqrt(dsq)
                        cache.world[count] = entry
                        cache.world_lookup[child] = entry
                    end
                end
            end
        end
    end
    return count
end

local function camera_enabled(camera_item, s)
    return s[camera_item.enabled] == true
end

local function camera_color(camera_item, s)
    return s[camera_item.color_key .. "_color"] or {0.8, 0.8, 1, 1}
end

function M.try_add_camera(obj, camera_item, s, scan_cameras_for_esp, max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count)
    if not is_valid(obj) or cache.world_lookup[obj] then
        return count
    end

    local esp_on = scan_cameras_for_esp and camera_enabled(camera_item, s)
    if not esp_on then
        return count
    end

    local anchor = find_anchor_part(obj)
    if not anchor then
        return count
    end

    local x, y, z = unpack_pos(anchor.Position or anchor.position)
    if not x then
        return count
    end

    local dsq = dist3d_sq(x, y, z, cam_x, cam_y, cam_z)
    if dsq > max_sq or dsq <= DIST.ESP_HIDE_SQ then
        return count
    end

    local label = camera_item.label
    if camera_item.model_name == "DefaultCamera" then
        local disabled = false
        if type(obj.GetAttribute) == "function" then
            disabled = obj:GetAttribute("Disabled") == true
        end
        if disabled then
            label = "MAP CAM (OFF)"
        end
    end

    count = count + 1
    local entry = {
        x = x,
        y = y,
        z = z,
        dist = sqrt(dsq),
        bbox = bbox_from_part(anchor),
        label = label,
        color = camera_color(camera_item, s),
        obj = obj,
        item = camera_item,
        anchor = anchor,
        is_esp = true,
        kind = camera_item.model_name,
    }
    cache.world[count] = entry
    cache.world_lookup[obj] = entry
    return count
end

local function scan_map_default_cameras(ws, camera_item, s, scan_cameras_for_esp, max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count)
    for _, folder in ipairs(M.get_map_camera_folders(ws)) do
        if is_valid(folder) then
            for _, child in ipairs(folder:GetChildren()) do
                if is_valid(child) and child.Name == camera_item.model_name then
                    count = M.try_add_camera(
                        child, camera_item, s, scan_cameras_for_esp,
                        max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count
                    )
                end
            end
        end
    end
    return count
end

function M.scan_cameras(ws, s, utilities_active, targetable_utilities, max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count)
    local scan_for_util = utilities_active and targetable_utilities.CAMERA

    for _, camera_item in ipairs(world_items.camera_items) do
        local scan_for_esp = camera_enabled(camera_item, s)
        if scan_for_esp or scan_for_util then
            if camera_item.map_only then
                count = scan_map_default_cameras(
                    ws, camera_item, s, scan_for_esp,
                    max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count
                )
            else
                for _, child in ipairs(ws:GetChildren()) do
                    if is_valid(child) and child.Name == camera_item.model_name then
                        count = M.try_add_camera(
                            child, camera_item, s, scan_for_esp,
                            max_sq, cam_x, cam_y, cam_z, dist3d_sq, sqrt, DIST, cache, count
                        )
                    end
                end
            end
        end
    end

    return count
end

function M.refresh_entry(entry, cam_x, cam_y, cam_z, dist3d_sq, sqrt)
    if not entry or not is_valid(entry.obj) then
        return false
    end

    local pos = nil
    if entry.item then
        pos = get_world_item_position(entry.obj, entry.item)
    end

    if not pos then
        local anchor = entry.anchor
        if not is_valid(anchor) then
            anchor = find_anchor_part(entry.obj)
            entry.anchor = anchor
        end
        if not anchor then
            return false
        end
        local x, y, z = unpack_pos(anchor.Position or anchor.position)
        if not x then
            return false
        end
        entry.x = x
        entry.y = y
        entry.z = z
        entry.bbox = bbox_from_part(anchor)
    else
        local x, y, z = unpack_pos(pos)
        if not x then
            return false
        end
        entry.x = x
        entry.y = y
        entry.z = z
        if not entry.bbox then
            local anchor = entry.anchor
            if is_valid(anchor) then
                entry.bbox = bbox_from_part(anchor)
            end
        end
    end

    entry.dist = sqrt(dist3d_sq(entry.x, entry.y, entry.z, cam_x, cam_y, cam_z))
    return true
end

return M

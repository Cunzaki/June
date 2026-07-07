--[[ World gadget scan — workspace + map cameras, per-type lifecycle from game dump. ]]

local draw_util = OperationOne.require("core.draw_util")
local world_items = OperationOne.require("game.world_items")
local gadget_team = OperationOne.require("game.gadget_team")
local gadget_lifecycle = OperationOne.require("game.gadget_lifecycle")

local M = {}

local bbox_from_part = draw_util.bbox_from_part
local get_world_item_position = draw_util.get_world_item_position
local dist3d_sq = draw_util.dist3d_sq

local GADGET_BBOX_MAX_PARTS = 12

local map_camera_folders = nil
local map_camera_folders_at = 0
local MAP_CAMERA_FOLDER_MS = 5000

local TARGETABLE_UTILITIES = {
    DRONE = true,
    C4 = true,
    CLAYMORE = true,
    JAMMER = true,
    STICKY = true,
    ["STICKY CAM"] = true,
    BREACH = true,
    CAMERA = true,
    ["MAP CAM"] = true,
    ["HARD BREACH"] = true,
    ["PROX ALARM"] = true,
    ["BP CAMERA"] = true,
    ["BP CAM"] = true,
    FLASH = true,
    STUN = true,
    FRAG = true,
    SMOKE = true,
    EMP = true,
    IMPACT = true,
    INCENDIARY = true,
}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

function M.inst_key(obj)
    if not obj then
        return nil
    end
    local addr = obj.address or obj.Address
    if addr then
        return tostring(addr)
    end
    return tostring(obj)
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

local function gadget_bbox(item, anchor)
    if anchor then
        return bbox_from_part(anchor)
    end
    return nil
end

local function get_map_camera_folders(ws)
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

local function should_scan_item(item, s, utilities_active)
    if s[item.enabled] then
        return true
    end
    if utilities_active and TARGETABLE_UTILITIES[item.label] then
        return true
    end
    return false
end

local function in_draw_range(dsq, max_sq, hide_sq, dynamic)
    if dsq > max_sq then
        return false
    end
    if dynamic then
        return true
    end
    return dsq > hide_sq
end

local function remove_entry(cache, entry)
    if entry.key then
        cache.world_lookup[entry.key] = nil
    end
    if entry.obj then
        cache.world_lookup[entry.obj] = nil
    end
end

local function add_entry(cache, entry)
    cache.world[#cache.world + 1] = entry
    if entry.key then
        cache.world_lookup[entry.key] = entry
    end
    if entry.obj then
        cache.world_lookup[entry.obj] = entry
    end
end

local function resolve_position(obj, item, anchor)
    local pos, sz = get_world_item_position(obj, item)
    if pos then
        return pos, sz, anchor or gadget_lifecycle.find_anchor(obj, item)
    end

    anchor = anchor or gadget_lifecycle.find_anchor(obj, item)
    if anchor then
        local x, y, z = unpack_pos(anchor.Position or anchor.position)
        if x then
            return {X = x, Y = y, Z = z}, anchor.Size or anchor.size, anchor
        end
    end

    return nil, nil, anchor
end

local function make_entry(obj, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, camera_item)
    local scan_item = camera_item or item
    if not gadget_lifecycle.is_trackable(obj, scan_item, ws) then
        return nil
    end

    local anchor = gadget_lifecycle.find_anchor(obj, scan_item)
    if not anchor then
        return nil
    end

    local pos, sz, resolved_anchor = resolve_position(obj, scan_item, anchor)
    if not pos then
        return nil
    end
    anchor = resolved_anchor or anchor

    local px, py, pz = unpack_pos(pos)
    if not px then
        return nil
    end

    local dsq = dist3d_sq(px, py, pz, cam_x, cam_y, cam_z)
    local is_dynamic = item and item.dynamic == true
    if not in_draw_range(dsq, max_sq, hide_sq, is_dynamic) then
        return nil
    end

    local label = item and item.label or (camera_item and camera_item.label) or obj.Name
    if camera_item then
        label = gadget_lifecycle.camera_status_label(obj, label)
    end

    local enabled_key = (camera_item and camera_item.enabled) or (item and item.enabled)
    local color_key = (camera_item and camera_item.color_key) or enabled_key

    return {
        x = px,
        y = py,
        z = pz,
        size = sz,
        bbox = gadget_bbox(scan_item, anchor),
        label = label,
        color = s[color_key .. "_color"] or {1, 1, 1, 1},
        obj = obj,
        item = camera_item or item,
        anchor = anchor,
        is_esp = enabled_key and s[enabled_key] == true,
        kind = (camera_item and camera_item.model_name) or (item and item.name),
        dist = sqrt(dsq),
        key = M.inst_key(obj),
        dynamic = item and item.dynamic == true,
        static = (item and item.static == true) or (camera_item and camera_item.static == true),
        map_only = camera_item and camera_item.map_only == true,
        is_teammate_gadget = gadget_team.is_friendly_gadget(obj),
        is_broken = gadget_lifecycle.is_broken(obj, scan_item),
    }
end

local function prune_entries(cache, match_fn, alive_fn, seen)
    for i = #cache.world, 1, -1 do
        local w = cache.world[i]
        if match_fn(w) then
            local tracked = w.key and seen[w.key]
            local alive = w.obj and alive_fn(w.obj, w.item)
            if not alive or not tracked then
                remove_entry(cache, w)
                table.remove(cache.world, i)
            end
        end
    end
end

function M.get_max_sq(s, utilities_active)
    local max_dist = s.world_max_distance
    if utilities_active then
        max_dist = math.max(max_dist, s.utilities_max_distance)
    end
    return max_dist * max_dist
end

function M.sync_workspace(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active)
    local lookup = world_items.world_items_by_name

    if not is_valid(ws) then
        return
    end

    for _, child in ipairs(ws:GetChildren()) do
        local item = lookup[child.Name]
        if item and should_scan_item(item, s, utilities_active) then
            if gadget_lifecycle.is_trackable(child, item, ws) then
                local key = M.inst_key(child)
                if key then
                    seen[key] = true
                    local entry = cache.world_lookup[key]
                    if entry then
                        M.refresh_flags(entry, s)
                        entry.is_teammate_gadget = gadget_team.is_friendly_gadget(child)
                        entry.is_broken = gadget_lifecycle.is_broken(child, item)
                    else
                        entry = make_entry(child, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, nil)
                        if entry then
                            add_entry(cache, entry)
                        end
                    end
                end
            end
        end
    end

    prune_entries(cache, function(w)
        return w.item and w.item.name and not w.map_only
    end, function(obj, item)
        return gadget_lifecycle.is_trackable(obj, item, ws)
    end, seen)
end

function M.sync_map_cameras(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active)
    local default_camera = world_items.camera_items_by_name.DefaultCamera

    if not default_camera then
        return
    end

    local enabled = s[default_camera.enabled]
        or (utilities_active and TARGETABLE_UTILITIES["MAP CAM"])

    if not enabled then
        for i = #cache.world, 1, -1 do
            local w = cache.world[i]
            if w.map_only then
                remove_entry(cache, w)
                table.remove(cache.world, i)
            end
        end
        return
    end

    for _, folder in ipairs(get_map_camera_folders(ws)) do
        if is_valid(folder) then
            for _, child in ipairs(folder:GetChildren()) do
                if is_valid(child) and child.Name == "DefaultCamera" then
                    if gadget_lifecycle.is_trackable(child, default_camera, ws) then
                        local key = M.inst_key(child)
                        if key then
                            seen[key] = true
                            local entry = cache.world_lookup[key]
                            if entry then
                                M.refresh_flags(entry, s)
                                entry.is_broken = gadget_lifecycle.is_broken(child, default_camera)
                                entry.label = gadget_lifecycle.camera_status_label(child, default_camera.label)
                            else
                                entry = make_entry(child, nil, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, default_camera)
                                if entry then
                                    add_entry(cache, entry)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    prune_entries(cache, function(w)
        return w.map_only == true
    end, function(obj)
        return gadget_lifecycle.is_trackable(obj, default_camera, ws)
    end, seen)
end

function M.refresh_workspace_entry(entry, cam_x, cam_y, cam_z, sqrt, ws)
    if not entry or entry.map_only then
        return false
    end
    if not gadget_lifecycle.is_trackable(entry.obj, entry.item, ws) then
        return false
    end

    local anchor = gadget_lifecycle.find_anchor(entry.obj, entry.item)
    if not anchor then
        return false
    end

    local pos, _, resolved_anchor = resolve_position(entry.obj, entry.item, anchor)
    if not pos then
        return false
    end
    anchor = resolved_anchor or anchor

    local x, y, z = unpack_pos(pos)
    if not x then
        return false
    end

    entry.anchor = anchor
    entry.x = x
    entry.y = y
    entry.z = z
    entry.dist = sqrt(dist3d_sq(x, y, z, cam_x, cam_y, cam_z))
    entry.bbox = gadget_bbox(entry.item, anchor)
    entry.is_teammate_gadget = gadget_team.is_friendly_gadget(entry.obj)
    entry.is_broken = gadget_lifecycle.is_broken(entry.obj, entry.item)
    return true
end

function M.refresh_map_camera_entry(entry, cam_x, cam_y, cam_z, sqrt, ws)
    if not entry or not entry.map_only then
        return false
    end

    local camera_item = entry.item or world_items.camera_items_by_name.DefaultCamera
    if not camera_item or not gadget_lifecycle.is_trackable(entry.obj, camera_item, ws) then
        return false
    end

    local anchor = gadget_lifecycle.find_anchor(entry.obj, camera_item)
    if not anchor then
        return false
    end

    local x, y, z = unpack_pos(anchor.Position or anchor.position)
    if not x then
        return false
    end

    entry.anchor = anchor
    entry.x = x
    entry.y = y
    entry.z = z
    entry.dist = sqrt(dist3d_sq(x, y, z, cam_x, cam_y, cam_z))
    entry.bbox = bbox_from_part(anchor)
    entry.is_broken = gadget_lifecycle.is_broken(entry.obj, camera_item)
    entry.label = gadget_lifecycle.camera_status_label(entry.obj, camera_item.label)
    return true
end

function M.refresh_flags(entry, s)
    if entry.map_only and entry.item then
        entry.is_esp = s[entry.item.enabled] == true
        entry.color = s[entry.item.color_key .. "_color"] or entry.color
        return
    end
    if entry.item and entry.item.enabled then
        entry.is_esp = s[entry.item.enabled] == true
        entry.color = s[entry.item.enabled .. "_color"] or entry.color
    end
end

function M.refresh_all(cache, cam_x, cam_y, cam_z, sqrt, ws)
    ws = ws or cache.ws
    for i = #cache.world, 1, -1 do
        local w = cache.world[i]
        local ok
        if w.map_only then
            ok = M.refresh_map_camera_entry(w, cam_x, cam_y, cam_z, sqrt, ws)
        else
            ok = M.refresh_workspace_entry(w, cam_x, cam_y, cam_z, sqrt, ws)
        end
        if not ok then
            remove_entry(cache, w)
            table.remove(cache.world, i)
        end
    end
end

return M

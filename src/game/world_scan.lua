--[[ World gadget scan — workspace + map cameras, per-type lifecycle from game dump. ]]

local draw_util = OperationOne.require("core.draw_util")
local world_items = OperationOne.require("game.world_items")
local gadget_team = OperationOne.require("game.gadget_team")
local gadget_lifecycle = OperationOne.require("game.gadget_lifecycle")
local shootable_gadgets = OperationOne.require("game.shootable_gadgets")

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

local function should_scan_item(item, s, utilities_active, gadget_aim_active)
    if s[item.enabled] then
        return true
    end
    if gadget_aim_active and shootable_gadgets.is_shootable_item(item) then
        return true
    end
    if utilities_active and TARGETABLE_UTILITIES[item.label] then
        return true
    end
    return false
end

local function in_draw_range(dsq, max_sq, hide_sq, dynamic, for_aim)
    if dsq > max_sq then
        return false
    end
    if for_aim or dynamic then
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

local function make_entry(obj, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, camera_item, for_aim)
    local scan_item = camera_item or item
    local anchor = gadget_lifecycle.find_anchor(obj, scan_item)
    if not anchor or not gadget_lifecycle.is_trackable(obj, scan_item, ws, anchor) then
        return nil
    end

    local pos, sz = get_world_item_position(obj, scan_item)
    if not pos then
        local x, y, z = unpack_pos(anchor.Position or anchor.position)
        if not x then
            return nil
        end
        pos = {X = x, Y = y, Z = z}
        sz = anchor.Size or anchor.size
    end

    local px, py, pz = unpack_pos(pos)
    if not px then
        return nil
    end

    local dsq = dist3d_sq(px, py, pz, cam_x, cam_y, cam_z)
    local is_dynamic = (item and item.dynamic == true) or for_aim
    if not in_draw_range(dsq, max_sq, hide_sq, is_dynamic, for_aim) then
        return nil
    end

    local label = item and item.label or (camera_item and camera_item.label) or obj.Name
    if camera_item then
        label = gadget_lifecycle.camera_status_label(obj, label, anchor)
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
        dsq = dsq,
        key = M.inst_key(obj),
        dynamic = item and item.dynamic == true,
        static = (item and item.static == true) or (camera_item and camera_item.static == true),
        map_only = camera_item and camera_item.map_only == true,
        is_teammate_gadget = gadget_team.is_friendly_gadget(obj),
        is_broken = gadget_lifecycle.is_broken(obj, scan_item, anchor),
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

function M.sync_workspace(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt, gadget_aim_active)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active or gadget_aim_active)
    local lookup = world_items.world_items_by_name
    local for_aim = gadget_aim_active == true

    if not is_valid(ws) then
        return
    end

    for _, child in ipairs(ws:GetChildren()) do
        local item = lookup[child.Name]
        if item and should_scan_item(item, s, utilities_active, gadget_aim_active) then
            if is_valid(child) then
                local key = M.inst_key(child)
                if key then
                    seen[key] = true
                    if not cache.world_lookup[key] then
                        local entry = make_entry(child, item, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, nil, for_aim)
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
        return gadget_lifecycle.is_trackable(obj, item, ws, nil)
    end, seen)
end

function M.sync_map_cameras(ws, s, utilities_active, cache, cam_x, cam_y, cam_z, hide_sq, sqrt, gadget_aim_active)
    local seen = {}
    local max_sq = M.get_max_sq(s, utilities_active or gadget_aim_active)
    local default_camera = world_items.camera_items_by_name.DefaultCamera
    local for_aim = gadget_aim_active == true

    if not default_camera then
        return
    end

    local enabled = s[default_camera.enabled]
        or (utilities_active and TARGETABLE_UTILITIES["MAP CAM"])
        or (gadget_aim_active and shootable_gadgets.is_shootable_item(default_camera))

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
                    local key = M.inst_key(child)
                    if key then
                        seen[key] = true
                        if not cache.world_lookup[key] then
                            local entry = make_entry(child, nil, s, cam_x, cam_y, cam_z, max_sq, hide_sq, sqrt, ws, default_camera, for_aim)
                            if entry then
                                add_entry(cache, entry)
                            end
                        end
                    end
                end
            end
        end
    end

    prune_entries(cache, function(w)
        return w.map_only == true
    end, function(obj, item)
        return gadget_lifecycle.is_map_camera_placed(obj, ws)
            and not gadget_lifecycle.is_camera_broken(obj, nil, nil)
    end, seen)
end

function M.refresh_entry_position(entry, cam_x, cam_y, cam_z, sqrt)
    if not entry or not entry.obj or not is_valid(entry.obj) then
        return false
    end

    local anchor = entry.anchor
    if not anchor or not is_valid(anchor) then
        anchor = gadget_lifecycle.find_anchor(entry.obj, entry.item)
        if not anchor then
            return false
        end
        entry.anchor = anchor
    end

    local x, y, z
    if entry.map_only then
        x, y, z = unpack_pos(anchor.Position or anchor.position)
    else
        local pos = get_world_item_position(entry.obj, entry.item)
        if pos then
            x, y, z = unpack_pos(pos)
        else
            x, y, z = unpack_pos(anchor.Position or anchor.position)
        end
    end

    if not x then
        return false
    end

    entry.x = x
    entry.y = y
    entry.z = z
    local dsq = dist3d_sq(x, y, z, cam_x, cam_y, cam_z)
    entry.dsq = dsq
    entry.dist = sqrt(dsq)

    if entry.dynamic or entry.map_only then
        entry.bbox = gadget_bbox(entry.item, anchor)
    end
    return true
end

function M.refresh_positions(cache, cam_x, cam_y, cam_z, sqrt, only_dynamic)
    for i = 1, #cache.world do
        local w = cache.world[i]
        if not only_dynamic or w.dynamic then
            M.refresh_entry_position(w, cam_x, cam_y, cam_z, sqrt)
        end
    end
end

function M.prune_lifecycle(cache, ws, refresh_team)
    for i = #cache.world, 1, -1 do
        local w = cache.world[i]
        local item = w.item
        local anchor = w.anchor
        if not is_valid(w.obj) or not gadget_lifecycle.is_trackable(w.obj, item, ws, anchor) then
            remove_entry(cache, w)
            table.remove(cache.world, i)
        else
            w.is_broken = gadget_lifecycle.is_broken(w.obj, item, anchor)
            if w.map_only and item then
                w.label = gadget_lifecycle.camera_status_label(w.obj, item.label, anchor)
            end
            if refresh_team then
                w.is_teammate_gadget = gadget_team.is_friendly_gadget(w.obj)
            end
        end
    end
end

function M.refresh_flags(cache_or_entry, s)
    local entries = cache_or_entry
    if cache_or_entry and cache_or_entry.world then
        entries = cache_or_entry.world
        for i = 1, #entries do
            M.refresh_flags(entries[i], s)
        end
        return
    end

    local entry = cache_or_entry
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

return M

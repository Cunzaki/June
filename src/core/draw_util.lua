local constants = OperationOne.require("core.constants")
local settings = OperationOne.require("core.settings")
local cache = OperationOne.require("core.cache")

local sqrt, floor, min, max = constants.sqrt, constants.floor, constants.min, constants.max
local BOX_TYPE = constants.BOX_TYPE
local VIEW_LINE_STYLE = constants.VIEW_LINE_STYLE
local TRACER_STYLE = constants.TRACER_STYLE
local MIN_BONES_REQUIRED = constants.MIN_BONES_REQUIRED

local M = {}
local s = settings.s

function M.dist3d_sq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx * dx + dy * dy + dz * dz
end
function M.is_teammate(vm)
    local h = vm:FindFirstChild("head")
    return h and
        (h:FindFirstChild("Username") or vm:FindFirstChild("TeammateHighlight") or h:FindFirstChild("TeammateHighlight")) and
        true or
        false
end

function M.is_valid_viewmodel(vm)
    if not vm or vm.Name ~= "Viewmodel" then
        return false
    end
    local h, t = vm:FindFirstChild("head"), vm:FindFirstChild("torso")
    if not h or not h.Position or not t or not t.Position or (t.Transparency and t.Transparency >= 1) then
        return false
    end
    local tsz = t.Size
    if tsz and (tsz.X <= 0.1 or tsz.Y <= 0.1 or tsz.Z <= 0.1) then
        return false
    end
    local bc = 0
    for _, bn in ipairs(cache.bone_list) do
        local b = vm:FindFirstChild(bn)
        if b and b.Position and b.Size and (b.Size.X > 0.05 or b.Size.Y > 0.05 or b.Size.Z > 0.05) then
            bc = bc + 1
        end
    end
    return bc >= MIN_BONES_REQUIRED
end

function M.get_world_item_position(obj, cfg)
    if not obj or not cfg then
        return nil, nil
    end

    local function part_pos(part)
        if not part then
            return nil, nil
        end
        local pos = part.Position or part.position
        local sz = part.Size or part.size
        if not pos then
            return nil, nil
        end
        return pos, sz
    end

    if cfg.priority_part then
        local pp = obj:FindFirstChild(cfg.priority_part)
        if pp then
            local pos, sz = part_pos(pp)
            if pos then
                return pos, sz
            end
        end
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Model" or cn == "Folder" then
                pp = child:FindFirstChild(cfg.priority_part)
                if pp then
                    local pos, sz = part_pos(pp)
                    if pos then
                        return pos, sz
                    end
                end
            end
        end
    end

    if obj.PrimaryPart then
        local pos, sz = part_pos(obj.PrimaryPart)
        if pos then
            return pos, sz
        end
    end
    if obj.primary_part then
        local pos, sz = part_pos(obj.primary_part)
        if pos then
            return pos, sz
        end
    end

    for _, name in ipairs({"Root", "Cam", "Base", "Handle", "Primary"}) do
        local pp = obj:FindFirstChild(name)
        if pp then
            local pos, sz = part_pos(pp)
            if pos then
                return pos, sz
            end
        end
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Model" or cn == "Folder" then
                pp = child:FindFirstChild(name)
                if pp then
                    local pos, sz = part_pos(pp)
                    if pos then
                        return pos, sz
                    end
                end
            end
        end
    end

    if obj.FindFirstChildWhichIsA then
        local first_part = obj:FindFirstChildWhichIsA("BasePart")
        if first_part then
            return part_pos(first_part)
        end
    end
    if obj.find_first_child_which_is_a then
        local first_part = obj:find_first_child_which_is_a("BasePart")
        if first_part then
            return part_pos(first_part)
        end
    end

    if obj.GetChildren then
        for _, child in ipairs(obj:GetChildren()) do
            local cn = child.ClassName or child.class_name
            if cn == "Part" or cn == "MeshPart" or cn == "UnionOperation" then
                local pos, sz = part_pos(child)
                if pos then
                    return pos, sz
                end
            end
        end
    end

    return nil, nil
end
local PART_CLASSES = {
    Part = true,
    MeshPart = true,
    UnionOperation = true
}

local function is_part(inst)
    if not inst then
        return false
    end
    local cn = inst.ClassName or inst.class_name
    return PART_CLASSES[cn] == true
end

local function get_descendants(obj)
    if obj.get_descendants then
        return obj:get_descendants()
    end
    if obj.GetDescendants then
        return obj:GetDescendants()
    end
    return {}
end

function M.get_model_bbox(obj, max_parts)
    if not obj then
        return nil
    end
    max_parts = max_parts or 16
    local mnx, mny, mnz = math.huge, math.huge, math.huge
    local mxx, mxy, mxz = -math.huge, -math.huge, -math.huge
    local found = 0

    local function consider(part)
        if not is_part(part) then
            return
        end
        if part.Transparency and part.Transparency >= 1 then
            return
        end
        local pos = part.Position or part.position
        local sz = part.Size or part.size
        if not pos or not sz then
            return
        end
        local hx, hy, hz = sz.X * 0.5, sz.Y * 0.5, sz.Z * 0.5
        local rv = part.RightVector or part.right_vector
        local uv = part.UpVector or part.up_vector
        local lv = part.LookVector or part.look_vector
        if rv and uv and lv then
            local corners = {
                pos + rv * -hx + uv * -hy + lv * -hz,
                pos + rv *  hx + uv * -hy + lv * -hz,
                pos + rv * -hx + uv *  hy + lv * -hz,
                pos + rv *  hx + uv *  hy + lv * -hz,
                pos + rv * -hx + uv * -hy + lv *  hz,
                pos + rv *  hx + uv * -hy + lv *  hz,
                pos + rv * -hx + uv *  hy + lv *  hz,
                pos + rv *  hx + uv *  hy + lv *  hz
            }
            for _, cp in ipairs(corners) do
                mnx = min(mnx, cp.X)
                mny = min(mny, cp.Y)
                mnz = min(mnz, cp.Z)
                mxx = max(mxx, cp.X)
                mxy = max(mxy, cp.Y)
                mxz = max(mxz, cp.Z)
            end
            found = found + 1
        else
            mnx = min(mnx, pos.X - hx)
            mny = min(mny, pos.Y - hy)
            mnz = min(mnz, pos.Z - hz)
            mxx = max(mxx, pos.X + hx)
            mxy = max(mxy, pos.Y + hy)
            mxz = max(mxz, pos.Z + hz)
            found = found + 1
        end
    end

    if is_part(obj) then
        consider(obj)
    else
        for _, child in ipairs(get_descendants(obj)) do
            if found >= max_parts then
                break
            end
            consider(child)
        end
    end

    if found == 0 then
        return nil
    end
    return {mnx, mny, mnz, mxx, mxy, mxz}
end

function M.bbox_from_part(part)
    if not part then
        return nil
    end
    local pos = part.Position or part.position
    local sz = part.Size or part.size
    if not pos or not sz then
        return nil
    end
    local hx = (sz.X or sz.x or 0) * 0.5
    local hy = (sz.Y or sz.y or 0) * 0.5
    local hz = (sz.Z or sz.z or 0) * 0.5
    local px = pos.X or pos.x
    local py = pos.Y or pos.y
    local pz = pos.Z or pos.z
    return {px - hx, py - hy, pz - hz, px + hx, py + hy, pz + hz}
end

function M.bbox_center(bbox)
    if not bbox then
        return nil
    end
    return {
        x = (bbox[1] + bbox[4]) * 0.5,
        y = (bbox[2] + bbox[5]) * 0.5,
        z = (bbox[3] + bbox[6]) * 0.5
    }
end

local hull_cache = {}
local vm_parts_cache = {}
local HULL_CACHE_MS = 150
local HULL_MOVE_EPS = 0.05
local VM_PARTS_CACHE_MS = 600
local MAX_HULL_CACHE = 640

function M.normalize_chams_style(style)
    if style == 1 then
        return 1
    end
    return 0
end

local function trim_hull_cache()
    local n = 0
    for _ in pairs(hull_cache) do
        n = n + 1
    end
    if n <= MAX_HULL_CACHE then
        return
    end
    local now = utility.get_tick_count()
    for k, entry in pairs(hull_cache) do
        if entry.tick and now - entry.tick > HULL_CACHE_MS * 4 then
            hull_cache[k] = nil
        end
    end
end

function M.clear_hull_cache()
    for k in pairs(hull_cache) do
        hull_cache[k] = nil
    end
    for k in pairs(vm_parts_cache) do
        vm_parts_cache[k] = nil
    end
end

function M.is_drawable_body_part(part)
    if not is_part(part) then
        return false
    end
    if part.Transparency and part.Transparency >= 1 then
        return false
    end
    local sz = part.Size or part.size
    if not sz then
        return false
    end
    local sx = sz.X or sz.x or 0
    local sy = sz.Y or sz.y or 0
    local sz_z = sz.Z or sz.z or 0
    if sx < 0.05 and sy < 0.05 and sz_z < 0.05 then
        return false
    end
    return true
end

function M.collect_viewmodel_body_parts(vm)
    local parts = {}
    local seen = {}

    local function add_part(part)
        if part and not seen[part] and M.is_drawable_body_part(part) then
            seen[part] = true
            parts[#parts + 1] = part
        end
    end

    local model = vm and vm.FindFirstChild and vm:FindFirstChild("Model")
    if model then
        for _, desc in ipairs(get_descendants(model)) do
            add_part(desc)
        end
    end

    for _, bn in ipairs(cache.bone_list) do
        local bone = vm and vm.FindFirstChild and vm:FindFirstChild(bn)
        if bone then
            if is_part(bone) then
                add_part(bone)
            end
            for _, desc in ipairs(get_descendants(bone)) do
                add_part(desc)
            end
        end
    end

    return parts
end

function M.get_viewmodel_body_parts(vm)
    if not vm then
        return {}
    end
    local key = tostring(vm)
    local now = utility.get_tick_count()
    local entry = vm_parts_cache[key]
    if entry and (now - entry.tick) < VM_PARTS_CACHE_MS then
        return entry.parts
    end
    local parts = M.collect_viewmodel_body_parts(vm)
    vm_parts_cache[key] = {parts = parts, tick = now}
    return parts
end

function M.project_bbox_screen(bbox)
    if not bbox then
        return nil
    end
    local mnx, mny, mxx, mxy, vis = 10000, 10000, -10000, -10000, false
    for _, c in ipairs({
        {bbox[1], bbox[2], bbox[3]},
        {bbox[4], bbox[2], bbox[3]},
        {bbox[4], bbox[5], bbox[3]},
        {bbox[1], bbox[5], bbox[3]},
        {bbox[1], bbox[2], bbox[6]},
        {bbox[4], bbox[2], bbox[6]},
        {bbox[4], bbox[5], bbox[6]},
        {bbox[1], bbox[5], bbox[6]},
    }) do
        local sx, sy, v = utility.world_to_screen(c[1], c[2], c[3])
        if v then
            vis = true
            mnx, mny, mxx, mxy = min(mnx, sx), min(mny, sy), max(mxx, sx), max(mxy, sy)
        end
    end
    if not vis then
        return nil
    end
    return mnx, mny, mxx, mxy, (mnx + mxx) * 0.5
end

function M.draw_screen_box(mnx, mny, mxx, mxy, col)
    if not mnx then
        return
    end
    local w, h = mxx - mnx, mxy - mny
    if w > 0 and h > 0 then
        draw.rect(mnx, mny, w, h, col, 0, 1.5)
    end
end

function M.draw_screen_chams(mnx, mny, mxx, mxy, color, style, outline_color)
    if not mnx then
        return
    end
    local w, h = mxx - mnx, mxy - mny
    if w <= 0 or h <= 0 then
        return
    end
    if style == 1 then
        draw.rect(mnx, mny, w, h, outline_color or color, 0, 1.5)
    else
        draw.rect_filled(mnx, mny, w, h, color)
        if outline_color then
            draw.rect(mnx, mny, w, h, outline_color, 0, 1.5)
        end
    end
end

function M.draw_vm_body_chams(vm, color, style, outline_color)
    if not vm or not vm.FindFirstChild then
        return
    end
    for _, bn in ipairs(cache.cham_bone_list or cache.bone_list) do
        local part = vm:FindFirstChild(bn)
        if part and part.Position and part.Size then
            local sz = part.Size
            if (sz.X or sz.x or 0) > 0 then
                M.draw_part_hull_cached(part, color, style, outline_color)
            end
        end
    end
end

function M.draw_bone_chams(bones, color, style, outline_color)
    if not bones then
        return
    end
    local bone_list = cache.cham_bone_list or cache.bone_list
    for _, bn in ipairs(bone_list) do
        local bp = bones[bn]
        if bp and bp.hx and bp.hy then
            local cx, cy, cz = bp.x, bp.y, bp.z
            local sx_c, sy_c, vis = utility.world_to_screen(cx, cy, cz)
            local sx_t, sy_t, vt = utility.world_to_screen(cx, cy + bp.hy, cz)
            local sx_r, sy_r, vr = utility.world_to_screen(cx + bp.hx, cy, cz)
            if vis and vt and vr then
                local h = math.abs(sy_t - sy_c) * 2
                local w = math.abs(sx_r - sx_c) * 2
                if h < 2 then
                    h = 4
                end
                if w < 2 then
                    w = 4
                end
                local bx = sx_c - w * 0.5
                local by = sy_c - h * 0.5
                if style == 1 then
                    draw.rect(bx, by, w, h, outline_color or color, 1.5)
                else
                    draw.rect_filled(bx, by, w, h, color)
                    if outline_color then
                        draw.rect(bx, by, w, h, outline_color, 1.5)
                    end
                end
            end
        end
    end
end

function M.draw_bbox_chams(bbox, color, style, outline_color)
    if not bbox then
        return
    end
    local screen_points = {}
    local corners = {
        {bbox[1], bbox[2], bbox[3]},
        {bbox[4], bbox[2], bbox[3]},
        {bbox[4], bbox[5], bbox[3]},
        {bbox[1], bbox[5], bbox[3]},
        {bbox[1], bbox[2], bbox[6]},
        {bbox[4], bbox[2], bbox[6]},
        {bbox[4], bbox[5], bbox[6]},
        {bbox[1], bbox[5], bbox[6]},
    }
    for _, c in ipairs(corners) do
        local sx, sy, v = utility.world_to_screen(c[1], c[2], c[3])
        if v then
            screen_points[#screen_points + 1] = {sx, sy}
        end
    end
    if #screen_points < 3 then
        return
    end
    local hull = draw.compute_hull(screen_points)
    if not hull then
        return
    end
    if style == 1 then
        draw.poly_closed(hull, outline_color or color, 1.5)
    else
        draw.poly_filled(hull, color)
        if outline_color then
            draw.poly_closed(hull, outline_color, 1.5)
        end
    end
end

function M.part_screen_pos(part)
    if not part then
        return nil
    end
    local pos = part.Position or part.position
    if not pos then
        return nil
    end
    local sx, sy, vis = utility.world_to_screen(pos.X, pos.Y, pos.Z)
    if not vis then
        return nil
    end
    return sx, sy
end

function M.part_screen_radius(part)
    if not part then
        return 3
    end
    local pos = part.Position or part.position
    local sz = part.Size or part.size
    if not pos or not sz then
        return 3
    end
    local hy = (sz.Y or 0) * 0.5
    local hx = (sz.X or 0) * 0.5
    local sx1, sy1, v1 = utility.world_to_screen(pos.X, pos.Y + hy, pos.Z)
    local sx2, sy2, v2 = utility.world_to_screen(pos.X, pos.Y - hy, pos.Z)
    if v1 and v2 then
        return sqrt((sx1 - sx2) ^ 2 + (sy1 - sy2) ^ 2) * 0.5
    end
    local sx3, sy3, v3 = utility.world_to_screen(pos.X + hx, pos.Y, pos.Z)
    local sx4, sy4, v4 = utility.world_to_screen(pos.X - hx, pos.Y, pos.Z)
    if v3 and v4 then
        return sqrt((sx3 - sx4) ^ 2 + (sy3 - sy4) ^ 2) * 0.5
    end
    return 3
end

function M.draw_part_hull_cached(part, color, style, outline_color)
    if not part then
        return
    end
    local pos = part.Position or part.position
    local sz = part.Size or part.size
    if not (pos and sz) then
        return
    end

    local now = utility.get_tick_count()
    local parent_name = part.Parent and part.Parent.Name or ""
    local key = tostring(part) .. ":" .. parent_name .. ":" .. (part.Name or "")
    local entry = hull_cache[key]
    local px = pos.X or pos.x
    local py = pos.Y or pos.y
    local pz = pos.Z or pos.z

    local function moved(e)
        if not e then
            return true
        end
        return math.abs(e.px - px) > HULL_MOVE_EPS
            or math.abs(e.py - py) > HULL_MOVE_EPS
            or math.abs(e.pz - pz) > HULL_MOVE_EPS
    end

    if entry and entry.hull and (now - entry.tick) < HULL_CACHE_MS
        and not moved(entry) and entry.style == style then
        local hull = entry.hull
        if style == 1 then
            draw.poly_closed(hull, outline_color or color, 1.5)
        else
            draw.poly_filled(hull, color)
            if outline_color then
                draw.poly_closed(hull, outline_color, 1.5)
            end
        end
        return
    end

    local hx = (sz.X or sz.x or 0) * 0.5
    local hy = (sz.Y or sz.y or 0) * 0.5
    local hz = (sz.Z or sz.z or 0) * 0.5
    local rv = part.RightVector or part.right_vector
    local uv = part.UpVector or part.up_vector
    local lv = part.LookVector or part.look_vector
    local pxv = pos.X or pos.x
    local pyv = pos.Y or pos.y
    local pzv = pos.Z or pos.z

    local corners = {}
    if rv and uv and lv and rv.X and uv.X and lv.X then
        corners = {
            {pxv + rv.X * -hx + uv.X * -hy + lv.X * -hz, pyv + rv.Y * -hx + uv.Y * -hy + lv.Y * -hz, pzv + rv.Z * -hx + uv.Z * -hy + lv.Z * -hz},
            {pxv + rv.X *  hx + uv.X * -hy + lv.X * -hz, pyv + rv.Y *  hx + uv.Y * -hy + lv.Y * -hz, pzv + rv.Z *  hx + uv.Z * -hy + lv.Z * -hz},
            {pxv + rv.X * -hx + uv.X *  hy + lv.X * -hz, pyv + rv.Y * -hx + uv.Y *  hy + lv.Y * -hz, pzv + rv.Z * -hx + uv.Z *  hy + lv.Z * -hz},
            {pxv + rv.X *  hx + uv.X *  hy + lv.X * -hz, pyv + rv.Y *  hx + uv.Y *  hy + lv.Y * -hz, pzv + rv.Z *  hx + uv.Z *  hy + lv.Z * -hz},
            {pxv + rv.X * -hx + uv.X * -hy + lv.X *  hz, pyv + rv.Y * -hx + uv.Y * -hy + lv.Y *  hz, pzv + rv.Z * -hx + uv.Z * -hy + lv.Z *  hz},
            {pxv + rv.X *  hx + uv.X * -hy + lv.X *  hz, pyv + rv.Y *  hx + uv.Y * -hy + lv.Y *  hz, pzv + rv.Z *  hx + uv.Z * -hy + lv.Z *  hz},
            {pxv + rv.X * -hx + uv.X *  hy + lv.X *  hz, pyv + rv.Y * -hx + uv.Y *  hy + lv.Y *  hz, pzv + rv.Z * -hx + uv.Z *  hy + lv.Z *  hz},
            {pxv + rv.X *  hx + uv.X *  hy + lv.X *  hz, pyv + rv.Y *  hx + uv.Y *  hy + lv.Y *  hz, pzv + rv.Z *  hx + uv.Z *  hy + lv.Z *  hz},
        }
    else
        corners = {
            {pxv - hx, pyv - hy, pzv - hz},
            {pxv + hx, pyv - hy, pzv - hz},
            {pxv - hx, pyv + hy, pzv - hz},
            {pxv + hx, pyv + hy, pzv - hz},
            {pxv - hx, pyv - hy, pzv + hz},
            {pxv + hx, pyv - hy, pzv + hz},
            {pxv - hx, pyv + hy, pzv + hz},
            {pxv + hx, pyv + hy, pzv + hz},
        }
    end

    local screen_points = {}
    for _, cp in ipairs(corners) do
        local sx, sy, v
        if draw and draw.world_to_screen then
            sx, sy, v = draw.world_to_screen(cp[1], cp[2], cp[3])
        else
            sx, sy, v = utility.world_to_screen(cp[1], cp[2], cp[3])
        end
        if v then
            screen_points[#screen_points + 1] = {sx, sy}
        end
    end
    if #screen_points < 3 then
        return
    end
    local hull = draw.compute_hull(screen_points)
    if not hull then
        return
    end

    hull_cache[key] = {
        hull = hull,
        tick = now,
        px = px,
        py = py,
        pz = pz,
        style = style
    }
    trim_hull_cache()

    if style == 1 then
        draw.poly_closed(hull, outline_color or color, 1.5)
    else
        draw.poly_filled(hull, color)
        if outline_color then
            draw.poly_closed(hull, outline_color, 1.5)
        end
    end
end

function M.draw_3d_box(bbox, col)
    if not bbox then
        return
    end
    local bb = {
        {bbox[1], bbox[2], bbox[3]},
        {bbox[4], bbox[2], bbox[3]},
        {bbox[4], bbox[5], bbox[3]},
        {bbox[1], bbox[5], bbox[3]},
        {bbox[1], bbox[2], bbox[6]},
        {bbox[4], bbox[2], bbox[6]},
        {bbox[4], bbox[5], bbox[6]},
        {bbox[1], bbox[5], bbox[6]}
    }
    local bb2, av = {}, false
    for i = 1, 8 do
        local sx, sy, vis = utility.world_to_screen(bb[i][1], bb[i][2], bb[i][3])
        bb2[i] = {sx, sy, vis}
        if vis then
            av = true
        end
    end
    if av then
        local edg = {{1, 2}, {2, 3}, {3, 4}, {4, 1}, {5, 6}, {6, 7}, {7, 8}, {8, 5}, {1, 5}, {2, 6}, {3, 7}, {4, 8}}
        for _, e in ipairs(edg) do
            local c1, c2 = bb2[e[1]], bb2[e[2]]
            if c1[3] and c2[3] then
                draw.line(c1[1], c1[2], c2[1], c2[2], col, 1.5)
            end
        end
    end
end

function M.draw_part_hull(b, color, style, outline_color)
    if not (b and b.Position and b.Size) then return end
    
    local pos = b.position or b.Position
    local sz = b.size or b.Size
    local rv, uv, lv = b.right_vector, b.up_vector, b.look_vector
    
    if pos and sz and rv and uv and lv then
        local hx, hy, hz = sz.x * 0.5, sz.y * 0.5, sz.z * 0.5
        local corners = {
            pos + rv * -hx + uv * -hy + lv * -hz,
            pos + rv *  hx + uv * -hy + lv * -hz,
            pos + rv * -hx + uv *  hy + lv * -hz,
            pos + rv *  hx + uv *  hy + lv * -hz,
            pos + rv * -hx + uv * -hy + lv *  hz,
            pos + rv *  hx + uv * -hy + lv *  hz,
            pos + rv * -hx + uv *  hy + lv *  hz,
            pos + rv *  hx + uv *  hy + lv *  hz
        }
        local screen_points = {}
        for _, cp in ipairs(corners) do
            local sx, sy, v = draw.world_to_screen(cp.x, cp.y, cp.z)
            if v then
                screen_points[#screen_points + 1] = {sx, sy}
            end
        end
        if #screen_points >= 3 then
            local hull = draw.compute_hull(screen_points)
            if style == 1 then
                draw.poly_closed(hull, outline_color or color, 1.5)
            else
                draw.poly_filled(hull, color)
                if outline_color then
                    draw.poly_closed(hull, outline_color, 1.5)
                end
            end
        end
    end
end

function M.draw_box(bx, by, bw, bh, col, fill, btype, bbox)
    if fill then
        local fc = s.box_fill_color
        draw.rect_filled(bx, by, bw, bh, {fc[1], fc[2], fc[3], s.box_fill_opacity * 0.01})
    end
    if btype == BOX_TYPE.STANDARD then
        draw.rect(bx, by, bw, bh, col, 0, 1)
    elseif btype == BOX_TYPE.CORNER then
        local cl = min(bw, bh) * 0.25
        draw.line(bx, by, bx + cl, by, col, 2)
        draw.line(bx, by, bx, by + cl, col, 2)
        draw.line(bx + bw - cl, by, bx + bw, by, col, 2)
        draw.line(bx + bw, by, bx + bw, by + cl, col, 2)
        draw.line(bx, by + bh - cl, bx, by + bh, col, 2)
        draw.line(bx, by + bh, bx + cl, by + bh, col, 2)
        draw.line(bx + bw - cl, by + bh, bx + bw, by + bh, col, 2)
        draw.line(bx + bw, by + bh - cl, bx + bw, by + bh, col, 2)
    elseif btype == BOX_TYPE.THREE_D and bbox then
        M.draw_3d_box(bbox, col)
    end
end

function M.draw_segmented_line(sx, sy, ex, ey, col, style)
    if style == VIEW_LINE_STYLE.SOLID then
        draw.line(sx, sy, ex, ey, col, 2)
    elseif style == VIEW_LINE_STYLE.DASHED then
        for i = 0, 4 do
            local t1, t2 = i / 5, (i + 0.5) / 5
            draw.line(sx + (ex - sx) * t1, sy + (ey - sy) * t1, sx + (ex - sx) * t2, sy + (ey - sy) * t2, col, 2)
        end
    elseif style == VIEW_LINE_STYLE.FADE then
        for i = 0, 19 do
            local t1, t2 = i / 20, (i + 1) / 20
            draw.line(
                sx + (ex - sx) * t1,
                sy + (ey - sy) * t1,
                sx + (ex - sx) * t2,
                sy + (ey - sy) * t2,
                {col[1], col[2], col[3], col[4] * (1 - t1)},
                2
            )
        end
    end
end

function M.draw_tracer(ox, oy, tx, ty, col, style)
    if style == TRACER_STYLE.SOLID then
        draw.line(ox, oy, tx, ty, col, 1.5)
    elseif style == TRACER_STYLE.DASHED then
        for i = 0, 9 do
            local t1, t2 = i / 10, (i + 0.5) / 10
            draw.line(
                ox + (tx - ox) * t1, oy + (ty - oy) * t1,
                ox + (tx - ox) * t2, oy + (ty - oy) * t2,
                col, 1.5
            )
        end
    elseif style == TRACER_STYLE.DOTTED then
        for i = 0, 19 do
            local t = i / 20
            draw.circle_filled(ox + (tx - ox) * t, oy + (ty - oy) * t, 2, col)
        end
    end
 end

return M

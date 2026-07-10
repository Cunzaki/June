-- GPU instance chams with a double-buffer applied set.
-- front (owner.applied) = addresses currently stamped
-- back  (fresh collect) = addresses that SHOULD be chammed this tick
-- Removals → RevertChams + rebuild all active owners.
-- Additions → incremental ApplyChamsToInstance only.

local settings = June.require("core.settings")
local env = June.require("core.env")

local M = {}

M.MODE_LABELS = { "Fill", "Wireframe", "Fill Glow", "Wireframe Glow" }
M.COLOR_LABELS = { "Default", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan" }

local PART_CLASSES = {
    Part = true,
    MeshPart = true,
    WedgePart = true,
    CornerWedgePart = true,
    TrussPart = true,
    UnionOperation = true,
    NegateOperation = true,
}

local owners = {}
local owner_order = {}
local rebuild_busy = false
local last_global_rebuild = 0
local MIN_REBUILD_GAP_MS = 400

function M.available()
    return exploits ~= nil
        and type(exploits.ApplyChamsToInstance) == "function"
        and type(exploits.RevertChams) == "function"
        and type(exploits.SetChamsMode) == "function"
        and type(exploits.SetChamsColor) == "function"
end

function M.is_part(inst)
    if not inst then
        return false
    end
    local cn = inst.ClassName or inst.class_name
    if PART_CLASSES[cn] then
        return true
    end
    return env.safe_call(function()
        if inst.is_a then
            return inst:is_a("BasePart")
        end
        if inst.IsA then
            return inst:IsA("BasePart")
        end
        return false
    end) == true
end

function M.instance_addr(inst)
    if not inst then
        return nil
    end
    return inst.Address or inst.address
end

function M.color_visible_for_mode(mode)
    mode = tonumber(mode) or 0
    return mode == 2 or mode == 3
end

function M.mode_index(id, default)
    return settings.combo_index(id, M.MODE_LABELS, default or 0)
end

function M.color_index(id, default)
    return settings.combo_index(id, M.COLOR_LABELS, default or 0)
end

function M.multicombo_selected(id, index)
    local t = settings.get(id)
    if type(t) ~= "table" then
        return false
    end
    local v = t[index]
    return v == true or v == 1
end

function M.multicombo_any(id, count)
    for i = 1, count do
        if M.multicombo_selected(id, i) then
            return true
        end
    end
    return false
end

function M.multicombo_defaults(count)
    local out = {}
    for i = 1, count do
        out[i] = false
    end
    return out
end

local function now_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function push_style(mode, color)
    pcall(function()
        exploits.SetChamsMode(mode or 0)
    end)
    pcall(function()
        exploits.SetChamsColor(color or 0)
    end)
end

local function any_other_active(except_id)
    for _, oid in ipairs(owner_order) do
        local o = owners[oid]
        if o and oid ~= except_id and o.is_active() then
            return true
        end
    end
    return false
end

local function sets_equal(a, b)
    for k in pairs(a) do
        if not b[k] then
            return false
        end
    end
    for k in pairs(b) do
        if not a[k] then
            return false
        end
    end
    return true
end

local function has_removed(prev, fresh)
    for addr in pairs(prev) do
        if not fresh[addr] then
            return true
        end
    end
    return false
end

local function apply_one(inst, applied)
    if not M.available() or not inst then
        return false
    end
    if not M.is_part(inst) then
        return false
    end
    local addr = M.instance_addr(inst)
    if not addr then
        return false
    end
    if applied[addr] then
        return true
    end
    local ok, result = pcall(exploits.ApplyChamsToInstance, inst)
    if ok and result then
        applied[addr] = true
        return true
    end
    return false
end

function M.cham_part(inst, applied)
    return apply_one(inst, applied or {})
end

function M.find_main_part(model, hints)
    if not model or not env.is_valid(model) then
        return nil
    end
    hints = hints or {}
    for i = 1, #hints do
        local name = hints[i]
        local p = env.safe_call(function()
            return model:FindFirstChild(name)
        end)
        if p and M.is_part(p) then
            return p
        end
    end
    local children = env.safe_call(function()
        return model:GetChildren()
    end) or {}
    for _, c in ipairs(children) do
        if M.is_part(c) then
            return c
        end
    end
    if M.is_part(model) then
        return model
    end
    return nil
end

function M.cham_entry_part(entry, applied)
    if not entry then
        return false
    end
    local part = entry.main_part or entry.anchor
    if part and env.is_valid(part) and M.is_part(part) then
        return apply_one(part, applied)
    end
    local model = entry.obj or entry.inst or entry.viewmodel
    if not model or not env.is_valid(model) then
        return false
    end
    local hints = {"Root", "Main", "HumanoidRootPart", "Cam"}
    if entry.item then
        if entry.item.priority_part then
            table.insert(hints, 1, entry.item.priority_part)
        end
        if entry.item.anchor_part then
            table.insert(hints, 1, entry.item.anchor_part)
        end
    end
    local main = M.find_main_part(model, hints)
    if main then
        entry.main_part = main
        return apply_one(main, applied)
    end
    return false
end

function M.register_owner(id, opts)
    opts = opts or {}
    if not owners[id] then
        owner_order[#owner_order + 1] = id
    end
    owners[id] = {
        id = id,
        applied = {},
        was_active = false,
        is_active = opts.is_active or function()
            return false
        end,
        style = opts.style or function()
            return 0, 0
        end,
        collect = opts.collect or function(_back)
        end,
        last_rescan = 0,
        rescan_ms = opts.rescan_ms or 500,
    }
    return owners[id]
end

function M.get_owner(id)
    return owners[id]
end

local function apply_owner_into(owner, into)
    if not owner or not owner.is_active() then
        return
    end
    local mode, color = owner.style()
    push_style(mode, color)
    pcall(owner.collect, into)
end

function M.rebuild_all()
    if not M.available() or rebuild_busy then
        return false
    end
    local now = now_ms()
    if last_global_rebuild ~= 0 and (now - last_global_rebuild) < MIN_REBUILD_GAP_MS then
        return false
    end
    last_global_rebuild = now
    rebuild_busy = true

    pcall(function()
        exploits.RevertChams()
    end)

    for _, id in ipairs(owner_order) do
        local owner = owners[id]
        if owner then
            owner.applied = {}
            owner.last_rescan = 0
        end
    end

    for _, id in ipairs(owner_order) do
        local owner = owners[id]
        if owner and owner.is_active() then
            local back = {}
            apply_owner_into(owner, back)
            owner.applied = back
            owner.was_active = true
        elseif owner then
            owner.was_active = false
        end
    end

    rebuild_busy = false
    return true
end

function M.revert_all()
    if not M.available() then
        return
    end
    pcall(function()
        exploits.RevertChams()
    end)
    last_global_rebuild = now_ms()
    for _, id in ipairs(owner_order) do
        local owner = owners[id]
        if owner then
            owner.applied = {}
            owner.was_active = false
            owner.last_rescan = 0
        end
    end
end

function M.clear_owner(id, rebuild_others)
    local owner = owners[id]
    if not owner then
        return
    end
    local had = owner.was_active or next(owner.applied) ~= nil
    owner.applied = {}
    owner.was_active = false
    owner.last_rescan = 0
    if not had or rebuild_others == false then
        return
    end
    if any_other_active(id) then
        M.rebuild_all()
    else
        M.revert_all()
    end
end

function M.refresh_owner_style(id)
    local owner = owners[id]
    if not owner then
        return
    end
    if not owner.is_active() then
        M.clear_owner(id)
        return
    end
    -- Style change must re-stamp; one global rebuild keeps multi-color owners stable.
    M.rebuild_all()
end

-- Collect desired address sets for every owner without applying.
-- Returns: need_rebuild, pending_adds { [owner_id] = { addr = true, ... } }
local function collect_all_backs(force)
    local now = now_ms()
    local need_rebuild = false
    local pending_adds = {}

    for _, id in ipairs(owner_order) do
        local owner = owners[id]
        if not owner then
            goto continue
        end

        if not owner.is_active() then
            if owner.was_active or next(owner.applied) ~= nil then
                need_rebuild = true
                owner.applied = {}
                owner.was_active = false
                owner.last_rescan = 0
                owner.missing = {}
            end
            goto continue
        end

        local due = force
            or owner.last_rescan == 0
            or (now - owner.last_rescan) >= owner.rescan_ms
        if not due then
            owner.was_active = true
            goto continue
        end

        owner.last_rescan = now
        owner.was_active = true
        owner.missing = owner.missing or {}

        local back = {}
        -- Collect only — apply phase sets style per owner.
        local ok = pcall(owner.collect, back)
        if not ok then
            goto continue
        end

        -- Grace: keep addresses missing for one rescan to avoid edge flicker.
        local front = owner.applied
        for addr in pairs(front) do
            if not back[addr] then
                local misses = (owner.missing[addr] or 0) + 1
                owner.missing[addr] = misses
                if misses < 2 then
                    back[addr] = true
                end
            else
                owner.missing[addr] = nil
            end
        end
        for addr in pairs(back) do
            if front[addr] then
                owner.missing[addr] = nil
            end
        end

        if sets_equal(front, back) then
            goto continue
        end

        if has_removed(front, back) or next(front) == nil then
            need_rebuild = true
            owner._pending_back = back
        else
            local adds = {}
            for addr in pairs(back) do
                if not front[addr] then
                    adds[addr] = true
                end
            end
            if next(adds) then
                pending_adds[id] = adds
                owner._pending_back = back
            end
        end
        ::continue::
    end

    return need_rebuild, pending_adds
end

-- Single per-frame sync for all owners.
-- Prevents multi-color flashing: at most one RevertChams, then each owner
-- pushes its own mode/color and stamps its parts in order.
function M.sync_all(force)
    if not M.available() or rebuild_busy then
        return
    end

    local need_rebuild, pending_adds = collect_all_backs(force)

    if need_rebuild then
        if M.rebuild_all() then
            for _, id in ipairs(owner_order) do
                local owner = owners[id]
                if owner then
                    owner._pending_back = nil
                    owner.missing = {}
                end
            end
        end
        return
    end

    -- Incremental additions only — stamp with each owner's style, never revert.
    for _, id in ipairs(owner_order) do
        local adds = pending_adds[id]
        local owner = owners[id]
        if owner and adds and next(adds) then
            local mode, color = owner.style()
            push_style(mode, color)
            local front = owner.applied
            for addr in pairs(adds) do
                if not front[addr] then
                    pcall(exploits.ApplyChamsToInstance, addr)
                    front[addr] = true
                end
            end
            if owner._pending_back then
                owner.applied = owner._pending_back
                owner._pending_back = nil
            else
                owner.applied = front
            end
        end
    end
end

function M.sync_owner(id, force)
    -- Always coalesce through sync_all so multi-owner colors stay stable.
    M.sync_all(force == true)
end

function M.wire_style_controls(owner_id, mode_id, color_id)
    if not menu or not menu.set_visible then
        return
    end

    local function sync_color_vis()
        local mode = M.mode_index(mode_id, 0)
        pcall(menu.set_visible, color_id, M.color_visible_for_mode(mode))
    end

    settings.on_change(mode_id, function()
        sync_color_vis()
        M.refresh_owner_style(owner_id)
    end)
    settings.on_change(color_id, function()
        M.refresh_owner_style(owner_id)
    end)
    sync_color_vis()
end

return M

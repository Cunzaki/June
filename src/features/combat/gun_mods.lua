local settings = OperationOne.require("core.settings")
local gc = OperationOne.require("game.gc_weapon_mods")

local M = {}

local s = settings.s
local RETRY_MS = 750
local RETRY_MAX_MS = 30000

M._apply_dirty = false
M._force_apply = false
M._defer_until = 0
M._retry_until = 0
M._was_enabled = false
M._status = "GC: idle"
M._logged_apply = false
M._callbacks_ready = false
M._last_mod_sig = ""

local MOD_IDS = {
    "gm_no_recoil",
    "gm_no_spread",
    "gm_firerate_enabled",
    "gm_speed_enabled",
    "gm_reload_enabled",
    "gm_accuracy_enabled",
    "gm_ads_enabled",
    "gm_firerate",
    "gm_speed_mult",
    "gm_reload_mult",
}

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function build_mods()
    local mods = {}

    if s.gm_no_recoil then
        mods.recoil_up = 0
        mods.recoil_side = 0
    end

    if s.gm_no_spread then
        mods.spread = 0
    end

    if s.gm_firerate_enabled then
        mods.firerate = s.gm_firerate or 1200
    end

    if s.gm_speed_enabled then
        mods.speed = s.gm_speed_mult or 1.2
    end

    if s.gm_reload_enabled then
        mods.reload_speed = s.gm_reload_mult or 2.5
    end

    if s.gm_accuracy_enabled then
        mods.accuracy = 25
    end

    if s.gm_ads_enabled then
        mods.ads = 0
    end

    return mods
end

local function payload_signature(mods)
    local keys = {}
    for k in pairs(mods) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        parts[i] = k .. "=" .. tostring(mods[k])
    end
    return table.concat(parts, ";")
end

local function has_active_mods()
    return s.gm_no_recoil
        or s.gm_no_spread
        or s.gm_firerate_enabled
        or s.gm_speed_enabled
        or s.gm_reload_enabled
        or s.gm_accuracy_enabled
        or s.gm_ads_enabled
end

function M.schedule_apply(delay_ms)
    M._apply_dirty = true
    M._force_apply = true
    local now = tick_ms()
    local until_ms = now + (delay_ms or 400)
    if until_ms > M._defer_until then
        M._defer_until = until_ms
    end
    if M._retry_until <= now then
        M._retry_until = now + RETRY_MAX_MS
    end
end

function M.try_apply(silent)
    if not s.gun_mods_enabled or not has_active_mods() then
        M._status = "GC: off"
        M._apply_dirty = false
        M._force_apply = false
        return false
    end

    local mods = build_mods()
    if not next(mods) then
        return false
    end

    if not M._force_apply and not M._apply_dirty then
        M._status = gc.status_text()
        return true
    end

    local ok, count, msg = gc.apply_weapon(mods, silent)
    if ok then
        M._apply_dirty = false
        M._force_apply = false
        M._defer_until = 0
        M._retry_until = 0
        M._status = gc.status_text()
        if not silent and not M._logged_apply then
            M._logged_apply = true
            print("[OperationOne] Gun mods: " .. (msg or (count .. " nodes patched")))
        end
        return true
    end

    M._status = msg or "GC: warming"
    M._apply_dirty = true
    M._force_apply = true
    M._defer_until = tick_ms() + RETRY_MS
    return false
end

local function on_mod_changed()
    if s.gun_mods_enabled then
        M.schedule_apply(150)
    end
end

function M.register_callbacks()
    if M._callbacks_ready then
        return
    end

    settings.on_change("gun_mods_enabled", function(enabled)
        if enabled then
            gc.refresh_cache()
            M._logged_apply = false
            M.schedule_apply(500)
            print("[OperationOne] Gun mods enabled — warming GC...")
        else
            M._apply_dirty = false
            M._force_apply = false
            M._defer_until = 0
            M._retry_until = 0
            M._status = "GC: off"
            M._logged_apply = false
        end
    end)

    for _, id in ipairs(MOD_IDS) do
        settings.on_change(id, on_mod_changed)
    end

    M._callbacks_ready = true
end

function M.update(_dt)
    local enabled = s.gun_mods_enabled and has_active_mods()

    if enabled and not M._was_enabled then
        gc.refresh_cache()
        M._logged_apply = false
        M.schedule_apply(500)
    elseif not enabled and M._was_enabled then
        M._apply_dirty = false
        M._force_apply = false
        M._status = "GC: off"
        M._logged_apply = false
    end

    M._was_enabled = enabled

    if not s.gun_mods_enabled then
        return
    end

    local mods = build_mods()
    local sig = payload_signature(mods)
    if sig ~= M._last_mod_sig then
        M._last_mod_sig = sig
        if has_active_mods() then
            M.schedule_apply(150)
        end
    end

    if not has_active_mods() then
        M._apply_dirty = false
        M._force_apply = false
        return
    end

    local now = tick_ms()

    if not M._apply_dirty then
        return
    end

    if now < M._defer_until then
        return
    end

    if M._retry_until > 0 and now > M._retry_until then
        M._apply_dirty = false
        M._force_apply = false
        M._status = "GC: timeout — toggle mods again"
        return
    end

    M.try_apply(true)
end

function M.get_status()
    return M._status
end

function M.register_menu()
    local menu_util = OperationOne.require("core.menu_util")
    local gc_mod = OperationOne.require("game.gc_weapon_mods")
    menu_util.ensure_groups()
    menu.add_button(menu_util.TAB, "Combat", "gm_dump_gc", "Dump GC Keys", function()
        local ok, count, msg = gc_mod.dump_keys("op_one_gc_dump.txt")
        print("[OperationOne] " .. (msg or (ok and "dump ok" or "dump failed")) .. " (" .. tostring(count) .. ")")
    end, { parent = "gun_mods_enabled" })
    M.register_callbacks()
end

return M

local settings = June.require("core.settings")
local gc = June.require("game.gc_weapon_mods")
local env = June.require("core.env")

local M = {}

local P = "june_gunmods_enabled"
local PERSIST_MS = 500
local RETRY_MS = 1000
local RETRY_MAX_MS = 30000

M._apply_dirty = false
M._defer_until = 0
M._retry_until = 0
M._last_persist = 0
M._status = "Off"

local function tick_ms()
    return utility and utility.get_tick_count and utility.get_tick_count() or 0
end

local function build_weapon_mods()
    local mods = {}

    if settings.enabled("june_gm_recoil") then
        mods.recoil_up = 0.01
        mods.recoil_side = 0.01
        mods.prone_recoil = 0.01
    end

    if settings.enabled("june_gm_firerate") then
        mods.firerate = settings.num("june_gm_firerate_val", 300)
    end

    if settings.enabled("june_gm_damage") then
        mods.damage = settings.num("june_gm_damage_val", 100)
    end

    if settings.enabled("june_gm_range") then
        mods.range = settings.num("june_gm_range_val", 80)
    end

    if settings.enabled("june_gm_destructive") then
        mods.destructive = settings.num("june_gm_destructive_val", 20) * 0.1
    end

    if settings.enabled("june_gm_lightweight") then
        mods.speed = settings.num("june_gm_lightweight_val", 100) * 0.01
    end

    return mods
end

local function build_exploit_mods()
    local mods = {}

    if settings.enabled("june_gc_speed_mult") then
        mods.speed_multiplier = settings.num("june_gc_speed_mult_val", 115) * 0.01
    end

    if settings.enabled("june_gc_infinite_ammo") then
        mods.fuel = 999
    end

    return mods
end

local function build_all_mods()
    local mods = build_weapon_mods()
    for k, v in pairs(build_exploit_mods()) do
        mods[k] = v
    end
    return mods
end

local function set_status(text)
    M._status = text or "—"
    if menu and menu.set then
        pcall(menu.set, "june_gm_status", M._status)
    end
end

local function schedule_apply(delay_ms)
    M._apply_dirty = true
    local now = tick_ms()
    local until_ms = now + (delay_ms or 400)
    if until_ms > M._defer_until then
        M._defer_until = until_ms
    end
    if M._retry_until <= now then
        M._retry_until = now + RETRY_MAX_MS
    end
end

function M.reset_mods()
    gc.reset_session()
    set_status("Off — re-equip to reset stats")
end

function M.try_apply(silent)
    if not settings.enabled(P) then
        return false
    end
    if not env.get_local_player() then
        set_status("Join match")
        return false
    end

    local mods = build_all_mods()
    if not next(mods) then
        M.reset_mods()
        M._apply_dirty = false
        set_status("No mods selected")
        return false
    end

    local ok, count, msg = gc.apply_many(mods)
    if ok then
        M._apply_dirty = false
        M._retry_until = 0
        set_status(msg or (tostring(count) .. " nodes"))
        if not silent then
            print("[June] Gun mods: " .. tostring(msg))
        end
        return true
    end

    M._apply_dirty = true
    M._defer_until = tick_ms() + RETRY_MS
    set_status(msg or "Warming…")
    return false
end

function M.update(_dt)
    if not settings.enabled(P) then
        return
    end

    local now = tick_ms()

    if M._apply_dirty then
        if now >= M._defer_until then
            if M._retry_until > 0 and now > M._retry_until then
                M._apply_dirty = false
                set_status("Failed — re-equip gun")
                return
            end
            M.try_apply(true)
        end
    end

    if now - M._last_persist >= PERSIST_MS then
        M._last_persist = now
        local mods = build_all_mods()
        if next(mods) then
            gc.apply_many(mods)
        end
    end
end

function M.on_setting_changed()
    if settings.enabled(P) then
        gc.reset_session()
        schedule_apply(300)
    else
        M.reset_mods()
        M._apply_dirty = false
        set_status("Off")
    end
end

function M.init()
    if not gc.available() then
        set_status("GC unavailable")
        return
    end
    gc.refresh_cache()
    set_status(gc.status_text())

    local ids = {
        P,
        "june_gm_recoil",
        "june_gm_firerate", "june_gm_firerate_val",
        "june_gm_damage", "june_gm_damage_val",
        "june_gm_range", "june_gm_range_val",
        "june_gm_destructive", "june_gm_destructive_val",
        "june_gm_lightweight", "june_gm_lightweight_val",
        "june_gc_speed_mult", "june_gc_speed_mult_val",
        "june_gc_infinite_ammo",
    }
    for _, id in ipairs(ids) do
        settings.on_change(id, M.on_setting_changed)
    end

    if settings.enabled(P) then
        schedule_apply(500)
    end
end

return M

-- Operation One GC layer — safe single-key patches (dump: Items.load_instance, Animations_30842).
-- Weapon stats copy stats → states on equip. Character uses speed_multiplier (Audio_29057).

local debug = June.require("core.debug")
local env = June.require("core.env")

local M = {}

M.WEAPON_KEYS = {
    "recoil_up",
    "recoil_side",
    "firerate",
    "damage",
    "range",
    "destructive",
    "speed",
    "fuel",
    "prone_recoil",
}

M.CHARACTER_KEYS = {
    "speed_multiplier",
}

M.CLAMP = {
    recoil_up = {0.01, 5},
    recoil_side = {0.01, 5},
    firerate = {60, 400},
    damage = {1, 120},
    range = {1, 100},
    destructive = {0.5, 3},
    speed = {0.85, 1},
    fuel = {25, 999},
    prone_recoil = {0.01, 1},
    speed_multiplier = {1, 1.4},
}

M._last_node_count = 0
M._refreshed = false

local function has_api()
    return type(refreshgc) == "function"
        and type(getgc) == "function"
        and type(applygc) == "function"
end

local function clamp_key(key, value)
    local lim = M.CLAMP[key]
    local n = tonumber(value)
    if not n or not lim then
        return nil
    end
    if n < lim[1] then
        n = lim[1]
    elseif n > lim[2] then
        n = lim[2]
    end
    if key == "firerate" and n <= 0 then
        n = 60
    end
    return n
end

function M.available()
    return has_api()
end

function M.last_node_count()
    return M._last_node_count
end

function M.in_game()
    return env.get_local_player() ~= nil
end

function M.ensure_refresh()
    if not has_api() or not M.in_game() then
        return false
    end
    if not M._refreshed then
        pcall(refreshgc)
        M._refreshed = true
    end
    return true
end

function M.warm_keys(keys)
    if not has_api() then
        return 0
    end
    local count = 0
    local ok, result = pcall(getgc, keys)
    if ok and type(result) == "number" then
        count = result
    end
    if count > M._last_node_count then
        M._last_node_count = count
    end
    return count
end

function M.apply_one(key, value)
    if not has_api() or not M.in_game() then
        return false, 0
    end
    local v = clamp_key(key, value)
    if v == nil then
        return false, 0
    end

    M.ensure_refresh()
    M.warm_keys({key})

    local patched = 0
    local ok, result = pcall(applygc, {key}, {[key] = v})
    if ok and type(result) == "number" then
        patched = result
    end
    if patched > M._last_node_count then
        M._last_node_count = patched
    end
    return patched > 0, patched
end

function M.apply_many(mods)
    if not has_api() then
        return false, 0, "GC API unavailable"
    end
    if not M.in_game() then
        return false, 0, "Enter a match first"
    end
    if not mods or not next(mods) then
        return false, 0, "No modifiers selected"
    end

    M.ensure_refresh()

    local keys = {}
    for k in pairs(mods) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    M.warm_keys(keys)

    local total = 0
    local applied = 0
    for _, key in ipairs(keys) do
        local ok, n = M.apply_one(key, mods[key])
        if ok then
            applied = applied + 1
            total = total + n
        end
    end

    if applied > 0 then
        return true, total, string.format("%d key(s), %d node(s)", applied, total)
    end

    debug.warn_once("gun_mods:nodes", "GC warming — equip gun, enable mods, wait")
    return false, 0, "GC warming — equip gun"
end

function M.refresh_cache()
    if not has_api() or not M.in_game() then
        M._last_node_count = 0
        M._refreshed = false
        return 0
    end
    pcall(refreshgc)
    M._refreshed = true
    local count = M.warm_keys(M.WEAPON_KEYS)
    M.warm_keys(M.CHARACTER_KEYS)
    return count
end

function M.reset_session()
    M._refreshed = false
end

function M.status_text()
    if not has_api() then
        return "GC: unavailable"
    end
    return string.format("GC nodes: %d", M._last_node_count)
end

return M

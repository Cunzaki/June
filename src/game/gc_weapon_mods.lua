--[[ Operation One weapon mods — refreshgc → getgc(keys) → applygc(keys, values) ]]

local debug = OperationOne.require("core.debug")
local env = OperationOne.require("core.env")

local M = {}

M.WEAPON_STAT_KEYS = {
    "recoil_up",
    "recoil_side",
    "spread",
    "accuracy",
    "firerate",
    "reload_speed",
    "ads",
    "speed",
}

M.WEAPON_FIND_KEYS = {
    "recoil_up",
    "recoil_side",
    "spread",
    "accuracy",
    "firerate",
    "reload_speed",
    "ads",
    "speed",
    "trail_size",
    "pellets",
    "zoom",
    "mag_size",
    "damage",
    "range",
    "destructive",
}

M.ALLOWED = {}
for _, key in ipairs(M.WEAPON_STAT_KEYS) do
    M.ALLOWED[key] = true
end

M._last_node_count = 0

local function has_api()
    return type(refreshgc) == "function"
        and type(getgc) == "function"
        and type(applygc) == "function"
end

function M.available()
    return has_api()
end

function M.last_node_count()
    return M._last_node_count
end

function M.in_game()
    if env.get_local_player() ~= nil then
        return true
    end
    local ws = env.get_workspace()
    return ws ~= nil and ws:FindFirstChild("Viewmodels") ~= nil
end

local function sanitize_payload(mods)
    local out = {}
    for k, v in pairs(mods) do
        if M.ALLOWED[k] and v ~= nil then
            local num = tonumber(v)
            if num ~= nil then
                out[k] = num
            end
        end
    end
    return out
end

local function keys_for_payload(payload)
    local keys = {}
    for k in pairs(payload) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function warm_nodes(keys)
    local count = 0
    local ok, result = pcall(getgc, keys)
    if ok and type(result) == "number" then
        count = result
    end
    if count <= 0 then
        ok, result = pcall(getgc, M.WEAPON_FIND_KEYS)
        if ok and type(result) == "number" then
            count = result
        end
    end
    return count
end

local function patch_count(keys, payload)
    local patched = 0

    local ok, result = pcall(applygc, keys, payload)
    if ok and type(result) == "number" then
        patched = result
    end

    if patched <= 0 then
        ok, result = pcall(applygc, M.WEAPON_FIND_KEYS, payload)
        if ok and type(result) == "number" then
            patched = result
        end
    end

    if patched <= 0 then
        ok, result = pcall(applygc, payload)
        if ok and type(result) == "number" then
            patched = result
        end
    end

    return patched
end

function M.apply_weapon(mods, _quiet)
    if not has_api() then
        return false, 0, "GC API unavailable"
    end

    local payload = sanitize_payload(mods)
    if not next(payload) then
        return false, 0, "No modifiers selected"
    end

    if not M.in_game() then
        return false, 0, "Enter a match first"
    end

    pcall(refreshgc)

    local patch_keys = keys_for_payload(payload)
    warm_nodes(M.WEAPON_FIND_KEYS)
    warm_nodes(patch_keys)

    local patched = patch_count(patch_keys, payload)
    M._last_node_count = math.max(M._last_node_count, patched, warm_nodes(patch_keys))

    if patched > 0 then
        return true, patched, string.format("%d node(s) patched", patched)
    end

    debug.warn_once("gun_mods:nodes", "GC warming — enable master + a mod, wait a moment")
    return false, 0, "GC warming — wait a moment"
end

function M.apply(mods)
    return M.apply_weapon(mods)
end

function M.refresh_cache()
    if not has_api() or not M.in_game() then
        M._last_node_count = 0
        return 0
    end

    pcall(refreshgc)
    warm_nodes(M.WEAPON_FIND_KEYS)
    local count = warm_nodes(M.WEAPON_STAT_KEYS)
    M._last_node_count = count
    return count
end

function M.dump_keys(path)
    if type(dumpgc) ~= "function" then
        return false, 0, "dumpgc unavailable"
    end
    local ok, result = pcall(dumpgc, M.WEAPON_FIND_KEYS, path or "op_one_gc_dump.txt")
    if ok and type(result) == "number" then
        return true, result, "Dumped " .. result .. " entries"
    end
    return false, 0, "dumpgc failed"
end

function M.status_text()
    if not has_api() then
        return "GC: unavailable"
    end
    return string.format("GC nodes: %d", M._last_node_count)
end

return M

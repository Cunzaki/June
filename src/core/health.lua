local constants = June.require("core.constants")
local cache = June.require("core.cache")

local M = {}

local HEALTH_CACHE_TIMEOUT = constants.HEALTH_CACHE_TIMEOUT

local function safe_num(v)
    local n = tonumber(v)
    if n == nil then
        return nil
    end
    return n
end

local function entity_health(ep)
    if not ep then
        return nil, nil, nil
    end

    local ok_alive, is_alive = pcall(function()
        return ep.is_alive
    end)
    if ok_alive and is_alive == false then
        local max_hp = safe_num(ep.max_health) or 125
        return 0, max_hp, false
    end

    local ok_dead, is_dead = pcall(function()
        return ep.is_dead
    end)
    if ok_dead and is_dead == true then
        local max_hp = safe_num(ep.max_health) or 125
        return 0, max_hp, false
    end

    local ok_hp, hp = pcall(function()
        return ep.health
    end)
    local ok_mhp, mhp = pcall(function()
        return ep.max_health
    end)
    if ok_hp and hp ~= nil then
        hp = safe_num(hp)
        mhp = ok_mhp and safe_num(mhp) or 125
        if hp ~= nil then
            return hp, mhp or 125, hp > 0
        end
    end

    return nil, nil, nil
end

local function humanoid_health(char_data)
    if not char_data or not char_data.hum then
        return nil, nil, nil
    end
    local hum = char_data.hum
    local hp = safe_num(hum.Health)
    local mhp = safe_num(hum.MaxHealth)
    if hp == nil then
        return nil, nil, nil
    end
    return hp, mhp or 125, hp > 0
end

local function cache_health(name, hp, mhp)
    if not name or hp == nil then
        return hp, mhp
    end
    local now = os.clock()
    local entry = cache.health_cache[name]
    if not entry then
        cache.health_cache[name] = {health = hp, max_health = mhp or 125, updated_at = now}
        return hp, mhp
    end

    if hp < entry.health then
        entry.health = hp
        entry.max_health = mhp or entry.max_health or 125
        entry.updated_at = now
    elseif mhp and mhp > (entry.max_health or 0) then
        entry.max_health = mhp
    end

    if now - (entry.updated_at or 0) > HEALTH_CACHE_TIMEOUT and hp > entry.health then
        entry.health = hp
        entry.max_health = mhp or entry.max_health or 125
        entry.updated_at = now
    end

    return entry.health, entry.max_health
end

function M.is_viewmodel_dead(vm)
    if not vm then
        return true
    end

    local parent = vm.Parent
    if parent then
        if parent.Name == "Garbage" then
            return true
        end
        local grand = parent.Parent
        if grand and grand.Name == "Garbage" then
            return true
        end
    end

    local torso = vm:FindFirstChild("torso")
    if torso and torso.Transparency and torso.Transparency >= 1 then
        return true
    end

    local head = vm:FindFirstChild("head")
    if not head or not head.Position then
        return true
    end

    return false
end

function M.resolve(name, entity_obj, char_data, viewmodel)
    if M.is_viewmodel_dead(viewmodel) then
        cache_health(name, 0, 125)
        return 0, 125, false
    end

    local hp, mhp, alive = entity_health(entity_obj)
    if hp == nil then
        hp, mhp, alive = humanoid_health(char_data)
    end

    if hp == nil then
        hp, mhp = 100, 125
        alive = true
    end

    hp, mhp = cache_health(name, hp, mhp)
    alive = hp > 0 and not M.is_viewmodel_dead(viewmodel)
    return hp, mhp or 125, alive
end

function M.apply(entry, entity_obj, char_data)
    if not entry then
        return false
    end
    local hp, mhp, alive = M.resolve(entry.name, entity_obj, char_data, entry.viewmodel)
    entry.health = hp
    entry.max_health = mhp
    entry.is_alive = alive
    return alive
end

function M.enabled(s)
    if not s then
        return true
    end
    if s.health_check == false then
        return false
    end
    return true
end

function M.passes(s, entry)
    if not M.enabled(s) then
        return true
    end
    if not entry then
        return false
    end
    if entry.is_alive == false then
        return false
    end
    return (entry.health or 0) > 0 and not M.is_viewmodel_dead(entry.viewmodel)
end

function M.prune_cache(active_names)
    local now = os.clock()
    for name, entry in pairs(cache.health_cache) do
        if not active_names[name] or now - (entry.updated_at or 0) > HEALTH_CACHE_TIMEOUT * 4 then
            cache.health_cache[name] = nil
        end
    end
end

return M

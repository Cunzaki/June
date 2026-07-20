local M = {}

local cache = {}
local ready = false
local old_phys, old_send = nil, nil
local last_apply_t = 0

local FLAG_DEFAULTS = {
    PhysicsSenderMaxBandwidthBps = 38760,
    DataSenderRate = 60,
    S2PhysicsSenderRate = 15,
}

local function can_mem()
    return memory and type(memory.write) == "function"
end

local function can_fflag()
    return fflag and type(fflag.set_value) == "function"
end

function M.available()
    return can_mem() or can_fflag()
end

function M.refresh()
    cache = {}
    ready = false
    if not fflag or not fflag.is_scanned or not fflag.is_scanned() then return end
    local ok, all = pcall(fflag.get_all)
    if ok and type(all) == "table" then
        for i = 1, #all do
            local e = all[i]
            if e and e.name and e.address and e.address > 0 then
                cache[e.name] = { addr = e.address, original = e.original or e.value }
            end
        end
    end
    ready = next(cache) ~= nil
end

local function lookup(name)
    if cache[name] then return cache[name] end
    if not fflag or not fflag.find then return nil end
    local ok, hits = pcall(fflag.find, name)
    if ok and type(hits) == "table" and hits[1] and hits[1].address then
        local e = { addr = hits[1].address, original = hits[1].original or hits[1].value }
        cache[name] = e
        return e
    end
    return nil
end

function M.set_int(name, value)
    if not name then return false end
    if not ready then M.refresh() end
    local num = tonumber(value)
    if num == nil then return false end

    local e = lookup(name)
    if e and e.addr and can_mem() then
        local ok = pcall(memory.write, e.addr, "int32", num)
        if ok then return true end
    end
    if can_fflag() then
        return pcall(fflag.set_value, name, num) == true
    end
    return false
end

function M.apply_rates(physics_rate, sender_rate)
    local phys = tonumber(physics_rate) or 0
    local send = tonumber(sender_rate) or 60
    local bw = phys == 0 and 0 or 38760

    M.set_int("S2PhysicsSenderRate", phys)
    M.set_int("PhysicsSenderMaxBandwidthBps", bw)
    M.set_int("DataSenderRate", send)
    old_phys, old_send = phys, send
end

function M.reset_defaults()
    for name, val in pairs(FLAG_DEFAULTS) do
        M.set_int(name, val)
    end
    old_phys, old_send = nil, nil
    last_apply_t = 0
end

local function now()
    if utility and utility.get_time then return utility.get_time() end
    return os.clock()
end

-- Autosend pulse: choke physics for `window` seconds, then brief send burst.
function M.tick_movement(active, autosend_window)
    if not M.available() then return end
    if not active then
        if old_phys ~= nil or old_send ~= nil then
            M.reset_defaults()
        end
        return
    end

    local t = now()
    local window = tonumber(autosend_window) or 0.1
    if window < 0.05 then window = 0.05 end
    if window > 1 then window = 1 end

    local cycle = window + 0.1
    local phys, send = 0, 60
    if (t % cycle) > window then
        phys, send = 15, 60
    end

    if phys ~= old_phys or send ~= old_send or (t - last_apply_t) > 0.35 then
        M.apply_rates(phys, send)
        last_apply_t = t
    end
end

return M

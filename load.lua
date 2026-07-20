-- Load June (local bundled file first, then GitHub).
local REMOTE_URL = "https://raw.githubusercontent.com/Cunzaki/June/refs/heads/main/june.lua"

local LOCAL_PATHS = {
    "june.lua",
    "June/june.lua",
}

local function try_load_local()
    if not loadfile then
        return false
    end

    for i = 1, #LOCAL_PATHS do
        local fn = loadfile(LOCAL_PATHS[i])
        if fn then
            fn()
            return true
        end
    end

    return false
end

if not try_load_local() then
    utility.load_url(REMOTE_URL)
end

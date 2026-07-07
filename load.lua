local JUNE_URL = "https://raw.githubusercontent.com/Cunzaki/April-Operation-One/refs/heads/main/june.lua"

local ok, err = utility.load_url(JUNE_URL)
if not ok then
    print("[June] Load failed: " .. tostring(err))
else
    print("[June] Loaded from GitHub")
end

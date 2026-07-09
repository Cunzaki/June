local M = {}

M.CDN_BASE = "https://raw.githubusercontent.com/Cunzaki/June/refs/heads/main/assets"

local function digits(id)
    return id and tostring(id):match("(%d+)")
end

function M.gadget_png(asset_id)
    asset_id = digits(asset_id)
    if not asset_id then return nil end
    return M.CDN_BASE .. "/gadgets/" .. asset_id .. ".png"
end

function M.operator_png(asset_id)
    return M.gadget_png(asset_id)
end

return M

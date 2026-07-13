local M = {}

local EYE_OFFSET_Y = 2.5
local DEFAULT_STEPS = 8
local MIN_RADIUS = 0.1
local MAX_RADIUS = 1
local MAX_EXTEND_EXTRA = 7
local RING_Y_OFFSETS = {0, 1.25, -0.5}

function M.eye_offset_y()
    return EYE_OFFSET_Y
end

function M.clamp_radius(radius)
    radius = tonumber(radius) or 1
    if radius < MIN_RADIUS then return MIN_RADIUS end
    if radius > MAX_RADIUS then return MAX_RADIUS end
    return math.floor(radius * 100 + 0.5) / 100
end

function M.clamp_extend_extra(extra)
    extra = tonumber(extra) or MAX_EXTEND_EXTRA
    if extra < 0 then return 0 end
    if extra > MAX_EXTEND_EXTRA then return MAX_EXTEND_EXTRA end
    return math.floor(extra * 100 + 0.5) / 100
end

function M.is_visible_from(ox, oy, oz, tx, ty, tz)
    if raycast and raycast.is_visible then
        return raycast.is_visible(ox, oy + EYE_OFFSET_Y, oz, tx, ty, tz) == true
    end
    return true
end

function M.is_visible_from_pos(origin, target)
    if not origin or not target then return false end
    return M.is_visible_from(origin.x, origin.y, origin.z, target.x, target.y, target.z)
end

function M.search_peek_at_radius(origin, target_pos, radius, steps)
    if not origin or not target_pos then return nil end
    steps = steps or DEFAULT_STEPS

    for _, yoff in ipairs(RING_Y_OFFSETS) do
        local oy = origin.y + yoff
        for i = 0, steps - 1 do
            local angle = (i / steps) * math.pi * 2
            local cx = origin.x + math.cos(angle) * radius
            local cz = origin.z + math.sin(angle) * radius
            if M.is_visible_from(cx, oy, cz, target_pos.x, target_pos.y, target_pos.z) then
                return { x = cx, y = oy, z = cz }
            end
        end
    end

    return nil
end

local function build_radii(base, max_r, extend)
    if not extend then return { base } end
    local radii = {}
    local r = base
    while r < max_r - 0.08 do
        radii[#radii + 1] = r
        r = r + (r < 0.6 and 0.2 or 0.45)
    end
    radii[#radii + 1] = max_r
    return radii
end

local function search_peek(origin, target_pos, base_r, max_r, steps, extend)
    base_r = M.clamp_radius(base_r)
    local radii = build_radii(base_r, max_r, extend)

    local total = #radii
    for idx, radius in ipairs(radii) do
        local peek = M.search_peek_at_radius(origin, target_pos, radius, steps)
        if peek then
            return peek, radius, idx / total
        end
    end
    return nil, max_r, 1
end

function M.evaluate_manipulation(origin, target_pos, opts)
    opts = opts or {}
    local extend = opts.extend == true
    local base_r = M.clamp_radius(opts.base_radius or 1)
    local extra = extend and M.clamp_extend_extra(opts.extend_extra or 0) or 0
    local max_r = extend and (base_r + extra) or base_r
    local steps = opts.steps or DEFAULT_STEPS

    if not origin or not target_pos then
        return {
            state = "blocked", peek = nil, radius = base_r,
            base_radius = base_r, extend_active = false, scan_progress = 0,
        }
    end

    if M.is_visible_from_pos(origin, target_pos) then
        return {
            state = "direct", peek = nil, radius = base_r,
            base_radius = base_r, extend_active = false, scan_progress = 1,
        }
    end

    local peek, radius, progress = search_peek(origin, target_pos, base_r, max_r, steps, extend)
    if peek then
        return {
            state = "ready", peek = peek, radius = radius,
            base_radius = base_r, extend_active = extend and radius > base_r + 0.05,
            scan_progress = progress or 1,
        }
    end

    return {
        state = "blocked", peek = nil, radius = max_r,
        base_radius = base_r, extend_active = false, scan_progress = 1,
    }
end

function M.peek_track_origin(peek, muzzle, body)
    if not peek then return nil end
    local y = peek.y
    if muzzle and body then
        y = peek.y + (muzzle.y - body.y)
    else
        y = peek.y + EYE_OFFSET_Y
    end
    return { x = peek.x, y = y, z = peek.z }
end

return M

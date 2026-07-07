--[[ June debug — off by default. Set June.debug = true for logs. ]]

local M = {}

local seen_errors = {}
local frame_count = 0

function M.enabled()
    return June and June.debug == true
end

function M.verbose()
    return June and June.debug_verbose == true
end

function M.log(msg)
    if not M.enabled() then return end
    print("[June] " .. tostring(msg))
end

function M.warn(msg)
    if not M.enabled() then return end
    print("[June WARN] " .. tostring(msg))
end

function M.warn_once(key, msg)
    M.error_once(key, msg)
end

function M.error_once(key, err)
    key = tostring(key)
    if seen_errors[key] and not M.verbose() then return end
    seen_errors[key] = (seen_errors[key] or 0) + 1
    local count = seen_errors[key]
    local suffix = count > 1 and (" (x" .. count .. ")") or ""
    print("[June ERROR][" .. key .. "] " .. tostring(err) .. suffix)
    if debug and debug.traceback then
        print(debug.traceback(err, 2))
    end
end

function M.guard(key, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        M.error_once(key, a)
        return nil
    end
    return a, b, c
end

function M.tick_frame()
    frame_count = frame_count + 1
end

function M.traceback(err, level)
    if debug and debug.traceback then
        return debug.traceback(err, level or 2)
    end
    return tostring(err)
end

function M.register_frame_hook(fn)
    if type(fn) ~= "function" then
        M.error_once("frame_hook", "on_frame handler is not a function")
        return false
    end

    -- Vector only invokes global on_frame.
    -- callbacks.add / draw.callback stack on reload and draw everything twice.
    _G.on_frame = fn

    if draw then
        draw.callback = nil
    end

    return true
end

return M

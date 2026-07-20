-- Soft movement helpers. HRP velocity only — no WalkSpeed writes (AC-safe).

local env = June.require("core.env")

local M = {}

local BASE_PARTS = {
    Part = true, MeshPart = true, UnionOperation = true,
    WedgePart = true, CornerWedgePart = true, TrussPart = true,
}

local NOCLIP_PARTS = {
    "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "Head",
}

local DEFAULT_GRAVITY = 196.2

function M.delta_time()
    if utility and utility.get_delta_time then
        local dt = utility.get_delta_time()
        if dt and dt > 0 and dt <= 0.1 then return dt end
    end
    return 0.016
end

function M.key_down(code)
    return input and input.is_key_down and input.is_key_down(code)
end

function M.read_velocity(inst)
    if not inst then return 0, 0, 0 end
    local vel = inst.AssemblyLinearVelocity or inst.Velocity or inst.velocity
    if not vel then return 0, 0, 0 end
    return vel.X or vel.x or 0, vel.Y or vel.y or 0, vel.Z or vel.z or 0
end

function M.is_base_part(inst)
    if not inst then return false end
    if inst.is_a then
        local ok, yes = pcall(function() return inst:is_a("BasePart") end)
        if ok and yes then return true end
    end
    local cn = inst.ClassName or inst.class_name
    return BASE_PARTS[cn] == true
end

function M.find_part(char, name)
    if not char then return nil end
    return env.safe_call(function()
        if char.find_first_child then return char:find_first_child(name) end
        return char:FindFirstChild(name)
    end)
end

function M.iter_parts(char)
    local out = {}
    if not char then return out end

    local desc = env.safe_call(function() return char:get_descendants() end)
        or env.safe_call(function() return char:GetDescendants() end)
    if desc then
        for _, inst in ipairs(desc) do
            if M.is_base_part(inst) then
                out[#out + 1] = inst
            end
        end
    end

    return out
end

function M.set_character_noclip(char, _root, enabled)
    local collide = not enabled
    for _, inst in ipairs(M.iter_parts(char)) do
        M.set_part_collide(inst, collide)
    end
end

function M.set_velocity(inst, x, y, z)
    if not inst then return end
    if part and part.set_velocity then
        pcall(part.set_velocity, inst, x, y, z)
    else
        pcall(function()
            if inst.set_velocity then
                inst:set_velocity(x, y, z)
            else
                inst.Velocity = Vector3.new(x, y, z)
            end
        end)
    end
end

function M.set_angular_velocity(inst, x, y, z)
    if not inst then return end
    x, y, z = x or 0, y or 0, z or 0
    if part and part.set_angular_velocity then
        pcall(part.set_angular_velocity, inst, x, y, z)
    else
        pcall(function()
            if inst.set_angular_velocity then
                inst:set_angular_velocity(x, y, z)
            else
                inst.AngularVelocity = Vector3.new(x, y, z)
            end
        end)
    end
end

function M.set_part_collide(inst, collide)
    if not inst then return end
    if part and part.set_can_collide then
        pcall(part.set_can_collide, inst, collide)
    else
        pcall(function() inst.CanCollide = collide end)
    end
end

function M.humanoid_state(hum, state)
    if not hum or state == nil then return end
    pcall(function()
        if hum.set_state then hum:set_state(state)
        else hum.state = state
        end
    end)
end

function M.camera_flat_axes()
    if not camera or not camera.get_look_vector then return nil end
    local ok, look = pcall(camera.get_look_vector)
    if not ok or not look then return nil end

    local lx = look.x or look.X or 0
    local lz = look.z or look.Z or 0
    local lm = math.sqrt(lx * lx + lz * lz)
    if lm < 0.001 then return nil end
    lx, lz = lx / lm, lz / lm

    return lx, lz, -lz, lx
end

function M.read_flat_input()
    local lx, lz, rx, rz = M.camera_flat_axes()
    if not lx then return 0, 0 end

    local mx, mz = 0, 0
    if M.key_down(0x57) then mx, mz = mx + lx, mz + lz end
    if M.key_down(0x53) then mx, mz = mx - lx, mz - lz end
    if M.key_down(0x41) then mx, mz = mx - rx, mz - rz end
    if M.key_down(0x44) then mx, mz = mx + rx, mz + rz end

    local mag = math.sqrt(mx * mx + mz * mz)
    if mag < 0.001 then return 0, 0 end
    return mx / mag, mz / mag
end

function M.read_fly_input()
    local mx, mz = M.read_flat_input()
    local my = 0
    if M.key_down(0x20) then my = 1 end
    if M.key_down(0x11) then my = -1 end
    return mx, my, mz
end

function M.drive_root_velocity(root, dx, dy, dz, speed, dt, opts)
    if not root then return end
    opts = opts or {}
    dt = dt or M.delta_time()

    local mag = math.sqrt(dx * dx + dy * dy + dz * dz)
    local tx, ty, tz = 0, 0, 0
    if mag >= 0.001 then
        dx, dy, dz = dx / mag, dy / mag, dz / mag
        tx, ty, tz = dx * speed, dy * speed, dz * speed
    end

    if opts.cancel_gravity ~= false and math.abs(ty) < 0.01 then
        ty = 0
    end

    local cx, cy, cz = M.read_velocity(root)
    local blend = opts.blend or 0.35
    blend = math.max(0.05, math.min(1, blend))

    local nx = cx + (tx - cx) * blend
    local ny = cy + (ty - cy) * blend
    local nz = cz + (tz - cz) * blend

    local max_speed = opts.max_speed or (speed * 1.15)
    local sm = math.sqrt(nx * nx + ny * ny + nz * nz)
    if sm > max_speed and sm > 0.001 then
        local s = max_speed / sm
        nx, ny, nz = nx * s, ny * s, nz * s
    end

    M.set_velocity(root, nx, ny, nz)
    M.set_angular_velocity(root, 0, 0, 0)
end

function M.boost_ground_velocity(root, mult, dt)
    if not root or not mult or mult <= 1.001 then return end
    local mx, mz = M.read_flat_input()
    if mx == 0 and mz == 0 then return end

    local cx, cy, cz = M.read_velocity(root)
    local horiz = math.sqrt(cx * cx + cz * cz)
    if horiz < 0.5 then return end

    local boost = (mult - 1) * horiz * math.min(1, (dt or M.delta_time()) * 12)
    M.set_velocity(root, cx + mx * boost, cy, cz + mz * boost)
end

return M

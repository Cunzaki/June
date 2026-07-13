local M = {
    players = {},
    world = {},
    world_lookup = {},
    health_cache = {},
    char_models = {},
    cam_x = 0,
    cam_y = 0,
    cam_z = 0,
    screen_w = 0,
    screen_h = 0,
    ws = nil,
    last_cleanup = 0,
    aim = {current_target = nil, locked_target = nil, silent_target_vm = nil, last_key_state = false, last_main_key_state = false, last_lmb_state = false},
    toggles = {player = {last = false}, world = {last = false}},
    bone_list = {"head", "torso", "arm1", "arm2", "leg1", "leg2", "shoulder1", "shoulder2", "hip1", "hip2"},
    cham_bone_list = {"head", "torso", "arm1", "arm2", "leg1", "leg2"},
    skeleton_bones = {
        {"head", "torso"},
        {"torso", "shoulder1"},
        {"torso", "shoulder2"},
        {"shoulder1", "arm1"},
        {"shoulder2", "arm2"},
        {"torso", "hip1"},
        {"torso", "hip2"},
        {"hip1", "leg1"},
        {"hip2", "leg2"}
    },
    body_part_names = {
        head = true,
        torso = true,
        arm1 = true,
        arm2 = true,
        leg1 = true,
        leg2 = true,
        shoulder1 = true,
        shoulder2 = true,
        hip1 = true,
        hip2 = true,
        Humanoid = true,
        PlayerHighlight = true,
        Model = true,
        Viewmodel = true,
        LocalViewmodel = true,
        TeammateHighlight = true
    },
    player_history = {},
    draw_frame = 0,
    stats = {
        last_world_scan = 0,
    },
    WORKSPACE_SCAN_MS = 1000,
    WORLD_DYNAMIC_MS = 50,
    WORLD_STATIC_MS = 2500,
    POS_CACHE_MS = 100,
    _last_pos_cache = 0,
}

function M.should_refresh_positions()
    local now = utility and utility.get_tick_count and utility.get_tick_count() or 0
    if now - M._last_pos_cache >= M.POS_CACHE_MS then
        M._last_pos_cache = now
        return true
    end
    return false
end

return M

local menu_defs = June.require("menu.menu_defs")
local config = June.require("features.utility.config")
local settings = June.require("core.settings")
local cache = June.require("core.cache")
local env = June.require("core.env")
local scan = June.require("features.combat.scan")
local aimbot = June.require("features.combat.aimbot")
local silent_aim = June.require("features.combat.silent_aim")
local player_esp = June.require("features.visuals.player_esp")
local world_esp = June.require("features.visuals.world_esp")
local aimbot_visuals = June.require("features.visuals.aimbot_visuals")
local crosshair = June.require("features.visuals.crosshair")
local keybind_window = June.require("features.utility.keybind_window")
local fov_changer = June.require("features.utility.fov_changer")
local gun_mods = June.require("features.combat.gun_mods")
local movement_ctrl = June.require("core.movement_ctrl")

local M = {}
local movement_ready = false
M._menu_registered = false

function M.register_all()
    if M._menu_registered then return end
    menu_defs.register_all()
    config.register_menu()
    M._menu_registered = true
end

function M.init()
    M.register_all()
    config.autoload()
    gun_mods.init()
    movement_ctrl.install()
    movement_ready = true
    return true
end

function M.update(_dt)
    local s = settings.s
    cache.ws = env.get_workspace()
    if not cache.ws then
        return
    end
    local cam = cache.ws:FindFirstChild("Camera")
    if cam and cam.CFrame then
        cache.cam_x, cache.cam_y, cache.cam_z = cam.CFrame.X, cam.CFrame.Y, cam.CFrame.Z
    end
    cache.screen_w, cache.screen_h = utility.get_screen_size()
    settings.sync_settings()
    menu.set_visible("world_display_options", s.world_enabled)
    menu.set_visible("world_team_check", s.world_enabled)
    menu.set_visible("box_type", s.players_enabled and s.players_box)
    menu.set_visible("box_fill", s.players_enabled and s.players_box)
    menu.set_visible("box_fill_opacity", s.players_enabled and s.box_fill)
    menu.set_visible("view_line_length", s.players_enabled and s.players_view_line)
    menu.set_visible("view_line_style", s.players_enabled and s.players_view_line)
    menu.set_visible("tracer_origin", s.players_enabled and s.players_tracers)
    menu.set_visible("tracer_style", s.players_enabled and s.players_tracers)
    menu.set_visible("crosshair_style", s.crosshair_enabled)
    menu.set_visible("crosshair_size", s.crosshair_enabled)
    menu.set_visible("crosshair_gap", s.crosshair_enabled)
    menu.set_visible("utilities_max_distance", s.aimbot_enabled and s.utilities_aimbot)
    menu.set_visible("aimbot_fov", s.aimbot_enabled and s.aimbot_fov_visible)
    menu.set_visible("aimbot_fov_style", s.aimbot_enabled and s.aimbot_fov_visible)
    menu.set_visible("target_line_style", s.aimbot_enabled and s.aimbot_target_line)
    menu.set_visible("vis_check_priority", (s.aimbot_enabled and s.aimbot_vischeck) or (s.players_enabled and s.players_visible_override))
    menu.set_visible("silent_prediction_val", s.silent_aim_enabled and s.silent_prediction)
    menu.set_visible("silent_fov_style", s.silent_aim_enabled and s.silent_draw_fov)
    menu.set_visible("silent_fov_fill", s.silent_aim_enabled and s.silent_draw_fov)
    menu.set_visible("silent_gadget_aim", s.silent_aim_enabled)
    menu.set_visible("silent_gadget_team_check", s.silent_aim_enabled and s.silent_gadget_aim)
    menu.set_visible("silent_hitscan_vis", s.silent_aim_enabled and s.silent_hitscan)
    menu.set_visible("fov_changer_value", s.fov_changer_enabled == true)
    menu.set_visible("june_fly_speed", s.june_fly_enabled == true)
    menu.set_visible("june_fly_noclip", s.june_fly_enabled == true)
    menu.set_visible("june_slowfall_speed", s.june_slowfall_enabled == true)
    menu.set_visible("june_speed_boost_mult", s.june_speed_boost_enabled == true)
    menu.set_visible("june_gm_firerate_val", s.june_gunmods_enabled and s.june_gm_firerate)
    menu.set_visible("june_gm_damage_val", s.june_gunmods_enabled and s.june_gm_damage)
    menu.set_visible("june_gm_range_val", s.june_gunmods_enabled and s.june_gm_range)
    menu.set_visible("june_gm_speed_val", s.june_gunmods_enabled and s.june_gm_speed)
    scan.update_char_models()
    scan.scan_players()
    scan.scan_world()
    aimbot.process_toggle("players_enabled", cache.toggles.player, "players_enabled")
    aimbot.process_toggle("world_enabled", cache.toggles.world, "world_enabled")
    silent_aim.update(_dt)
    aimbot.process_aimbot()
    fov_changer.process_fov_changer()
    gun_mods.update(_dt)
    if movement_ready then
        movement_ctrl.tick(_dt)
    end
end

function M.draw()
    player_esp.render_players()
    world_esp.render_world()
    aimbot_visuals.render_aimbot_visuals()
    silent_aim.draw()
    crosshair.draw_crosshair()
    keybind_window.draw_keybind_window()
end

return M

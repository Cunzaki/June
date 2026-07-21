#!/usr/bin/env node
/**
 * Builds june.lua — the single Vector-executable script.
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = path.join(ROOT, "src");
const OUT = path.join(ROOT, "june.lua");

const ORDER = [
  // Core primitives first
  "core/constants.lua",
  "core/env.lua",
  "core/debug.lua",
  "core/cache.lua",
  "core/vk_names.lua",
  "core/menu_util.lua",
  "core/incremental_scan.lua",
  // menu_defs + world_items before settings (settings requires both at load)
  "game/world_items.lua",
  "menu/menu_defs.lua",
  "core/settings.lua",
  // These require settings at load time
  "core/feature_bind.lua",
  "core/aim_key.lua",
  // Game helpers
  "game/gadget_team.lua",
  "game/gadget_lifecycle.lua",
  "game/shootable_gadgets.lua",
  "game/combat_origin.lua",
  // Custom UI
  "ui/gs_theme.lua",
  "ui/gs_input.lua",
  "ui/gs_state.lua",
  "ui/gs_anim.lua",
  "ui/menu_shim.lua",
  "ui/gs_icons.lua",
  "ui/gs_widgets.lua",
  "ui/catalog.lua",
  "ui/custom_menu.lua",
  // Features
  "core/draw_util.lua",
  "game/world_scan.lua",
  "core/silent_ray.lua",
  "core/vis_util.lua",
  "features/combat/hitscan_ray.lua",
  "features/combat/silent_resolve.lua",
  "features/utility/config.lua",
  "features/combat/scan.lua",
  "features/combat/aimbot.lua",
  "features/combat/silent_aim.lua",
  "features/visuals/player_esp.lua",
  "features/visuals/world_esp.lua",
  "features/visuals/aimbot_visuals.lua",
  "features/visuals/crosshair.lua",
  "features/utility/keybind_window.lua",
  "menu/tabs.lua",
  "app.lua",
];

const header = `--[[
    June — Project Vector script
    Built: ${new Date().toISOString()}
    UI: custom June menu (INSERT) — Vector menu tabs disabled
]]

June = {
    version = "1.2.0",
    debug = false,
    _mods = {},
    bundled = true,
    custom_ui = true,
}

June._menu_tab_ready = true

function June.require(path)
    local mod = June._mods[path]
    if mod == nil then
        error("[June] bundled module missing: " .. path)
    end
    return mod
end

`;

const footer = `
do
    June.require("menu.tabs").register_all()
end

June._init_ok = false

local ok, err = pcall(function()
    local debug = June.require("core.debug")
    local app = June.require("app")

    if not app.init() then
        debug.error_once("init", "app.init() returned false")
        return
    end

    June._init_ok = true

    if not debug.register_frame_hook(function()
        app.on_frame()
    end) then
        debug.error_once("init", "Failed to register on_frame")
        return
    end

    print("[June] v" .. (June.version or "?") .. " ready — INSERT for June menu")
end)

if not ok then
    print("[June] Fatal: " .. tostring(err))
    if debug and debug.traceback then print(debug.traceback(err)) end
end
`;

let body = "";
for (const rel of ORDER) {
  const full = path.join(SRC, rel);
  if (!fs.existsSync(full)) {
    console.error("Missing:", rel);
    process.exit(1);
  }
  const modPath = rel.replace(/\.lua$/, "").replace(/\//g, ".");
  const src = fs.readFileSync(full, "utf8");
  body += `\n-- ── ${rel} ──\n`;
  body += `June._mods["${modPath}"] = (function()\n${src}\nend)()\n`;
}

fs.writeFileSync(OUT, header + body + footer);
console.log("Built", path.relative(ROOT, OUT), `(${(fs.statSync(OUT).size / 1024).toFixed(1)} KB)`);

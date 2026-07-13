# Operation One — Agent Reference

PlaceId: **72920620366355** (SEASON 3 Operation One)  
June target game. This document describes how the game is structured and what June hooks into.

---

## High-level architecture

Operation One is a tactical FPS (Rainbow Six Siege–style) built on a custom **StateObject** framework. Almost all gameplay entities are `StateObject` instances with:

- `owner` — network ownership / player controller
- `states` — reactive state machine (`State` module)
- `values` — runtime data (items, viewmodels, camera, etc.)
- `instance` — underlying Roblox model/part

Core modules live under `ReplicatedStorage.Modules` (Util, State, Items, UI, Timer, Maid, etc.).

---

## Workspace layout (what June cares about)

| Path | Purpose |
|------|---------|
| `Workspace.Camera` | Active camera CFrame — June reads position from here |
| `Workspace.Viewmodels` | **Enemy/player visual proxies** — June scans these for ESP & aimbot |
| `Workspace.Viewmodels/Viewmodel` | Per-player viewmodel model (`Viewmodels` attribute = true) |
| `Workspace` children | Character models with `Humanoid` + `HumanoidRootPart` (server bodies) |
| `Workspace.Model/*/DefaultCameras` | Map-placed default cameras |
| `Workspace/<GadgetName>` | Deployed gadgets (Claymore, Drone, C4, etc.) |
| `ReplicatedStorage.Garbage` | Dead/destroyed instances moved here |

### Viewmodel bone names (R6-style, lowercase)

June expects these parts inside each `Viewmodel`:

`head`, `torso`, `arm1`, `arm2`, `leg1`, `leg2`, `shoulder1`, `shoulder2`, `hip1`, `hip2`

Weapon models are sibling `Model` children that are not body parts.

---

## Player representation (dual model system)

Operation One separates **logical characters** from **rendered viewmodels**:

1. **Workspace character model** — has `Humanoid`, `HumanoidRootPart`, used for physics/raycasts/ownership.
2. **Viewmodel** — client-side visual used for ESP rendering; matched to characters by head position proximity.

June flow (`scan.lua`):

1. Enumerate `Workspace.Viewmodels` → each `Viewmodel` child.
2. Read bones + bbox from viewmodel parts.
3. Match to workspace character via `match_character(head_pos)` within `NAME_MATCH_SQ` (20 studs).
4. Resolve health via `core.health` (entity API → humanoid → cache).
5. Link `entity.get_players()` by username for `head_position` / live health.

---

## Health system (critical for combat)

### How the game handles health

- Humanoid `Health` / `MaxHealth` are used in UI (`HealthFrame`, `OpponentHealthFrame`).
- `setup_health()` watches `Humanoid.Health` changes for damage feedback.
- **Enemy health bars are hidden when `ownership < 2`** — health does not reliably replicate to clients for non-owned characters.
- On death: `Humanoid.Health <= 0` → ragdoll → viewmodel parent set to `ReplicatedStorage.Garbage`.
- Dead viewmodels: `torso.Transparency >= 1`, head missing/invalid.

### June health check (`core/health.lua`)

Priority order:

1. **Viewmodel death signals** — Garbage parent, torso fully transparent, missing head.
2. **Vector entity live properties** — `entity.get_players()[name].health`, `is_alive`, `is_dead` (memory read).
3. **Workspace Humanoid** — fallback from `char_models` cache.
4. **health_cache** — tracks lowest seen health per player name between scans.

Settings:

| ID | Default | Effect |
|----|---------|--------|
| `health_check` | on | Global master toggle (Settings tab) |
| `aimbot_health_check` | on | Skip dead players in aimbot |
| `silent_filter_health` | on | Skip dead players in silent aim |

---

## Ownership model

`Util.ownership(instance)` returns network authority level:

| Level | Meaning (approximate) |
|-------|----------------------|
| 0 | Enemy / no authority |
| 2 | Spectator / teammate visibility |
| 3 | Local owner / full authority |

Used throughout game code for:

- Whether to show health bars
- Whether to play sounds/effects
- Whether gadgets are friendly

June gadget team check uses `UserId` + `Team` attributes (`gadget_team.lua`).

---

## Gadgets & world objects

Gadgets spawn as named workspace children (e.g. `Claymore`, `Drone`, `BreachCharge`).

June tracks them via `game/world_items.lua` + `gadget_lifecycle.lua`:

- Anchor part discovery
- Break/destroy state (`is_broken`)
- Team attributes on deploy
- Map cameras under `Workspace.Model/<map>/DefaultCameras/DefaultCamera`

Shootable gadgets for silent/utilities aim: drones, cameras, claymores, C4, breach charges, etc.

---

## ReplicatedStorage structure

```
ReplicatedStorage/
├── Modules/          # Core framework (Util, State, Items, UI, …)
├── Garbage/          # Destroyed instances
├── Objects/          # Runtime object registry
└── …                 # Sounds, animations, UI templates
```

---

## June module map

| June module | Game hook |
|-------------|-----------|
| `features/combat/scan.lua` | Viewmodels + char_models + entity players |
| `core/health.lua` | Health/death detection |
| `game/world_scan.lua` | Workspace gadget scan + model bbox |
| `game/gadget_lifecycle.lua` | Anchor discovery, break/pool state |
| `game/combat_origin.lua` | Muzzle + server body origin (LocalViewmodel) |
| `core/manip_math.lua` | Peek ring manipulation math |
| `features/combat/bullet_tp_ray.lua` | Bullet TP / wallbang origins |
| `features/combat/silent_resolve.lua` | Silent fire origin resolver |
| `features/visuals/manip_visuals.lua` | Manip / TP ray visuals |
| `features/utility/fov_changer.lua` | Permanent `camera.set_fov` override |
| `game/gc_weapon_mods.lua` | `refreshgc` / `getgc` / `applygc` weapon patches |
| `features/combat/gun_mods.lua` | Gun mod menu + apply loop |
| `core/cframe_move.lua` | HRP velocity fly / speed helpers |
| `core/movement_ctrl.lua` | Fly, slowfall, speed boost tick |
| `features/combat/aimbot.lua` | Viewmodel bones → screen aim |
| `features/combat/silent_aim.lua` | Silent ray + gadget resolve |
| `features/visuals/player_esp.lua` | Viewmodel bbox/skeleton ESP |
| `features/visuals/world_esp.lua` | Gadget icons/text/3D boxes |

---

## Vector API reference

Full engine docs: [`docs/API.md`](docs/API.md) (synced from April / Vector GitBook).

Key APIs June uses:
- `entity.get_players()` — live health, positions
- `raycast.track_silent_target` / `enable_silent_hook` — silent aim
- `raycast.is_visible` — manip peek + vis checks
- `camera.get_fov` / `camera.set_fov` — FOV changer
- `refreshgc` / `getgc` / `applygc` — gun mods (see `docs/API.md` GC section)
- `draw.*` / `utility.world_to_screen` — ESP rendering

---

## Silent exploits (Combat tab)

| Setting | Effect |
|---------|--------|
| **Bullet TP (Wallbang)** | Spawns bullet ray origin on/around target (Center, Ring, Sphere, etc.) |
| **Bullet Manipulation** | Ring-scans body position for visible peek through walls |
| **Manip Extend** | Expands peek search radius up to +7 studs |
| **Bullet TP Ray Visual** | Draws muzzle → TP → target path |
| **Manip Peek Visual** | Draws peek point + aim line |

Muzzle origin: `LocalViewmodel` weapon `Muzzle`/`Barrel`/`FlashPart` parts.  
Manip body origin: local player `HumanoidRootPart` / entity position.

---

## Other exploits

| Feature | Notes |
|---------|-------|
| **FOV Changer** | Settings → forces `camera.set_fov` every frame (game tries to reset via `OriginalFOV` attribute — changer wins while enabled) |
| **Silent hook** | Redirects bullet ray origin via Vector `raycast.track_silent_target` |
| **Gun Mods** | Gun Mods tab → `refreshgc()` → `getgc(keys)` warm → `applygc(keys, values)`. Standard Mult keys (`RecoilMult`, `FireRateMult`, etc.) plus Op One probes (`firerate`, `recoil_up`, `speed_multiplier`). Equip a gun in-match before enabling. |
| **Fly** | Movement tab → HRP velocity only (WASD + Space/Ctrl). Optional noclip. Spoofs `Humanoid` Running state so `values.falling` does not block shooting. |
| **Slowfall** | Caps downward velocity + same shoot bypass |
| **Speed Boost** | Adds horizontal velocity on top of normal movement (no `WalkSpeed` write) |

### Anticheat notes (from dump)

- `Time_37624.lua` → `game.ServerStorage.Modules.AntiCheat.validate_position` (server-side position checks).
- `Audio_29057.lua` lerps `Humanoid.WalkSpeed` from `states.speed` / `speed_multiplier` — **do not write WalkSpeed** from external scripts; use velocity/CFrame instead.
- Shooting blocked when `values.falling:get()` is true — movement ctrl spoofs Running state while flying/slowfalling.

From dump: game uses `Util.can_ray_reach` server-side — client-side silent/manip depends on Vector hook, not game Lua.

---

## Bundle load order (critical)

June bundles all `src/` modules into one `june.lua`. Each file runs as an **IIFE at load time** — any `June.require()` at the **top** of a file must already be registered.

**Error:** `[June] bundled module missing: features.visuals.manip_visuals`  
**Cause:** `silent_aim.lua` requires `manip_visuals` but `manip_visuals` was bundled after it.

**Rule:** In `scripts/bundle.mjs` `ORDER` array, list every dependency **before** dependents.

Current combat/visual chain:

```
manip_math → combat_origin → bullet_tp_ray → silent_resolve → manip_visuals → silent_aim
```

Gun mods / movement chain:

```
gc_weapon_mods → gun_mods
cframe_move → movement_ctrl
```

`menu/tabs.lua` and `app.lua` must stay **last** (they require almost everything).

After adding a new module, grep its top-level `June.require` calls and insert it after all of those paths. Then `npm run build`.

---

## Dump layout (local)

Generated by `python scripts/dump-rbxlx.py`:

```
dump/
├── INDEX.md
├── structure.json      # counts + signatures
├── signatures.json     # keyword hits in place file
├── services.json       # early service names
├── scripts_index.json  # all extracted scripts
└── scripts/*.lua       # 350 decompiled ModuleScripts/LocalScripts
```

Re-run dump after place updates:

```bash
python scripts/dump-rbxlx.py "path/to/place.rbxlx"
```

---

## Known quirks for external scripts

1. **Do not trust raw `Humanoid.Health` for enemies** — use entity live reads + viewmodel death signals.
2. **Viewmodels are the ESP source of truth for positions** — character HRP may desync.
3. **Dead players briefly linger** — check Garbage parent + torso transparency.
4. **Join a live match** before enabling combat — menu loads in lobby but scan needs Viewmodels populated.
5. **fishy bypass.txt** — referenced for anticheat bypass; file was empty at time of setup. Fallen bypass pattern lives in Volt `newvape/libraries/fallen_bypass.lua` (different game).

---

## Build & load

```bash
npm run build          # src/ → june.lua
```

```lua
utility.load_url("https://raw.githubusercontent.com/Cunzaki/June/refs/heads/main/june.lua")
```

Menu: **Scripts → June**

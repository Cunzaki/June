# June

**June** is a [Project Vector](https://project-vector-1.gitbook.io/vector-lua-engine/) script for Roblox place `72920620366355`.

Player ESP, world gadget ESP, aimbot, silent aim, configs, and more — all from one loadstring.

---

## Quick load

Paste this in Vector and execute:

```lua
utility.load_url("https://raw.githubusercontent.com/Cunzaki/June/refs/heads/main/june.lua")
```

Or run [`load.lua`](load.lua) from this repo.

Open the menu: press **INSERT** (Neverlose-style custom UI).

---

## Features

| Category | What's included |
|----------|-----------------|
| **Combat** | Aimbot (players + gadgets), silent aim, gadget targeting (drones, cameras, claymores, etc.), FOV circles, prediction |
| **Players** | Box ESP, skeleton, tracers, health, names, team check, visibility filter |
| **World** | Gadget ESP with icons, distance, team colors, break-state filtering |
| **Settings** | Config save/load, keybind overlay, crosshair |

No gun mods or movement features.

---

## Local install

**Option A — loadstring (recommended):** use the snippet above.

**Option B — run from disk:**

```bash
npm run build
```

Then load `june.lua` in Vector → **Execute Script**.

---

## Development

```bash
npm run build    # bundle src/ → june.lua
npm run assets   # refresh gadget PNGs for CDN
```

Edit files under `src/`, rebuild, and push `june.lua` to GitHub so the loadstring stays up to date.

### Repo layout

| Path | Purpose |
|------|---------|
| [`load.lua`](load.lua) | One-line loadstring |
| [`june.lua`](june.lua) | Bundled runtime script (what users load) |
| [`src/`](src/) | Modular source |
| [`scripts/`](scripts/) | Bundle + asset tools |
| [`assets/`](assets/) | Gadget icons served via GitHub CDN |

**Local only (gitignored):** `dump/`, `node_modules/`

### Asset CDN

Gadget icons load from:

```
https://raw.githubusercontent.com/Cunzaki/June/refs/heads/main/assets/gadgets/{id}.png
```

Regenerate with `npm run assets` before pushing new icons.

---

## Requirements

- [Project Vector](https://project-vector-1.gitbook.io/vector-lua-engine/) external
- Join a match before enabling combat features

---

## Debug

Set `June.debug = true` before or after load to print internal logs.

---

## Disclaimer

For educational use. Not affiliated with Project Vector. Use at your own risk.

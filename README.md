# April Operation One

Project Vector script for **Operation One** (place `72920620366355`).

## Load in Vector

**Option A — loadstring (recommended):**

```lua
utility.load_url("https://raw.githubusercontent.com/Cunzaki/April-Operation-One/refs/heads/main/operation_one.lua")
```

Or run `load.lua` from this repo.

**Option B — local file:**

1. Build: `npm run build`
2. Load `operation_one.lua` in Vector → **Execute Script**.

Menu: **Scripts → Operation One**

---

## Rebuild from source

```bash
npm run build
```

Edit `src/`, rebuild, push `operation_one.lua` to GitHub.

---

## Assets (GitHub CDN)

```bash
npm run assets
```

PNG icons go to `assets/gadgets/`. Runtime loads via:

`https://raw.githubusercontent.com/Cunzaki/April-Operation-One/refs/heads/main/assets/gadgets/{id}.png`

---

## What's on GitHub (minimal)

| Path | Purpose |
|------|---------|
| `load.lua` | One-line loadstring |
| `operation_one.lua` | Bundled runtime script |
| `src/` | Modular source |
| `scripts/` | Bundle + asset tools |
| `assets/` | CDN gadget icons |
| `package.json` | `npm run build` |

**Local only (gitignored):** `dump/`, `references/`, `Script 1.lua`, `node_modules/`

---

## License

Use at your own risk. Not affiliated with Project Vector or Operation One.

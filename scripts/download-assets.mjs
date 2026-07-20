#!/usr/bin/env node
/**
 * Download gadget/operator PNGs via Roblox Thumbnails API → assets/gadgets/{id}.png
 * Commit assets/ to GitHub — runtime loads via raw.githubusercontent.com
 *
 * Run: npm run extract-images && npm run download-assets
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST = path.join(ROOT, "assets/manifest.json");
const OUT_DIR = path.join(ROOT, "assets/gadgets");

const THUMB_API = "https://thumbnails.roblox.com/v1/assets";
const BATCH = 50;
const DELAY_MS = 300;

const args = process.argv.slice(2);
const missingOnly = args.includes("--missing-only");

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function downloadUrl(url, dest) {
  const res = await fetch(url, {
    headers: { "User-Agent": "June-Asset-Sync/1.0" },
    redirect: "follow",
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 100) throw new Error(`too small (${buf.length}b)`);
  fs.writeFileSync(dest, buf);
  return buf.length;
}

async function resolveThumbnails(ids) {
  const q = new URLSearchParams({
    assetIds: ids.join(","),
    returnPolicy: "PlaceHolder",
    size: "420x420",
    format: "Png",
  });
  const res = await fetch(`${THUMB_API}?${q}`, {
    headers: { "User-Agent": "June-Asset-Sync/1.0" },
  });
  if (!res.ok) throw new Error(`Thumbnails API HTTP ${res.status}`);
  const json = await res.json();
  const out = new Map();
  const rows = json.data || [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const id = ids[i];
    if (id && row.imageUrl && row.state === "Completed") {
      out.set(String(id), row.imageUrl);
    }
  }
  return out;
}

async function main() {
  if (!fs.existsSync(MANIFEST)) {
    console.error("Run: node scripts/extract-gadget-images.mjs first");
    process.exit(1);
  }
  const manifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  let ids = manifest.assetIds || [];
  fs.mkdirSync(OUT_DIR, { recursive: true });

  if (missingOnly) {
    ids = ids.filter((id) => !fs.existsSync(path.join(OUT_DIR, `${id}.png`)));
  }

  console.log(`Downloading ${ids.length} assets → assets/gadgets/`);
  let ok = 0;
  let fail = 0;

  for (let i = 0; i < ids.length; i += BATCH) {
    const batch = ids.slice(i, i + BATCH);
    const thumbs = await resolveThumbnails(batch);
    for (const id of batch) {
      const dest = path.join(OUT_DIR, `${id}.png`);
      const url = thumbs.get(String(id));
      if (!url) {
        console.warn(`  skip ${id} — no thumbnail`);
        fail++;
        continue;
      }
      try {
        const size = await downloadUrl(url, dest);
        console.log(`  ✓ ${id}.png (${(size / 1024).toFixed(1)} KB)`);
        ok++;
      } catch (e) {
        console.warn(`  ✗ ${id}: ${e.message}`);
        fail++;
      }
    }
    if (i + BATCH < ids.length) await sleep(DELAY_MS);
  }

  console.log(`Done: ${ok} ok, ${fail} failed`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

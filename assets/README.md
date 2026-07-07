# Assets

Gadget and operator icons for April Operation One.

## Generate

```bash
npm run assets
# or: npm run extract-images && npm run download-assets
```

PNG files land in `assets/gadgets/{assetId}.png`.

Asset IDs come from `dump/properties/ImageLabel.jsonl`.

## GitHub CDN

After pushing to GitHub, runtime loads via one HTTPS URL per image:

`https://raw.githubusercontent.com/Cunzaki/April-Operation-One/refs/heads/main/assets/gadgets/{assetId}.png`

See `src/game/asset_urls.lua` and `docs/API.md`.

# immersive-cdn

Media for the Immersive iOS app's temporary local catalog (Trending / Challenge / Workout tabs), served through jsDelivr.

```
videos/<documentId>.mp4        H.264 (High) + AAC, yuv420p, faststart, ≤ 20 MB
thumbnails/<documentId>.jpg
data/videos_api_snapshot.json  GET /api/videos at build time
scripts/build.sh               snapshot → download → transcode → app JSON
```

This repo is the **source**: snapshot, scripts and every file. It is ~660 MB, and
jsDelivr rejects GitHub repos over 50 MB — intermittently, as a 403 "Package size
exceeded". So the app never points here. Each record is packed into a shard repo
`immersive-cdn-NN` (≤ 45 MB, see `data/shards.json`) and served from there:

```
https://cdn.jsdelivr.net/gh/<owner>/immersive-cdn-NN@v1.0.0/videos/<documentId>.mp4
https://cdn.jsdelivr.net/gh/<owner>/immersive-cdn-NN@v1.0.0/thumbnails/<documentId>.jpg
```

Pin a tag, never `@main`.

## Sources

- 21 records that have media on the Strapi API: re-encoded from HEVC / AV1 to H.264 (AV1 does not play on most iPhones).
- 80 records with no media on the API: taken from `nhat120904/immersive-cdn`, matched by `video_title`, remuxed with `+faststart`.

## Rebuild

```bash
API_TOKEN=… CDN_OWNER=<owner> CDN_TAG=vX.Y.Z ./scripts/build.sh
CDN_OWNER=<owner> CDN_TAG=vX.Y.Z ./scripts/publish-shards.sh
```

`shards.json` keeps existing assignments, so a rebuild only adds new records. Copy
`out/catalog_videos.json` and `out/catalog_tabs.json` to `Immersive/Resources/` in the app.

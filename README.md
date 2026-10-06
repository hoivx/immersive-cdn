# immersive-cdn

Media for the Immersive iOS app's temporary local catalog (Trending / Challenge / Workout tabs), served through jsDelivr.

```
videos/<documentId>.mp4        H.264 (High) + AAC, yuv420p, faststart, ≤ 20 MB
thumbnails/<documentId>.jpg
data/videos_api_snapshot.json  GET /api/videos at build time
scripts/build.sh               snapshot → download → transcode → app JSON
```

URL pattern (pin a tag, never `@main`):

```
https://cdn.jsdelivr.net/gh/<owner>/immersive-cdn@v1.0.0/videos/<documentId>.mp4
https://cdn.jsdelivr.net/gh/<owner>/immersive-cdn@v1.0.0/thumbnails/<documentId>.jpg
```

## Sources

- 21 records that have media on the Strapi API: re-encoded from HEVC / AV1 to H.264 (AV1 does not play on most iPhones).
- 80 records with no media on the API: taken from `nhat120904/immersive-cdn`, matched by `video_title`, remuxed with `+faststart`.

## Rebuild

```bash
API_TOKEN=… CDN_BASE=https://cdn.jsdelivr.net/gh/<owner>/immersive-cdn@vX.Y.Z ./scripts/build.sh
```

Copy `out/catalog_videos.json` and `out/catalog_tabs.json` to `Immersive/Resources/` in the app, then push and tag a new version here.

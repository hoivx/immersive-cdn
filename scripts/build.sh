#!/usr/bin/env bash
# Rebuilds the Immersive local catalog from the Strapi API.
#
#   API_TOKEN=… CDN_OWNER=<github user> CDN_TAG=v1.0.0 ./scripts/build.sh
#
# 1. Snapshots GET /api/videos (all pages) into data/videos_api_snapshot.json.
# 2. For every record:
#      - has media on the API  → download, re-encode to H.264/AAC (the API serves HEVC and AV1);
#      - no media on the API   → take the mp4/jpg from nhat120904/immersive-cdn, matched by title.
#    Every output is checked: h264 + yuv420p, moov before mdat, ≤ 20 MB (jsDelivr per-file cap).
# 3. Packs records into ≤ 45 MB shards (scripts/shard.py → data/shards.json): jsDelivr
#    rejects GitHub repos over 50 MB, so each shard is its own repo immersive-cdn-NN.
# 4. Writes out/catalog_videos.json and out/catalog_tabs.json for the app bundle.
#
# The token is only read from the environment; it is never written to disk.
set -euo pipefail

: "${API_TOKEN:?API_TOKEN is required}"
: "${CDN_OWNER:?CDN_OWNER (GitHub user owning immersive-cdn-NN) is required}"
CDN_TAG="${CDN_TAG:-v1.0.0}"
API_HOST="${API_HOST:-https://immersive.var-meta.com}"
REF_JSON="${REF_JSON:-https://raw.githubusercontent.com/nhat120904/immersive-cdn/main/data.json}"
MAX_BYTES=$((20 * 1024 * 1024))

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p data videos thumbnails out .work

# ---------------------------------------------------------------- 1. snapshot
echo "▸ snapshot /api/videos"
page=1; : > .work/pages.jsonl
while :; do
  curl --retry 5 --retry-all-errors --retry-delay 2 -fsS -g -H "Authorization: Bearer $API_TOKEN" \
    "$API_HOST/api/videos?pagination[page]=$page&pagination[pageSize]=100" > .work/page.json
  cat .work/page.json >> .work/pages.jsonl; echo >> .work/pages.jsonl
  count=$(jq '.meta.pagination.pageCount' .work/page.json)
  [ "$page" -ge "$count" ] && break
  page=$((page + 1))
done
jq -s '[.[].data[]]' .work/pages.jsonl > data/videos_api_snapshot.json
curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL "$REF_JSON" > .work/ref.json
echo "  $(jq length data/videos_api_snapshot.json) records"

# ---------------------------------------------------------------- 2. media
is_ok_h264() { # file → 0 when h264 + yuv420p
  local v; v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,pix_fmt -of csv=p=0 "$1")
  [ "$v" = "h264,yuv420p" ]
}
encode() { # in out
  ffmpeg -nostdin -loglevel error -y -i "$1" -map 0:v:0 -map 0:a:0? \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 23 -preset slow \
    -c:a aac -b:a 128k -movflags +faststart "$2"
}
remux() { # in out — already H.264, only move moov to the front
  ffmpeg -nostdin -loglevel error -y -i "$1" -map 0 -c copy -movflags +faststart "$2"
}

jq -c '.[]' data/videos_api_snapshot.json | while read -r rec; do
  id=$(jq -r .documentId <<<"$rec")
  title=$(jq -r .video_title <<<"$rec")
  out_v="videos/$id.mp4"; out_t="thumbnails/$id.jpg"
  if [ -s "$out_v" ] && [ -s "$out_t" ]; then continue; fi

  api_video=$(jq -r '.video_name.url // empty' <<<"$rec")
  if [ -n "$api_video" ]; then
    src_v="$API_HOST$api_video"
    src_t="$API_HOST$(jq -r '.thumb_name.url' <<<"$rec")"
  else
    ref=$(jq -c --arg t "$title" '.data[] | select(.video_title == $t)' .work/ref.json)
    [ -n "$ref" ] || { echo "✗ no media anywhere for $id ($title)"; exit 1; }
    src_v=$(jq -r .video_name <<<"$ref")
    src_t=$(jq -r .thumb_name <<<"$ref")
  fi

  echo "▸ $id  $title"
  curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL "$src_v" -o .work/in.mp4
  curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL "$src_t" -o "$out_t"
  if is_ok_h264 .work/in.mp4; then remux .work/in.mp4 "$out_v"; else encode .work/in.mp4 "$out_v"; fi
done

echo "▸ verify"
fail=0
for f in videos/*.mp4; do
  is_ok_h264 "$f" || { echo "✗ codec $f"; fail=1; }
  size=$(stat -f%z "$f"); [ "$size" -le "$MAX_BYTES" ] || { echo "✗ size $f $size"; fail=1; }
  # faststart: the moov atom must appear before mdat
  python3 -c 'import os,struct,sys
f=sys.argv[1]; s=os.path.getsize(f); p=0; o=[]
with open(f,"rb") as h:
    while p<s:
        h.seek(p); n,t=struct.unpack(">I4s",h.read(8))
        if n==1: n=struct.unpack(">Q",h.read(8))[0]
        o.append(t); p+=n or s
sys.exit(o.index(b"moov")>o.index(b"mdat"))' "$f" || { echo "✗ moov not at front $f"; fail=1; }
done
for f in thumbnails/*.jpg; do
  [ "$(stat -f%z "$f")" -le "$MAX_BYTES" ] || { echo "✗ size $f"; fail=1; }
done
[ "$fail" = 0 ] || exit 1

# ---------------------------------------------------------------- 3. shards
echo "▸ shards"
python3 scripts/shard.py

# ---------------------------------------------------------------- 4. app JSON
echo "▸ catalog_videos.json"
jq --arg owner "$CDN_OWNER" --arg tag "$CDN_TAG" --slurpfile shards data/shards.json '
  def cdn: "https://cdn.jsdelivr.net/gh/\($owner)/immersive-cdn-\($shards[0][.documentId])@\($tag)";
  {
    data: [ .[] | cdn as $cdn | {
      documentId, video_title, topic_name, video_type, video_format,
      download, calories, mode, difficulty_level,
      thumb_name: {
        url: "\($cdn)/thumbnails/\(.documentId).jpg",
        mime: "image/jpeg",
        width: (.thumb_name.width // null),
        height: (.thumb_name.height // null)
      },
      video_name: { url: "\($cdn)/videos/\(.documentId).mp4", mime: "video/mp4" }
    } ],
    meta: { pagination: { page: 1, pageSize: length, pageCount: 1, total: length } }
  }' data/videos_api_snapshot.json > out/catalog_videos.json

echo "▸ catalog_tabs.json"
# Chip ids are exactly what CatalogViewModel sends; see the app's LocalContentRepository.
jq '
  def ids(f): [ .[] | select(f) | .documentId ];
  {
    trending: {
      "Trending":  ids(.topic_name == "challenge" or .topic_name == "Trending"),
      "Finger In": ids(.topic_name == "fingerin"),
      "Exercies":  ids(.topic_name == "exercises")
    },
    challenge: {
      single: ids(.mode == "single"),
      duo:    ids(.mode == "duo"),
      squad:  ids(.mode == "squad")
    },
    workout: {
      "":           ids(.topic_name == "warmup" or .topic_name == "exercises"),
      "Strength":   [], "Cardio": [], "Yoga": [], "HIIT": [],
      "Stretching": [], "Dance":  [], "Full Body": []
    }
  }' data/videos_api_snapshot.json > out/catalog_tabs.json

jq -c '{trending: (.trending|map_values(length)), challenge: (.challenge|map_values(length)), workout: (.workout|map_values(length))}' out/catalog_tabs.json
echo "✓ done"

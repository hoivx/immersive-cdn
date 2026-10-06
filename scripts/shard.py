#!/usr/bin/env python3
"""Packs each record (video + thumbnail) into shards of <= LIMIT bytes.

jsDelivr refuses GitHub repos over 50 MB - not always, intermittently, which is
worse. Each shard becomes its own repo `immersive-cdn-NN`, so every repo jsDelivr
sees stays under the limit. Writes data/shards.json: {documentId: "NN"}.
An existing assignment is kept, so a rebuild never moves a published file.
"""
import json, os, sys
LIMIT = 45 * 1024 * 1024
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
ids = [r["documentId"] for r in json.load(open("data/videos_api_snapshot.json"))]
size = {i: os.path.getsize(f"videos/{i}.mp4") + os.path.getsize(f"thumbnails/{i}.jpg") for i in ids}
path = "data/shards.json"
shards = json.load(open(path)) if os.path.exists(path) else {}
used = {}
for i, s in shards.items():
    used[s] = used.get(s, 0) + size.get(i, 0)
# first-fit decreasing for records that have no shard yet
for i in sorted((i for i in ids if i not in shards), key=lambda i: -size[i]):
    for s in sorted(used):
        if used[s] + size[i] <= LIMIT:
            break
    else:
        s = f"{len(used) + 1:02d}"
        used[s] = 0
    shards[i] = s
    used[s] += size[i]
json.dump(dict(sorted(shards.items())), open(path, "w"), indent=1)
for s in sorted(used):
    print(s, round(used[s] / 1048576, 1), "MB", sum(1 for v in shards.values() if v == s), "records")

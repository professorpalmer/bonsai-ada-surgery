from __future__ import annotations

import json
import sys
import urllib.request

for repo in sys.argv[1:]:
    url = f"https://huggingface.co/api/models/{repo}/tree/main"
    with urllib.request.urlopen(url, timeout=30) as r:
        items = json.load(r)
    print(f"== {repo}")
    for x in items:
        print(f"{x.get('size', 0) / 1e9:8.3f} GB  {x['path']}")

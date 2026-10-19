"""Live check of the cut-retry fix through the layer: content length per request, stream off and on.
python cut_live.py BASE KEYFILE OUT.jsonl TAG"""
import json, random, sys, urllib.request

BASE, KEY, OUT, TAG = sys.argv[1], open(sys.argv[2]).read().strip(), sys.argv[3], sys.argv[4]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}


def doc(i, d):
    rng = random.Random(100 + i)
    return " ".join("Item %d: the %s in room %d holds %d parts." % (j, rng.choice(["box", "crate", "bin", "rack"]), rng.randint(1, 60),
                    rng.randint(10, 999)) for j in range(max(1, int(d / 20.6)))) + "\n\nWrite a short report (about 200 words) on what this inventory suggests."


cases = [("short40", "Write a short report (about 200 words) on why warehouses keep spare parts.", 40),
         ("doc4k250", doc(0, 4000), 250), ("doc64k250", doc(2, 64000), 250)]
for name, text, mt in cases:
    for stream in (False, True):
        body = {"messages": [{"role": "user", "content": text}], "max_tokens": mt, "temperature": 0, "stream": stream,
                "chat_template_kwargs": {"enable_thinking": False}}
        raw = urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(), headers=H),
                                     timeout=3600).read().decode("utf-8", "replace")
        if stream:
            content, fin = "", None
            for l in raw.splitlines():
                if l.startswith("data: {"):
                    e = json.loads(l[6:])
                    for ch in e.get("choices") or []:
                        content += (ch.get("delta") or {}).get("content") or ""
                        fin = ch.get("finish_reason") or fin
            rec = {"tag": TAG, "case": name, "stream": True, "finish": fin, "content_len": len(content), "head": content[:60]}
        else:
            r = json.loads(raw)
            m = r["choices"][0]["message"]
            rec = {"tag": TAG, "case": name, "stream": False, "finish": r["choices"][0]["finish_reason"],
                   "content_len": len(m.get("content") or ""), "cut_retry": (r.get("layer") or {}).get("cut_retry"),
                   "completion_tokens": (r.get("usage") or {}).get("completion_tokens"), "head": (m.get("content") or "")[:60]}
        open(OUT, "a", encoding="utf-8").write(json.dumps(rec) + "\n")
        print(json.dumps(rec), flush=True)

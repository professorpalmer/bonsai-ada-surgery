"""Send a captured request again and print only numbers: prompt tokens, time to first token, decode tok/s, draft
acceptance, and a hash of the output. No prompt or answer text is printed or saved, so the output is safe to paste
into an issue. Use it to compare two server settings on the same request: start the server with the first setting,
run this, restart the server with the second setting, run this again.

    python bench/capture_replay.py logs/pi_requests.jsonl --base http://127.0.0.1:10022 --key-file artifacts/api_key.txt --tag lookup-on
    python bench/capture_replay.py logs/pi_requests.jsonl --base http://127.0.0.1:10022 --key-file artifacts/api_key.txt --tag lookup-off

--index picks the captured chat request (default -1: the last one). --greedy sets temperature 0, so both runs write
the same text and the speed difference comes only from the server setting (the output hashes then match). Without
--greedy the client's own sampling settings are used. --max-tokens caps the answer length (default 2000), so both
runs decode about the same number of tokens. With thinking on, the serve raises a smaller cap to the thinking budget
plus 4096 tokens, so a greedy answer that repeats itself can run that long.
"""
import argparse, hashlib, json, time, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("capture")
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", default="artifacts/api_key.txt")
ap.add_argument("--index", type=int, default=-1)
ap.add_argument("--greedy", action="store_true")
ap.add_argument("--max-tokens", type=int, default=2000)
ap.add_argument("--tag", default="")
ap.add_argument("--out", default="")
a = ap.parse_args()

reqs = []
for line in open(a.capture, encoding="utf-8"):
    rec = json.loads(line)
    body = rec.get("body")
    if isinstance(body, dict) and "messages" in body and rec.get("path", "").rstrip("/").endswith("/chat/completions"):
        reqs.append(body)
if not reqs:
    raise SystemExit("no chat request in " + a.capture)
body = dict(reqs[a.index])
body.pop("store", None)
body["stream"] = True
body["stream_options"] = {"include_usage": True}
for k in ("max_tokens", "max_completion_tokens"):
    body.pop(k, None)
body["max_tokens"] = a.max_tokens
if a.greedy:
    for k in ("top_p", "top_k", "min_p", "seed"):
        body.pop(k, None)
    body["temperature"] = 0

key = open(a.key_file, encoding="utf-8").read().strip()
req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), method="POST",
                             headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
h = hashlib.sha256()
t0 = time.time(); t_first = None; timings = None; usage = None; finish = None
with urllib.request.urlopen(req, timeout=7200) as r:
    for raw in r:
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        ev = json.loads(data)
        timings = ev.get("timings") or timings
        usage = ev.get("usage") or usage
        for ch in ev.get("choices") or []:
            d = ch.get("delta") or {}
            piece = (d.get("reasoning_content") or "") + (d.get("content") or "")
            for c in d.get("tool_calls") or []:
                f = c.get("function") or {}
                piece += (f.get("name") or "") + (f.get("arguments") or "")
            if piece:
                if t_first is None:
                    t_first = time.time()
                h.update(piece.encode("utf-8"))
            finish = ch.get("finish_reason") or finish
t1 = time.time()

out = {"tag": a.tag, "index": a.index, "messages": len(body.get("messages") or []), "tools": len(body.get("tools") or []),
       "greedy": a.greedy, "finish": finish, "output_sha": h.hexdigest()[:12]}
if timings:
    out.update(prompt_n=timings.get("prompt_n"), prompt_tps=round(timings.get("prompt_per_second") or 0, 1),
               gen_n=timings.get("predicted_n"), decode_tps=round(timings.get("predicted_per_second") or 0, 2))
    if timings.get("draft_n"):
        out.update(draft_n=timings["draft_n"], draft_accepted=timings.get("draft_n_accepted"),
                   acceptance=round(timings.get("draft_n_accepted", 0) / timings["draft_n"], 3))
else:
    gen = (usage or {}).get("completion_tokens")
    out.update(prompt_n=(usage or {}).get("prompt_tokens"), gen_n=gen,
               decode_tps=round(gen / (t1 - t_first), 2) if gen and t_first and t1 > t_first else None,
               note="no timings in the stream: decode tok/s from wall time")
out["ttft_s"] = round(t_first - t0, 1) if t_first else None
print(json.dumps(out))
if a.out:
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(out) + "\n")

"""P168: one cold read of about --depth tokens (a unique first line, so the server cannot reuse its prompt cache) + a short
answer; prints the server's prefill tok/s. --short: a tiny request instead."""
import argparse, json, sys, time, urllib.request
sys.path.insert(0, r"C:\bonsai\bonsai-ada-surgery\bench")
import quick_tps as q  # noqa: E402
ap = argparse.ArgumentParser()
ap.add_argument("--key-file", required=True)
ap.add_argument("--depth", type=int, default=0)
ap.add_argument("--salt", default="0")
ap.add_argument("--short", action="store_true")
a = ap.parse_args()
key = open(a.key_file).read().strip()
base = "http://127.0.0.1:8080"
text = "Say hi." if a.short else f"Session {a.salt} at {time.time():.0f}. " + q.filler(base, key, a.depth) + "Summarize the notes in one line."
body = {"model": "b", "messages": [{"role": "user", "content": text}], "max_tokens": 32 if a.short else 64, "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False}}
req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(), headers=q._headers(key))
t0 = time.time()
r = json.loads(urllib.request.urlopen(req, timeout=7200).read())
t = r.get("timings", {})
print(f"{time.strftime('%H:%M:%S')} {'short' if a.short else 'read'} depth {a.depth} salt {a.salt}: prompt_n {t.get('prompt_n')} "
      f"prefill {t.get('prompt_per_second', 0):.1f} tok/s  decode {t.get('predicted_per_second', 0):.1f} tok/s  wall {time.time() - t0:.1f} s",
      flush=True)

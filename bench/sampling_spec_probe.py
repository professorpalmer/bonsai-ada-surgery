"""Issue #4 probe, part 2: client sampling parameters vs MTP drafting at agent-sized context.

Pads the prompt to --depth tokens (varied filler, as quick_tps does), sends an agent-style tools request under
several sampling parameter sets that harnesses commonly send, and reads the server's own decode timing:
  default    temperature 0.7, top_p 0.95 (as the harness would)
  penalties  + repeat_penalty 1.1, repeat_last_n 64, min_p 0.05
  wholectx   + repeat_last_n -1 (penalty window = the whole context)
  presence   + presence_penalty 1.5, frequency_penalty 0.5
Run with the product (MTP on) and again with BONSAI_SPEC=0; the ratio per row is the answer.

    python bench/sampling_spec_probe.py --base http://127.0.0.1:18080 --key-file artifacts/api_key.txt --depth 50000 --log logs/issue_serve.err
"""
import argparse, json, re, sys, os, time, urllib.request, urllib.error
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quick_tps import filler  # noqa: E402
from grammar_spec_probe import TOOLS  # noqa: E402

VARIANTS = {
    "default":   {"temperature": 0.7, "top_p": 0.95},
    "penalties": {"temperature": 0.7, "top_p": 0.95, "min_p": 0.05, "repeat_penalty": 1.1, "repeat_last_n": 64},
    "wholectx":  {"temperature": 0.7, "top_p": 0.95, "min_p": 0.05, "repeat_penalty": 1.1, "repeat_last_n": -1},
    "presence":  {"temperature": 0.7, "top_p": 0.95, "presence_penalty": 1.5, "frequency_penalty": 0.5},
}
PROMPT = "Summarize the document above in about 300 words of prose, then list the five most important points. No tool calls."

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--base", default="http://127.0.0.1:18080"); ap.add_argument("--key-file", default="artifacts/api_key.txt")
    ap.add_argument("--depth", type=int, default=50000); ap.add_argument("--n", type=int, default=400); ap.add_argument("--log", default="")
    a = ap.parse_args(); key = open(a.key_file, encoding="utf-8").read().strip()
    H = {"Authorization": "Bearer " + key, "Content-Type": "application/json"}
    pad = filler(a.base, key, a.depth)
    msgs = [{"role": "system", "content": "You are a careful assistant."}, {"role": "user", "content": pad + "\n\n" + PROMPT}]
    mark = len(open(a.log, encoding="utf-8", errors="replace").read()) if a.log else 0
    for name, samp in VARIANTS.items():
        body = {"model": "bonsai-2-27b", "messages": msgs, "max_tokens": a.n, "tools": TOOLS, "tool_choice": "auto",
                "chat_template_kwargs": {"enable_thinking": False}, **samp}
        t = time.time()
        try:
            r = json.loads(urllib.request.urlopen(urllib.request.Request(a.base + "/v1/chat/completions", json.dumps(body).encode(), H), timeout=3600).read())
        except urllib.error.HTTPError as e:
            print(f"{name:10} HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:300]}", flush=True); continue
        tm = r.get("timings", {})
        acc = ""
        if a.log:
            tail = open(a.log, encoding="utf-8", errors="replace").read()[mark:]; mark += len(tail)
            m = re.findall(r"draft acceptance = ([0-9.]+)", tail); acc = f"acceptance {m[-1]}" if m else ""
        print(f"{name:10} decode {tm.get('predicted_per_second', 0):6.1f} tok/s  n={tm.get('predicted_n')}  prompt {tm.get('prompt_n')} tok  {acc}  wall {time.time()-t:.0f}s", flush=True)

if __name__ == "__main__":
    main()

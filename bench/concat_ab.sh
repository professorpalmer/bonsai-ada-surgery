#!/usr/bin/env bash
# Patch 0050: the transpose concat path for the gated-delta-net conv state on every NVIDIA card (was GB10 only) vs
# the product engine. Product launcher (12 GB recipe), drafting on, layer off. Arms: product root, candidate, product.
# Per arm: decode at depth 0 and 16k (bench/quick_tps.py) and 6 greedy answers for identity.
#   bash bench/concat_ab.sh <candidate root>   -> receipts/concat_ab.log, logs/catab_<arm>.answers.jsonl
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W)"; CAND="$1"; LOG=receipts/concat_ab.log; QT=bench/quick_tps.py
MODEL="$ROOT\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() {
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4; }
answers() { PYTHONUTF8=1 python - "$1" <<'EOF'
import json, sys, urllib.request
key = open("artifacts/api_key.txt").read().strip()
prompts = ["Write a Python function that returns the n-th Fibonacci number iteratively, with a docstring.",
           "Explain in three sentences why the sky is blue.",
           "List five prime numbers greater than 100 and say how you checked them.",
           "Write a bash one-liner that counts lines in all .py files under the current directory.",
           "Translate to French: The meeting moved to Thursday because the room was booked.",
           "What is 37 * 43? Show the steps."]
with open(sys.argv[1], "w", encoding="utf-8") as out:
    for p in prompts:
        body = {"model": "m", "messages": [{"role": "user", "content": p}], "max_tokens": 400, "temperature": 0,
                "chat_template_kwargs": {"enable_thinking": False}}
        req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
        r = json.loads(urllib.request.urlopen(req, timeout=600).read())
        out.write(json.dumps({"prompt": p, "text": r["choices"][0]["message"]["content"]}, ensure_ascii=False) + "\n")
EOF
}
for A in "old|$ROOT" "new|$CAND" "old2|$ROOT"; do
  NAME=${A%%|*}; R=${A#*|}
  stop_srv
  env BONSAI_LAYER=0 BONSAI_MODEL="$MODEL" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$R\\start-server.ps1' -RedirectStandardOutput '$ROOT\\logs\\catab_$NAME.launcher.log'"
  ok=0; for i in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME ($R): health=$ok; $(grep '^kv' logs/catab_$NAME.launcher.log | cut -c1-80)"
  [ $ok = 1 ] || continue
  answers "logs/catab_$NAME.answers.jsonl"
  for d in 0 16000; do PYTHONUTF8=1 python $QT --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $d 2>&1 | tee -a "$LOG"; done
done
stop_srv
python - <<'EOF' | tee -a "$LOG"
import json
a = [json.loads(l)["text"] for l in open("logs/catab_old.answers.jsonl", encoding="utf-8")]
for n in ("new", "old2"):
    try:
        b = [json.loads(l)["text"] for l in open(f"logs/catab_{n}.answers.jsonl", encoding="utf-8")]
        print(f"identity old vs {n}: {sum(x == y for x, y in zip(a, b))}/{len(a)} same")
    except FileNotFoundError:
        print(f"identity old vs {n}: no answers")
EOF
say "=== concat ab done"

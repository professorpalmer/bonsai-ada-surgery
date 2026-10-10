#!/usr/bin/env bash
# PrismML #346 on an RTX 4070: illegal memory access after a long prefill with q4_0 K/V + FA on prism-b10770.
# The reporter's command (no drafter, default -b/-ub, 65k slot), a needle prompt of ~30k and ~45k tokens
# (code word at the start, a repeated filler sentence, the question at the end), max_tokens 3000.
# Arms: b10770 as is, b10770 with bf197c43d (#312) reverted. BALLAST_MIB=N holds N MiB of VRAM first.   -> receipts/prism346.log
cd "$(dirname "$0")/.." || exit 1
MODEL="$(pwd -W)/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf"; LOG=receipts/prism346.log; RT=$(pwd)/bin
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
# BALLAST_MIB=N: hold N MiB of VRAM in a second process (tools/vram-ballast), so the server sees a smaller card
if [ -n "$BALLAST_MIB" ]; then
  rm -f logs/ballast.stop
  ./tools/vram-ballast/ballast.exe $BALLAST_MIB logs/ballast.stop > logs/ballast.log 2>&1 &
  sleep 4; say "ballast: $(cat logs/ballast.log) | free VRAM $(nvidia-smi --query-gpu=memory.free --format=csv,noheader)"
fi
IFS=" " read -ra ARMS <<< "${PRISM_ARMS:-b10770|/tmp/build-b10770/bin b10770-revert312|/tmp/build-b10770-r312/bin}"
for A in "${ARMS[@]}"; do
  NAME=${A%%|*}; B=${A#*|}
  for N in ${SIZES:-30000 45000}; do
    powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 -Ports 8091 >/dev/null 2>&1; sleep 3
    ( cd "$B" && PATH="$RT:$PATH" ./llama-server.exe -m "$MODEL" --host 127.0.0.1 --port 8091 -ngl 99 -c 65536 -np 1 -fa on \
        -ctk q4_0 -ctv q4_0 --jinja --reasoning-budget 2048 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05 --threads 8 \
        > "$OLDPWD/logs/prism346_${NAME}_$N.log" 2>&1 & )
    ok=0; for k in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:8091/health | grep -q ok && { ok=1; break; }; done
    [ $ok = 1 ] || { say "$NAME $N: no health"; continue; }
    res=$(PYTHONUTF8=1 python - "$N" <<'EOF'
import json, sys, urllib.request, urllib.error
n = int(sys.argv[1])
filler = "The quick brown fox jumps over the lazy dog near the riverbank on a sunny afternoon. "
body_text = "Remember this code word: AMBERFALCON.\n\n" + filler * (n // 19) + "\n\nWhat was the code word at the start? Answer with the word only."
req = urllib.request.Request("http://127.0.0.1:8091/v1/chat/completions",
    data=json.dumps({"messages": [{"role": "user", "content": body_text}], "max_tokens": 3000}).encode(),
    headers={"Content-Type": "application/json"})
try:
    r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
    t = r.get("timings", {})
    c = r["choices"][0]["message"].get("content") or ""
    print(f"ok prompt {t.get('prompt_n')} completion {t.get('predicted_n')} content={c.strip()[:40]!r} AMBERFALCON={'AMBERFALCON' in c.upper()}")
except Exception as e:
    print(f"FAILED {type(e).__name__}: {str(e)[:120]}")
EOF
)
    alive=$(curl -s -m 2 http://127.0.0.1:8091/health | grep -c ok)
    err=$(grep -a -m1 -o "CUDA error[^\r]*\|illegal memory access[^\r]*" logs/prism346_${NAME}_$N.log | head -1)
    say "$NAME prompt ~$N: $res | server alive=$alive | ${err:-no CUDA error}"
  done
done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 -Ports 8091 >/dev/null 2>&1
[ -n "$BALLAST_MIB" ] && { touch logs/ballast.stop; sleep 3; }
say "=== done"

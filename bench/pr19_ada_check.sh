#!/usr/bin/env bash
# PR #19 on Ada (RTX 4070, 12 GB recipe, q8_0 K/V, 262k): chunked prefill attention (GGML_CUDA_FA_CHUNK) off vs on in
# one binary. (1) test-backend-ops FLASH_ATTN_EXT off / 256 / 768; (2) one server session per arm through
# 4k -> 64k -> 128k -> 192k -> 250k (quick_tps: first line = prefill of the new depth, then 2 follow-ups), lowest free
# VRAM; (3) texts with drafting + lookup at 64k and 160k; (4) fresh long prompts with the chunk on.
#   bash bench/pr19_ada_check.sh <root>   -> receipts/pr19_ada.log, receipts/pr19_ada.jsonl
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"
LOG=receipts/pr19_ada.log; OUT=receipts/pr19_ada.jsonl; CHUNK=${PR19_CHUNK:-32768}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '$ROOT\bin\*' } | Stop-Process -Force" >/dev/null 2>&1; sleep 4; }
start_srv() { # NAME "ENVS"
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $2 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\pr19_$1.launcher.log' -RedirectStandardError '$REPO\logs\pr19_$1.server.log'"
  local ok=0 i; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" >/dev/null 2>&1 || ok=0
  say "arm $1 ($2): health=$ok; $(grep '^kv' logs/pr19_$1.launcher.log | cut -c1-110)"
  [ $ok = 1 ]
}
minfree_start() { ( lo=999999; while [ ! -f logs/pr19.stopvram ]; do f=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1 | tr -d ' \r'); [ "$f" -lt "$lo" ] && lo=$f && echo $lo > logs/pr19.minfree; sleep 1; done ) & }
minfree_stop() { touch logs/pr19.stopvram; sleep 2; rm -f logs/pr19.stopvram; cat logs/pr19.minfree 2>/dev/null; }
BIN="$(cygpath -u "$ROOT")/bin"
say "=== PR #19 Ada check, engine $("$BIN/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), chunk $CHUNK"
stop_srv
# (1) operator tests
for c in 0 256 768; do
  r=$(cd "$BIN" && GGML_CUDA_FA_CHUNK=$c ./test-backend-ops.exe -o FLASH_ATTN_EXT -b CUDA0 2>&1 | grep -c "OK"; cd "$BIN" && GGML_CUDA_FA_CHUNK=$c ./test-backend-ops.exe -o FLASH_ATTN_EXT -b CUDA0 2>&1 | grep -E "^ *FLASH_ATTN_EXT.*FAIL" | head -3)
  say "test-backend-ops FLASH_ATTN_EXT chunk=$c: $(echo "$r" | head -1) OK; fails: $(echo "$r" | tail -n +2 | wc -l)"
done
# (2) depth sequence per arm
for A in "off|GGML_CUDA_FA_CHUNK=0" "on|GGML_CUDA_FA_CHUNK=$CHUNK"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  start_srv depth-$NAME "$ENVS" || continue
  rm -f logs/pr19.minfree; minfree_start
  for D in 4000 64000 128000 192000 250000; do
    QTPS_TIMEOUT=3600 PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $D 2>&1 | sed "s/^/$NAME /" | tee -a "$LOG"
  done
  say "$NAME lowest free VRAM $(minfree_stop) MiB"
done
# (3) texts with drafting + lookup, off vs on
for D in 64000 160000; do for A in "off|GGML_CUDA_FA_CHUNK=0" "on|GGML_CUDA_FA_CHUNK=$CHUNK"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  start_srv text-d$D-$NAME "$ENVS" && PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "d$D-$NAME" --out $OUT --depth $D 2>&1 | tail -1 | tee -a "$LOG"
done; done
stop_srv
python - "$OUT" <<'EOF' | tee -a "$LOG"
import json, sys
from collections import defaultdict
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
by = defaultdict(dict)
for r in rows:
    d, arm = r["tag"].rsplit("-", 1)
    by[(d, r["kind"], r["item"])][arm] = r["sha"]
for d in sorted({k[0] for k in by}):
    items = [(k, v) for k, v in by.items() if k[0] == d and "off" in v and "on" in v]
    same = sum(v["off"] == v["on"] for k, v in items)
    diff = ", ".join(f"{k[1]}:{k[2]}" for k, v in items if v["off"] != v["on"])
    print(f"texts {d}: {same}/{len(items)} identical off vs on{'; differ: ' + diff if diff else ''}")
EOF
# (4) fresh long prompts with the chunk on
bash bench/one_token_ab.sh "pr19-chunk|$ROOT|BONSAI_TIER=1,BONSAI_CTX=262144,GGML_CUDA_FA_CHUNK=$CHUNK" > logs/pr19_onetoken.run.log 2>&1
grep -A6 "arm pr19-chunk" receipts/one_token_ab.log | tail -6 | tee -a "$LOG"
stop_srv
say "=== done"

#!/usr/bin/env bash
# PR #13 on Ada (RTX 4070, 12 GB recipe): the packed KQ mask with MTP drafting + lookup at 32k and 64k (texts against
# the f16 mask), the VRAM it saves at a pinned line, fresh long prompts with it on, and the release smoke of the new
# engine with its default switches.   bash bench/pr13_ada_check.sh <root>   -> receipts/pr13_ada.log, receipts/pr13_ada.jsonl
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"; LOG=receipts/pr13_ada.log; OUT=receipts/pr13_ada.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; powershell -NoProfile -ExecutionPolicy Bypass -File ../mirai-s-serve/tooling/stop.ps1 >/dev/null 2>&1; powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '$ROOT\bin\*' } | Stop-Process -Force" >/dev/null 2>&1; sleep 4; }
start_srv() { # NAME "ENVS"
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $2 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\pr13_$1.launcher.log' -RedirectStandardError '$REPO\logs\pr13_$1.server.log'"
  local ok=0 i; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" >/dev/null 2>&1 || ok=0
  say "arm $1 ($2): health=$ok; $(grep '^kv' logs/pr13_$1.launcher.log | cut -c1-120)"
  [ $ok = 1 ]
}
used() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 | tr -d ' \r'; }
say "=== PR #13 Ada check, engine $("$(cygpath -u "$ROOT")/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
# (b) VRAM at a pinned line, 32k request
for m in 0 1; do start_srv vram-mask$m "BONSAI_KV_VRAM_CELLS=110592 LLAMA_ARG_KQ_MASK_PACKED=$m" && { PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 32000 2>&1 | tail -1 | tee -a "$LOG"; say "mask$m used $(used) MiB"; }; done
# (a) texts with drafting + lookup at 32k and 64k, f16 vs packed mask
for D in 32000 64000; do for m in 0 1; do
  start_srv text-d$D-mask$m "LLAMA_ARG_KQ_MASK_PACKED=$m" && PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "d$D-mask$m" --out $OUT --depth $D 2>&1 | tail -1 | tee -a "$LOG"
done; done
stop_srv
# (c) fresh long prompts, packed mask on, 12 GB recipe
bash bench/one_token_ab.sh "pr13-mask1|$ROOT|BONSAI_TIER=1,BONSAI_CTX=262144,LLAMA_ARG_KQ_MASK_PACKED=1" > logs/pr13_onetoken.run.log 2>&1
grep -A6 "arm pr13-mask1" receipts/one_token_ab.log | tail -6 | tee -a "$LOG"
stop_srv
# (d) release smoke: new engine, default switches, against the product bin
bash bench/release_smoke.sh "$(cygpath -m "$ROOT")" pr13 > logs/pr13_smoke.run.log 2>&1; say "release smoke exit $?: $(tail -2 receipts/release_smoke_pr13.log | head -1)"
stop_srv
say "=== done"

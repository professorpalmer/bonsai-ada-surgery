#!/usr/bin/env bash
# 12 GB recipe: the shared CUDA pool + 256-token MTP draft micro-batch (BONSAI_SHARED_POOL=1), as the Mirai S serve uses.
# Phase 1: VRAM used after a 32k request, pool off vs on, same VRAM line -> the saving S (MiB).
# Phase 2: pool on with BONSAI_POOL_MIB = S - 32 (the VRAM line moves up): decode at 131k and 180k against pool off,
#          and fresh long prompts for 1-token answers (the race that patch 0045 fixed).
#   bash bench/pool_ab.sh   -> receipts/pool_ab.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/pool_ab.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
start_srv() { # NAME "ENV ASSIGNMENTS"
  stop_srv
  env BONSAI_LAYER=0 LLAMA_ARG_CHECKPOINT_EVERY_NT=8192 $2 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\pool_$1.launcher.log' -RedirectStandardError '$REPO\\logs\\pool_$1.server.log'"
  local ok=0 i; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" >/dev/null 2>&1 || ok=0
  say "arm $1 ($2): health=$ok; $(grep '^kv' logs/pool_$1.launcher.log)"
  [ $ok = 1 ]
}
used() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 | tr -d ' \r'; }
tps() { PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $1 2>&1 | tail -4 | tee -a "$LOG"; }

# phase 1: same line (pinned), pool off vs on
LINE=110592
start_srv m-off "BONSAI_KV_VRAM_CELLS=$LINE" && { tps 32000 >/dev/null; U_OFF=$(used); say "m-off used $U_OFF MiB"; }
start_srv m-on "BONSAI_KV_VRAM_CELLS=$LINE BONSAI_SHARED_POOL=1" && { tps 32000 >/dev/null; U_ON=$(used); say "m-on used $U_ON MiB"; }
S=$(( ${U_OFF:-0} - ${U_ON:-0} - 32 )); [ $S -lt 0 ] && S=0
say "saving: ${U_OFF:-?} - ${U_ON:-?} MiB, BONSAI_POOL_MIB=$S"

# phase 2: automatic line, pool off vs on with the saving
for D in 131000 180000; do
  start_srv off-$D "" && tps $D
  start_srv on-$D "BONSAI_SHARED_POOL=1 BONSAI_POOL_MIB=$S" && tps $D
done
stop_srv
say "fresh long prompts with the pool on (1-token check)"
bash bench/one_token_ab.sh "pool-on|$REPO|BONSAI_TIER=1,BONSAI_CTX=262144,BONSAI_SHARED_POOL=1,BONSAI_POOL_MIB=$S" > logs/pool_ab_onetoken.run.log 2>&1
grep -A6 "arm pool-on" receipts/one_token_ab.log | tail -6 | tee -a "$LOG"
stop_srv
say "=== done"

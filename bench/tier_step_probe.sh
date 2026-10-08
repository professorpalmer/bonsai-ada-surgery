#!/usr/bin/env bash
# Prefill cost step at the tiered-KV line. The served 159k prefill costs 0.012 ms per token for each 1k of depth
# below the VRAM line (119,040 cells), then jumps by about 0.67 ms per token at the line and grows twice as fast
# past it (receipts/prefill_depth_fit.txt). With the line pinned low (BONSAI_KV_VRAM_CELLS), a short prefill shows
# the same step, so each arm takes about a minute. The arms change one thing each, to find the cause.
#   bash bench/tier_step_probe.sh [depth] [arm ...]      arm = name:VAR=value,VAR=value   -> receipts/tier_step.log
# Per arm: one quick_tps prefill to <depth>, then the cost of each 2,048-token prefill chunk from the server log.
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; DEPTH="${1:-40000}"; shift
LOG=receipts/tier_step.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ARMS=("$@")
[ ${#ARMS[@]} -gt 0 ] || ARMS=("line16k:BONSAI_KV_VRAM_CELLS=16384" "line16k-ctx64k:BONSAI_KV_VRAM_CELLS=16384,BONSAI_CTX=65536" "line16k-nostage:BONSAI_KV_VRAM_CELLS=16384,GGML_CUDA_KV_TIER_STAGING=0" "line16k-mtpoff:BONSAI_KV_VRAM_CELLS=16384,BONSAI_SPEC=0" "allvram:BONSAI_TIER=0,BONSAI_CTX=65536")
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
ours() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$1"; }
say "=== tier step probe, depth $DEPTH"
for A in "${ARMS[@]}"; do
  NAME=${A%%:*}; VARS=${A#*:}
  stop_srv
  ENVS=(BONSAI_MODEL="$MODEL" BONSAI_LAYER=0)
  IFS=',' read -ra KV <<< "$VARS"; for kv in "${KV[@]}"; do ENVS+=("$kv"); done
  env "${ENVS[@]}" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\tierstep.$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\tierstep.$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  ours "$REPO" || ok=0
  say "arm $NAME ($VARS): health=$ok; $(grep '^kv' logs/tierstep.$NAME.launcher.log)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH 2>&1 | grep -m1 "depth" | sed "s/^/$NAME: /" | tee -a "$LOG"
  grep "prompt processing, n_tokens" logs/tierstep.$NAME.server.log | sed -E 's/.*n_tokens = +([0-9]+).*t = +([0-9.]+) s.*/\1 \2/' \
    | awk -v n="$NAME" 'NR>1 && $1>pn {d=$1-pn; dt=$2-pt; printf "%s chunk to %6d: %.3f ms/tok\n", n, $1, 1000*dt/d} {pn=$1; pt=$2}' | tee -a "$LOG"
done
stop_srv
say "=== done"

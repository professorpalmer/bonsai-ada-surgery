#!/usr/bin/env bash
# Decode speed at depth, one server session per arm, arms given as "name|root|env" lines in a file (root "-" = this
# repo, the release bin). 12 GB recipe, layer off. Per arm: bench/quick_tps.py at each depth, the server log kept as
# logs/arms_<tag>_<name>.server.log, and with GGML_CUDA_OP_TIMING=1 in the env the op timing lines from that log.
# RAM guard on.
#   DEPTHS="192000" bash bench/depth_arms.sh <arms file> <tag>   -> receipts/depth_arms.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ARMS_FILE=${1:?arms file}; TAG=${2:?tag}; LOG=receipts/depth_arms.log; DEPTHS=${DEPTHS:-192000}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
say "=== depth arms $TAG: depths $DEPTHS ($ARMS_FILE)"
while IFS='|' read -r NAME ROOT ENVS; do
  [ -z "$NAME" ] || [ "${NAME:0:1}" = "#" ] && continue
  R="$REPO"; [ "$ROOT" != "-" ] && R="$(cygpath -w "$ROOT")"
  SLOG="logs/arms_${TAG}_${NAME}.server.log"
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1 < /dev/null; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$R\start-server.ps1' -RedirectStandardOutput '$REPO\logs\arms_${TAG}_${NAME}.launcher.log' -RedirectStandardError '$REPO\\$(cygpath -w "$SLOG")'" < /dev/null
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME ($R; $ENVS): health=$ok; $(grep '^kv' logs/arms_${TAG}_${NAME}.launcher.log | cut -c1-80)"
  [ $ok = 1 ] || continue
  for D in $DEPTHS; do
    PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $D < /dev/null 2>&1 | sed "s/^/$NAME /" | tee -a "$LOG"
  done
  if echo "$ENVS" | grep -q GGML_CUDA_OP_TIMING; then
    # the last block the server printed (every 100 graphs: ms per graph, then the top ops)
    awk '/op timing over/ {blk=$0 "\n"; n=0; next} blk != "" && n < 12 {blk=blk $0 "\n"; n++} END {printf "%s", blk}' "$SLOG" \
      | sed "s/^/$NAME timing: /" | cut -c1-200 | tee -a "$LOG"
  fi
  n=$(grep -c "one sync per K write" "$SLOG"); say "$NAME: 'one sync per K write' warnings: $n"
done < "$ARMS_FILE"
say "=== $TAG done"

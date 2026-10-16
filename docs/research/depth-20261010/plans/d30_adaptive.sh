#!/usr/bin/env bash
# D30: adaptive sparse page budget, q3_0, 245k, 2060-like line pinned at 80,640, sparse forced (AUTO off), graphs on,
# packed mask on. Arms: cap 1/4 (FRAC 0.25) with floor 1/8 (FLOOR_FRAC 0.125) and DELTA t = 4 / 8 logits; KEPTSTAT logs
# the mean kept share (the speed proxy; 1/8 = 0.125, 1/4 = 0.25 of host pages). Per arm, one fresh server per set:
# needle_depth n 24, needle_depth n 28, code_needle n 20 (+ --diff), all at 245k.
# Gate (declared before the run): an arm passes when every item matches dense item by item on the three sets (dense:
# D26h-1e / D26h-3: n24 wrong only 14, n28 wrong 15, 19, 24; copies 19 strict / 20 lenient) AND its mean kept share is
# below 0.20. The passing arm with the lowest kept share then gets the 2060's speed run.
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "$TEMP/root-d30")"
LOG=docs/receipts/sparse_adaptive_d30.log; OUT=docs/receipts/sparse_adaptive_d30.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
BASE="BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_CTK=q3_0 LLAMA_ARG_KQ_MASK_PACKED=1 BONSAI_SPARSE=0 GGML_CUDA_FA_SPARSE=12288,64,1024 GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9 GGML_CUDA_FA_SPARSE_MIN_HOST=32768 GGML_CUDA_FA_SPARSE_FRAC=0.25 GGML_CUDA_FA_SPARSE_FLOOR_FRAC=0.125 GGML_CUDA_FA_SPARSE_KEPTSTAT=1"
start() {   # $1 name, rest env
  local NAME=$1; shift
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  env BONSAI_MODEL="$MODEL" $BASE "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\${NAME}.launcher.log' -RedirectStandardError '$REPO\logs\${NAME}.server.log'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME: health=$ok ($*); $(grep '^kv' logs/${NAME}.launcher.log | head -1 | cut -c1-70)"
  [ $ok = 1 ]
}
say "=== D30 start: $(cat "$TEMP/root-d30/ENGINE.txt"), mem clock under load sampled per arm"
for T in 4 8; do
  for SET in n24 n28 copies; do
    NAME=d30_t${T}_$SET
    start $NAME GGML_CUDA_FA_SPARSE_DELTA=$T || continue
    case $SET in
      n24) PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 24 --tag $NAME --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG" ;;
      n28) PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 28 --tag $NAME --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG" ;;
      copies) PYTHONUTF8=1 python bench/code_needle.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 20 --diff --tag $NAME --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG" ;;
    esac
    say "$NAME: clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader); last KEPTSTAT: $(grep KEPTSTAT logs/${NAME}.server.log | tail -1 | sed 's/.*KEPTSTAT //')"
  done
done
say "=== D30 done"

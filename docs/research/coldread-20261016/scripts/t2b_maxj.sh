#!/usr/bin/env bash
# T2b-1: MMQ column tile cap (GGML_CUDA_MMQ_MAX_J = 128 default / 64 / 48) on the PTQ1_0 prefill matmuls.
# Why: on sm_75 the PTQ1_0 MMQ kernels use 255 registers and spill 112-136 B at J >= 80 (J 64: 24 B, J <= 48: none);
# on sm_89 they do not spill. This 4070 (sm_89) run is the CONTROL: expect no gain here. The 2060 runs the same script
# on its own sm_75 build of t2-prefill 5bb256bb4.
# Gates (declared before the run):
#   G1 MUL_MAT op tests for type_a=ptq1_0: 0 FAIL at each MAX_J.
#   G2 the perf rate of the 12 PTQ1_0 prefill cases (n=512, n=2048), alternated x2 per arm (stderr kept apart, so CUDA graph log lines do not split the timing lines); a cap counts only if its sum
#      of us/run is >= 3 % below the J=128 arm in both repeats.
#   G3 the cold prefill rate at 4k / 16k / 32k (quick_tps, fresh server per arm, alternated x2), same 3 % rule.
#   Answers (d27_hash.py, temp 0) are recorded per arm; a cap changes the stream-k split, so a hash change alone is not
#   a failure; a changed default would need a PPL check at <= 16k first.
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "$TEMP/root-t2b")"
SP="$(cd "$(dirname "$0")" && pwd)"   # this scripts folder
TBO="$TEMP/root-t2b/bin/test-backend-ops.exe"
LOG=docs/receipts/prefill_mmq_maxj_t2b.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
BASE="BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_CTK=q3_0 LLAMA_ARG_KQ_MASK_PACKED=1 BONSAI_SPARSE=0 GGML_CUDA_FA_CHUNK=32768"
say "=== T2b-1 start: $(cat "$TEMP/root-t2b/ENGINE.txt"), driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
for J in 128 64 48; do
  GGML_CUDA_MMQ_MAX_J=$J "$TBO" -o MUL_MAT -b CUDA0 -p "type_a=ptq1_0" > "logs/t2b_optest_j$J.log" 2>&1
  say "G1 J=$J: $(grep -cE '^ +MUL_MAT.*OK' "logs/t2b_optest_j$J.log") OK, $(grep -c FAIL "logs/t2b_optest_j$J.log") FAIL lines, $(grep -E 'backends passed' "logs/t2b_optest_j$J.log" | tr -s ' ')"
done
for R in 1 2; do
  for J in 128 64 48; do
    GGML_CUDA_MMQ_MAX_J=$J "$TBO" perf -o MUL_MAT -b CUDA0 -p "type_a=ptq1_0" > "logs/t2b_perf_j${J}_r$R.log" 2> "logs/t2b_perf_j${J}_r$R.err"
    grep -E "n=(512|2048),.*us/run" "logs/t2b_perf_j${J}_r$R.log" | sed -E 's/.*m=([0-9]+),n=([0-9]+),k=([0-9]+).* ([0-9.]+) us\/run.* ([0-9.]+) [GT]FLOPS.*/m=\1 n=\2 k=\3 \4 us/' | sed "s/^/G2 r$R J=$J /" | tee -a "$LOG"
    say "G2 r$R J=$J sum us/run: $(grep -E "n=(512|2048),.*us/run" "logs/t2b_perf_j${J}_r$R.log" | grep -oE '[0-9.]+ us/run' | awk '{s+=$1} END {printf "%.1f", s}'); mem clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  done
done
for R in 1 2; do
  for J in 128 64 48; do
    NAME="j$J"
    SLOG="$REPO\\logs\\t2b_${NAME}_r$R.server.log"; LLOG="$REPO\\logs\\t2b_${NAME}_r$R.launcher.log"
    powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
    env BONSAI_MODEL="$MODEL" $BASE GGML_CUDA_MMQ_MAX_J=$J powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$LLOG' -RedirectStandardError '$SLOG'"
    ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
    say "G3 r$R $NAME: health=$ok; mem clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
    [ $ok = 1 ] || continue
    [ $R = 1 ] && PYTHONUTF8=1 python "$SP/d27_hash.py" http://127.0.0.1:8080 artifacts/api_key.txt < /dev/null 2>&1 | sed "s/^/$NAME hash /" | tee -a "$LOG"
    for D in 4000 16000 32000; do
      PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $D < /dev/null 2>&1 | grep "code " | sed "s/^/G3 r$R $NAME /" | tee -a "$LOG"
    done
  done
done
say "=== T2b-1 done"

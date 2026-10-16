#!/usr/bin/env bash
# T2a: prefill attention with 2 Q heads per column group (GGML_CUDA_FA_PREFILL_NCOLS2=2) vs the default 8, on the 8 GB
# prefill path: q3_0, line pinned 80,640, GGML_CUDA_FA_CHUNK=32768 (chunked FA past the f16 limit, as the 8 GB launcher),
# sparse off. Gates (declared before the run): FLASH_ATTN_EXT op tests 0 FAIL; answers byte-identical (d27_hash.py, 3
# prompts, temp 0) between the arms; then the cold prefill rate at 32k / 64k / 128k (quick_tps, fresh server per arm,
# alternated x2). This is sm_89; the 2060 (sm_75) measures the same switch on its own card.
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "$TEMP/root-t2")"
SP="$(cd "$(dirname "$0")" && pwd)"   # this scripts folder
LOG=docs/receipts/prefill_ncols2_t2a.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
BASE="BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_CTK=q3_0 LLAMA_ARG_KQ_MASK_PACKED=1 BONSAI_SPARSE=0 GGML_CUDA_FA_CHUNK=32768"
say "=== T2a start: $(cat "$TEMP/root-t2/ENGINE.txt"), driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
"$TEMP/root-t2/bin/test-backend-ops.exe" -o FLASH_ATTN_EXT -b CUDA0 > logs/t2a_optest.log 2>&1
say "op test (default): $(grep -E 'tests passed' logs/t2a_optest.log | tail -1 | tr -s ' ')"
GGML_CUDA_FA_PREFILL_NCOLS2=2 "$TEMP/root-t2/bin/test-backend-ops.exe" -o FLASH_ATTN_EXT -b CUDA0 > logs/t2a_optest_nc2.log 2>&1
say "op test (NCOLS2=2): $(grep -E 'tests passed' logs/t2a_optest_nc2.log | tail -1 | tr -s ' ') $(grep -c FAIL logs/t2a_optest_nc2.log) FAIL lines"
for R in 1 2; do
  for A in "nc8|" "nc2|GGML_CUDA_FA_PREFILL_NCOLS2=2"; do
    NAME=${A%%|*}; ENVS=${A#*|}
    SLOG="$REPO\logs\t2a_${NAME}_r$R.server.log"; LLOG="$REPO\logs\t2a_${NAME}_r$R.launcher.log"
    powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
    env BONSAI_MODEL="$MODEL" $BASE $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$LLOG' -RedirectStandardError '$SLOG'"
    ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
    say "r$R $NAME: health=$ok ($ENVS); mem clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
    [ $ok = 1 ] || continue
    [ $R = 1 ] && PYTHONUTF8=1 python "$SP/d27_hash.py" http://127.0.0.1:8080 artifacts/api_key.txt < /dev/null 2>&1 | sed "s/^/$NAME hash /" | tee -a "$LOG"
    for D in 32000 64000 128000; do
      PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $D < /dev/null 2>&1 | grep "code " | sed "s/^/r$R $NAME /" | tee -a "$LOG"
    done
  done
done
say "=== T2a done"

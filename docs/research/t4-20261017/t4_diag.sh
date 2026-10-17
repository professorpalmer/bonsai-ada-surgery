#!/usr/bin/env bash
# T4 diagnostics (not a gate): dump the probe scores for one 245k needle question (vault 2, lost in T4-2) and test
# other aggregations offline (t4_analyze.py). Arm d7: the kernel session's setting (8 blocks, probe 7); arm d15: 16
# blocks, probe 15. Root %TEMP%\bonsai-t4d = the zip + the dump build (a269a922c9 + the dump diff).
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=docs/research/t4-20261017/t4_diag.log; say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
R=$TEMP/bonsai-t4d; rm -rf "$R"; mkdir -p "$R"
python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $B/artifacts/release/bonsai-bundle-win-x64-20261017.zip)" "$(cygpath -w $R)"
cp /c/Users/<user>/Projects/build-t4b/bin/*.exe /c/Users/<user>/Projects/build-t4b/bin/*.dll "$R/bin/"
D=$TEMP/t4dump; rm -rf "$D"; mkdir -p "$D"; K="$(cygpath -w $R/artifacts/api_key.txt)"
for arm in "d7|keep=16384,layers=8,probe=7|7" "d15|keep=16384,layers=16,probe=15|15"; do
  IFS='|' read -r NAME CFG L <<< "$arm"
  stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_CTK=q3_0 BONSAI_KV_VRAM_CELLS=80640 LLAMA_FAST_READ="$CFG" LLAMA_FAST_READ_DUMP="$(cygpath -w $D)\$NAME" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $R)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t4d_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\t4d_$NAME.server.log'"
  ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "=== $NAME ($CFG): health=$ok"
  PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file "$K" --depth 245000 --n 24 --only 2 --tag t4d_$NAME < /dev/null 2>&1 | head -1 | cut -c1-200 | tee -a "$LOG"
  grep 'fast read' logs/t4d_$NAME.server.log | sed -E 's/^[0-9.]+ //' | cut -c1-200 | tee -a "$LOG"
  PYTHONUTF8=1 python "$SP/t4_analyze.py" --prefix "$(cygpath -w $D)\$NAME" --layer $L --key-file "$K" --target 2 2>&1 | tee -a "$LOG"
done
say "=== T4 diag done"

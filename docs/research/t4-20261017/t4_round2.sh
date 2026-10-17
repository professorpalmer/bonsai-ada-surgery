#!/usr/bin/env bash
# T4 round 2 (#138; declared before the runs in docs/research/t4-20261017/EXPERIMENTS.md "round 2"): needle n24 at 245k,
# same recipe, block score = best token (bmax=1), budgets keep=16384 and keep=32768. Root %TEMP%\bonsai-t4d (the build
# with bmax). Reference: dense 24/24 (467.8 s cold), round 1 (sum, keep=16384) 7/24.
B=/c/Users/<user>/Projects/bonsai-2-27b-serve
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=docs/research/t4-20261017/t4_round2.log; OUT=docs/research/t4-20261017/t4_round2.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
R=$TEMP/bonsai-t4d; cp /c/Users/<user>/Projects/build-t4b/bin/*.exe /c/Users/<user>/Projects/build-t4b/bin/*.dll "$R/bin/"
K="$(cygpath -m $R/artifacts/api_key.txt)"
say "=== T4 round 2 start: $("$R/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), branch $(git -C /c/Users/<user>/Projects/wt-t4b log --oneline -1 | cut -c1-12); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
for arm in "b16|keep=16384,bmax=1" "b32|keep=32768,bmax=1"; do
  IFS='|' read -r NAME CFG <<< "$arm"
  stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_CTK=q3_0 BONSAI_KV_VRAM_CELLS=80640 LLAMA_FAST_READ="$CFG" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $R)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t4r2_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\t4r2_$NAME.server.log'"
  ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($CFG): health=$ok"
  PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file "$K" --depth 245000 --n 24 --tag t4r2_$NAME --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG"
  say "$NAME: clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader); CUDA errors $(grep -c 'CUDA error' logs/t4r2_$NAME.server.log)"; grep 'fast read:' logs/t4r2_$NAME.server.log | head -1 | sed -E 's/^[0-9.]+ //' | cut -c1-200 | tee -a "$LOG"
done
say "=== T4 round 2 done"

#!/usr/bin/env bash
# T4-A fast read gates on the 4070 (#138, declared before the runs): T4-0 mode off = product hashes; T4-1/T4-2 needle
# n24 at 245k with LLAMA_FAST_READ=keep=16384 (first item = cold TTFT); T4-3 n24 at 128k. Recipe: BONSAI_8GB=1, q3_0,
# line 80,640, layer off. Roots: %TEMP%\bonsai-t4ref = the bundle-20261017 zip; %TEMP%\bonsai-t4 = the same + the T4 bins.
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; FK=/c/Users/<user>/AppData/Local/Temp/claude/<session>/scratchpad
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
mkdir -p docs/research/t4-20261017; LOG=docs/research/t4-20261017/t4_gates.log; OUT=docs/research/t4-20261017/t4_gates.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261017.zip
for R in bonsai-t4ref bonsai-t4; do rm -rf "$TEMP/$R"; mkdir -p "$TEMP/$R"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $ZIP)" "$(cygpath -w $TEMP/$R)"; done
cp /c/Users/<user>/Projects/build-t4b/bin/*.exe /c/Users/<user>/Projects/build-t4b/bin/*.dll "$TEMP/bonsai-t4/bin/"
say "=== T4 gates start: ref $("$TEMP/bonsai-t4ref/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); t4 $("$TEMP/bonsai-t4/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), branch t4-fastread-b $(git -C /c/Users/<user>/Projects/wt-t4b rev-parse --short HEAD) + diff $(git -C /c/Users/<user>/Projects/wt-t4b diff --stat | tail -1); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
start() { local NAME=$1 R=$2; shift 2; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_CTK=q3_0 BONSAI_KV_VRAM_CELLS=80640 "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/$R)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t4_${NAME}.launcher.log' -RedirectStandardError '$REPO\logs\t4_${NAME}.server.log'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($R $*): health=$ok; $(grep '^kv' logs/t4_${NAME}.launcher.log | head -1 | cut -c1-60)"; [ $ok = 1 ]; }
note() { say "$1: clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader); CUDA errors $(grep -c 'CUDA error' logs/t4_$1.server.log); fast read lines $(grep -c 'fast read:' logs/t4_$1.server.log)"; grep 'fast read' logs/t4_$1.server.log | head -3 | sed -E 's/^[0-9.]+ //' | cut -c1-230 | tee -a "$LOG"; }
key() { cygpath -w "$TEMP/$1/artifacts/api_key.txt"; }
# T4-0
for side in t4ref t4; do start h_$side bonsai-$side && PYTHONUTF8=1 python "$FK/d27_hash.py" http://127.0.0.1:8080 "$(key bonsai-$side)" < /dev/null 2>&1 | sed "s/^/T4-0 $side hash /" | tee -a "$LOG"; note h_$side; done
# T4-1 + T4-2: 245k n24
N=k16_245; start $N bonsai-t4 LLAMA_FAST_READ=keep=16384 && PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file "$(key bonsai-t4)" --depth 245000 --n 24 --tag t4_$N --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG"; note $N
# T4-3: 128k n24
N=k16_128; start $N bonsai-t4 LLAMA_FAST_READ=keep=16384 && PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file "$(key bonsai-t4)" --depth 128000 --n 24 --tag t4_$N --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG"; note $N
say "=== T4 gates done"

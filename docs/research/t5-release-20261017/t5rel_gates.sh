#!/usr/bin/env bash
# Release (T5 opt-in + 8 GB pool reserve) gates R1 / R2-n24 / R4 on the 4070 (plan #138 comments 6241854303, 6241885671).
# Roots: %TEMP%\r-t5ref = the bundle-20261017b zip; %TEMP%\r-t5 = the same + release bins (build-t5rel, a6bfcb1a4f) +
# the launcher of branch launcher/fast-read. Layer off.
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; LWT=/c/Users/<user>/Projects/bonsai-poolres
FK=/c/Users/<user>/AppData/Local/Temp/claude/<session>/scratchpad
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=docs/receipts/t5rel_gates.log; OUT=docs/receipts/t5rel_gates.jsonl; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261017b.zip
for R in r-t5ref r-t5; do rm -rf "$TEMP/$R"; mkdir -p "$TEMP/$R"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $ZIP)" "$(cygpath -w $TEMP/$R)"; done
cp /c/Users/<user>/Projects/build-t5rel/bin/*.exe /c/Users/<user>/Projects/build-t5rel/bin/*.dll "$TEMP/r-t5/bin/"; cp "$LWT/start-server.ps1" "$TEMP/r-t5/"
say "=== T5 release R1/R2/R4: ref $("$TEMP/r-t5ref/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); new $("$TEMP/r-t5/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); launcher $(git -C $LWT log --oneline -1 | cut -c1-12); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
start() { local NAME=$1 R=$2; shift 2; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/$R)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t5r_${NAME}.launcher.log' -RedirectStandardError '$REPO\logs\t5r_${NAME}.server.log'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($R $*): health=$ok; $(grep -E '^fast|^8gb' logs/t5r_${NAME}.launcher.log | cut -c1-90 | tr '\n' '|')"; [ $ok = 1 ]; }
key() { cygpath -m "$TEMP/$1/artifacts/api_key.txt"; }
note() { say "  $1: CUDA errors $(grep -c 'CUDA error' logs/t5r_$1.server.log); window lines $(grep -ci 'prefill window\|PREFILL_WINDOW' logs/t5r_$1.server.log)"; }
# R1: op tests (new bins) + identity off (12 GB default, 8 GB preset), ref vs new
for op in ADD RMS_NORM GET_ROWS SET_ROWS CPY FLASH_ATTN_EXT GATED_DELTA_NET; do
  r=$("$TEMP/r-t5/bin/test-backend-ops.exe" -o $op 2>&1 | tr -d '\r'); say "R1 op $op: $(echo "$r" | grep -E 'tests passed' | tail -1 | sed 's/^ *//'); FAIL lines $(echo "$r" | grep -c FAIL)"
done
for preset in 12gb 8gb; do E=""; [ $preset = 8gb ] && E="BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640"
  for side in r-t5ref r-t5; do N=r1_${preset}_${side#r-}; start $N $side $E && PYTHONUTF8=1 python "$FK/d27_hash.py" http://127.0.0.1:8080 "$(key $side)" < /dev/null 2>&1 | grep 'hash all' | sed "s/^/R1 $preset ${side#r-} /" | tee -a "$LOG"; note $N; done
done
# R4 speed + R2 needles: 8 GB recipe, the new bins, fast read off / on: cold 128k and 245k, then n24 at 245k
P8="BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640"
for arm in "off|" "on|BONSAI_FAST_READ=1"; do
  NAME=${arm%%|*}; E=${arm#*|}
  N=r4_${NAME}_128; start $N r-t5 $P8 $E && PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file "$(key r-t5)" --depth 128000 2>&1 | grep "code   depth" | cut -c1-150 | sed "s/^/R4 $NAME 128k /" | tee -a "$LOG"; note $N
  N=r2_${NAME}_245; start $N r-t5 $P8 $E && PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file "$(key r-t5)" --depth 245000 --n 24 --tag t5r_$NAME --out $OUT < /dev/null 2>&1 | tail -1 | sed "s/^/R2 $NAME n24 /" | tee -a "$LOG"; note $N
  say "  R4 $NAME 245k cold (first n24 item): $(grep "\"t5r_$NAME\"" $OUT | head -1 | grep -o '"wall_s": [0-9.]*')"
done
stopall
say "=== T5 release R1/R2/R4 done"

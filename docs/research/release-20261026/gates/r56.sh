#!/usr/bin/env bash
# release-20261026 R5 (12 GB default) and R6 (BONSAI_8GB=1 on the RTX 4070, line pinned at 90,112 as on the RTX 2060 SUPER):
# the 1025 zip root and the candidate root in turns, fresh server per depth, layer off, quick_tps with QTPS_SAVE.
SP=$(dirname "$(realpath "$0")"); REPO=<projects>/bonsai-saa; SERVE=<projects>/bonsai-2-27b-serve
MODEL="$(cygpath -w $SERVE/models/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf)"; KEY=$SERVE/artifacts/api_key.txt
OLDR=$TEMP/r-1025a; NEWR=$TEMP/r-1026z
LOG=$SP/release_1026.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
[ -d $OLDR/bin ] || { mkdir -p $OLDR; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $SERVE/artifacts/release/bonsai-bundle-win-x64-20261025.zip)" "$(cygpath -w $OLDR)"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $REPO/bench/stop_serve.ps1)" >/dev/null 2>&1; }
one() { local G=$1 d=$2 tag=$3; shift 3; local ROOT=$OLDR; [ $tag = new ] && ROOT=$NEWR; local T=${G}_${tag}_$d
  stop_srv; mkdir -p "$ROOT/artifacts" && cp "$KEY" "$ROOT/artifacts/api_key.txt"
  local LL="$(cygpath -w "$SP/$T.launcher.log")" SL="$(cygpath -w "$SP/$T.server.log")" SS="$(cygpath -w "$ROOT/start-server.ps1")"
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$SS' -RedirectStandardOutput '$LL' -RedirectStandardError '$SL'" </dev/null >/dev/null 2>&1
  local ok=0; for i in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $REPO/bench/serve_owner.ps1)" -Root "$(cygpath -w $ROOT)" >/dev/null || ok=0
  say "$G $T: health=$ok; $(grep -E '^kv ' $SP/$T.launcher.log | tr -d '\r' | cut -c1-110)"
  [ $ok = 1 ] || return
  QTPS_SAVE="$(cygpath -w $SP/texts_${G}_$tag)" PYTHONUTF8=1 python "$REPO/bench/quick_tps.py" --base http://127.0.0.1:8080 --key-file "$(cygpath -w $KEY)" --depth $d 2>&1 \
    | grep -E "^(code|prose|bash) |mean decode|Error|Traceback" | sed "s/^/$G $T: /" | tee -a "$LOG"
  say "$G $T: mem $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  stop_srv
  say "$G $T: CUDA errors $(grep -c 'CUDA error' $SP/$T.server.log)"; }
for d in 4000 32000 128000; do one R5 $d old; one R5 $d new; done
for d in 64000 128000; do one R6 $d old BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112; one R6 $d new BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112; done
for G in R5 R6; do n=0; bad=0; for f in $SP/texts_${G}_old/*.txt; do n=$((n+1)); cmp -s "$f" "$SP/texts_${G}_new/$(basename $f)" || { bad=$((bad+1)); say "$G text $(basename $f): DIFFER"; }; done; say "$G texts: $((n-bad)) / $n identical"; done
say "R5 R6 done"

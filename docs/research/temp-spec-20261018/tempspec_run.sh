#!/usr/bin/env bash
# MTP speed and acceptance against temperature, bundle-20261018e root, 8 GB preset, layer off; spec on (default) and off.
B=%USERPROFILE%/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
R=$TEMP/r-1018ez; RW="$(cygpath -w $R)"; D=%USERPROFILE%/Projects/bonsai-saa/docs/research/temp-spec-20261018; mkdir -p $D; LOG=$D/tempspec.log; OUT="$(cygpath -m $D)/tempspec.jsonl"
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
K="$(cygpath -m $R/artifacts/api_key.txt)"
start() { local NAME=$1; shift; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 BONSAI_LAYER=0 "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$RW\start-server.ps1' -RedirectStandardOutput '$REPO\logs\tempspec_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\tempspec_$NAME.server.log'"
  local ok=0; for i in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($*): health=$ok; $(grep -E '^(spec|draft|mtp)' logs/tempspec_$NAME.launcher.log | head -2 | cut -c1-100 | tr '\n' '|')"; }
say "=== temperature vs MTP: engine $("$R/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
start spec
for d in 4000 16000; do PYTHONUTF8=1 python "$SP/tempspec.py" http://127.0.0.1:8080 "$K" $d "$OUT" spec 2>&1 | cut -c1-220 >> "$LOG"; done
start pmin5 LLAMA_ARG_SPEC_DRAFT_P_MIN=0.5
for d in 4000 16000; do PYTHONUTF8=1 python "$SP/tempspec.py" http://127.0.0.1:8080 "$K" $d "$OUT" pmin5 2>&1 | cut -c1-220 >> "$LOG"; done
start nospec BONSAI_SPEC=0
for d in 4000 16000; do PYTHONUTF8=1 python "$SP/tempspec.py" http://127.0.0.1:8080 "$K" $d "$OUT" nospec 2>&1 | cut -c1-220 >> "$LOG"; done
say "CUDA errors $(cat logs/tempspec_*.server.log | grep -c 'CUDA error')"
stopall
say "=== done"

#!/usr/bin/env bash
# Adaptive MTP depth A/B (README in this research dir): F1 vs A4 vs A3 on the 8 GB preset with replay.
B=${BONSAI_DEV:?the development checkout}; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
R=$TEMP/r-adaptive; RW="$(cygpath -w $R)"; D=$SP/out; mkdir -p $D; LOG=$D/ab.log; OUT="$(cygpath -m $D)/ab.jsonl"
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
K="$(cygpath -m $R/artifacts/api_key.txt)"
say "=== adaptive A/B: engine $("$R/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
for arm in "F1|BONSAI_KV_VRAM_CELLS=90880" "A4|BONSAI_KV_VRAM_CELLS=90624 BONSAI_SPEC=4 BONSAI_SPEC_DEEP=4 LLAMA_ARG_SPEC_DRAFT_ADAPTIVE=1" "A3|BONSAI_KV_VRAM_CELLS=90624 BONSAI_SPEC=3 BONSAI_SPEC_DEEP=3 LLAMA_ARG_SPEC_DRAFT_ADAPTIVE=1"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_LAYER=0 LLAMA_RS_REPLAY=1 LLAMA_ARG_LOG_VERBOSITY=4 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$RW\start-server.ps1' -RedirectStandardOutput '$REPO\logs\ab_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\ab_$NAME.server.log'"
  ok=0; for i in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($ENVS): health=$ok; $(grep -E '^spec ' logs/ab_$NAME.launcher.log | cut -c1-90); $(grep -h 'adaptive MTP draft depth' logs/ab_$NAME.server.log | head -1 | cut -c1-80); RS $(grep -h 'RS buffer size' logs/ab_$NAME.server.log | head -1 | grep -o '[0-9.]* MiB')"
  for d in 4000 32000 64000 128000; do PYTHONUTF8=1 python "$SP/../replay/r2.py" http://127.0.0.1:8080 "$K" $d "$OUT" $NAME 2>&1 | cut -c1-240 >> "$LOG"; done
  say "$NAME CUDA errors $(grep -c 'CUDA error' logs/ab_$NAME.server.log); depth changes $(grep -c 'adaptive draft depth seq' logs/ab_$NAME.server.log)"
done
stopall
say "=== done"

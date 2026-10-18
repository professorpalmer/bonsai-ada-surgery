#!/usr/bin/env bash
# Release R2, the code + prose sets (P170 data, ~240k tokens each): the 2060 agent's driver, arm "dense" (the full prompt
# per item; the server caches the document), on the release bins (root %TEMP%\r-t5 from t5rel_gates.sh), 8 GB recipe,
# BONSAI_FAST_READ off vs on. Gate (#138): loss at most 1 item per set; no more than 1 wrong code where off is right.
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=docs/receipts/t5rel_r2b.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
K="$(cygpath -m $TEMP/r-t5/artifacts/api_key.txt)"
say "=== R2 code/prose: $("$TEMP/r-t5/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
for arm in "off|" "on|BONSAI_FAST_READ=1"; do
  NAME=${arm%%|*}; E=${arm#*|}
  for set in code prose; do
    stopall; sleep 4
    env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 $E powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/r-t5)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t5r2b_${NAME}_$set.launcher.log' -RedirectStandardError '$REPO\logs\t5r2b_${NAME}_$set.server.log'"
    ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
    say "server $NAME $set: health=$ok; $(grep '^fast' logs/t5r2b_${NAME}_$set.launcher.log | cut -c1-60)"
    PYTHONUTF8=1 python "$SP/p170/p170_drive.py" --set $set --arm dense --key-file "$K" --out "$(cygpath -m $B/docs/receipts)/t5rel_r2b_${NAME}_$set.jsonl" < /dev/null 2>&1 | tail -2 | cut -c1-200 | sed "s/^/R2 $NAME $set /" | tee -a "$LOG"
    say "  CUDA errors $(grep -c 'CUDA error' logs/t5r2b_${NAME}_$set.server.log)"
  done
done
stopall
say "=== R2 code/prose done"

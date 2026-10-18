#!/usr/bin/env bash
# R1 identity rerun (the first run's hashes were not kept: a grep fault): the release bins (r-t5) vs the bundle-20261017b
# zip bins (r-t5ref), the same launcher per root, env unset: 12 GB default and 8 GB preset; three greedy prompts.
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; FK=/c/Users/<user>/AppData/Local/Temp/claude/<session>/scratchpad
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=docs/receipts/t5rel_gates.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
for preset in 12gb 8gb; do E=""; [ $preset = 8gb ] && E="BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640"
  for side in r-t5ref r-t5; do
    stopall; sleep 4
    env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $E powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/$side)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t5r_id_${preset}_$side.launcher.log' -RedirectStandardError '$REPO\logs\t5r_id_${preset}_$side.server.log'"
    ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
    H=$(PYTHONUTF8=1 python "$FK/d27_hash.py" http://127.0.0.1:8080 "$(cygpath -m $TEMP/$side/artifacts/api_key.txt)" < /dev/null 2>&1 | tr '\n' ' ')
    say "R1 identity $preset ${side#r-}: health=$ok; $H; CUDA errors $(grep -c 'CUDA error' logs/t5r_id_${preset}_$side.server.log)"
  done
done
stopall

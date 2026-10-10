#!/usr/bin/env bash
# 12 GB recipe with the PR #13 engine: the current launcher (f16 mask) against the launcher that turns the packed KQ
# mask on and adds the 240 MiB it saves to the VRAM line. Decode and prefill at 131k and 180k (quick_tps).
#   bash bench/mask12_ab.sh <root f16-mask launcher> <root packed-mask launcher>   -> receipts/mask12_ab.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; LOG=receipts/mask12_ab.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force" >/dev/null 2>&1; sleep 4; }
for D in 131000 180000; do for arm in "f16|$1" "packed|$2"; do NAME=${arm%%|*}; ROOT="$(cygpath -w "${arm#*|}")"
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\mask12_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\mask12_$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME depth $D: health=$ok; $(grep '^kv' logs/mask12_$NAME.launcher.log | cut -c1-190)"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $D 2>&1 | tail -4 | tee -a "$LOG"
done; done
stop_srv; say "=== done"

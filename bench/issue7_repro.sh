#!/usr/bin/env bash
# Issue #7 (Milor123): decode at ~138k context with the VRAM line where a display-on-the-4070 box puts it.
# Arms: MTP on (launcher default 2 / 4 past the line) vs BONSAI_SPEC=0. Layer off; server on :8080.
#   bash bench/issue7_repro.sh [cells] [depth]   -> receipts/issue7_repro.log
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W)"; CELLS=${1:-95000}; DEPTH=${2:-138000}; LOG=receipts/${OUT:-issue7_repro}.log
stop_srv() { powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '$ROOT\bin\*'.Replace('/','\') } | Stop-Process -Force" >/dev/null 2>&1; sleep 4; }
for ARM in ${ARMS:-mtp nomtp}; do
  stop_srv; SPEC=""; [ $ARM = nomtp ] && SPEC=0
  env BONSAI_KV_VRAM_CELLS=$CELLS BONSAI_LAYER=0 BONSAI_SPEC=$SPEC \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$ROOT\logs\issue7_launcher_$ARM.log' -RedirectStandardError '$ROOT\logs\issue7_$ARM.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  echo "=== $(date '+%H:%M') arm $ARM cells $CELLS depth $DEPTH health=$ok" | tee -a $LOG
  grep -iE "kv-vram|line|spec|draft" logs/issue7_launcher_$ARM.log | head -6 | tee -a $LOG
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/${TOOL:-quick_tps}.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH ${TOOL_ARGS:-} 2>&1 | tee -a $LOG
  grep -E "draft acceptance" logs/issue7_$ARM.log | tail -4 | tee -a $LOG
  nvidia-smi --query-gpu=memory.used,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader | tee -a $LOG
done
stop_srv; echo "=== $(date '+%H:%M') done" | tee -a $LOG

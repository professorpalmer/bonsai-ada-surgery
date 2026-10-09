#!/usr/bin/env bash
# Issue #7 (2026-10-09): long session vs fresh server at the same context, past a pinned VRAM line (no difference:
# receipts/frag_ab.log). Served recipe
# (MTP + lookup, q8_0 tiered), layer off, VRAM line pinned at 16k so the session passes it quickly.
#   bash bench/frag_ab.sh [target]   -> receipts/frag_ab.log, receipts/frag_session.jsonl
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/frag_ab.log; TARGET=${1:-45000}
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
start_srv() { # NAME
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=16384 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\frag.$1.launcher.log' -RedirectStandardError '$REPO\\logs\\frag.$1.server.log'"
  local ok=0 i; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" >/dev/null 2>&1 || ok=0
  say "server $1: health=$ok; $(grep '^kv' logs/frag.$1.launcher.log)"
  [ $ok = 1 ]
}
start_srv long && PYTHONUTF8=1 python bench/frag_session.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --target $TARGET --tag long 2>&1 | tee -a "$LOG"
start_srv fresh && PYTHONUTF8=1 python bench/frag_session.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --replay-last --tag fresh 2>&1 | tee -a "$LOG"
stop_srv
say "=== done"

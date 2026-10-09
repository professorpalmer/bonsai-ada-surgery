#!/usr/bin/env bash
# Effective PCIe bandwidth of decode past the VRAM line: the same 100k context with the whole cache in VRAM and with
# the VRAM line pinned lower. MTP and lookup off (one token per step), layer off. Extra ms per token / tail bytes.
#   bash bench/tier_bw.sh name:cells ...   (cells empty = automatic line)  -> receipts/tier_bw.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/tier_bw.log; DEPTH=${DEPTH:-100000}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
for A in "$@"; do
  NAME=${A%%:*}; CELLS=${A#*:}
  stop_srv
  env BONSAI_LAYER=0 BONSAI_SPEC=0 BONSAI_LOOKUP=0 LLAMA_ARG_CHECKPOINT_EVERY_NT=8192 ${CELLS:+BONSAI_KV_VRAM_CELLS=$CELLS} powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\start-server.ps1' -RedirectStandardOutput '$REPO\logs\bw_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\bw_$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" >/dev/null 2>&1 || ok=0
  say "arm $NAME: health=$ok; $(grep '^kv' logs/bw_$NAME.launcher.log)"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH 2>&1 | tail -4 | tee -a "$LOG"
done
stop_srv; say "=== done"

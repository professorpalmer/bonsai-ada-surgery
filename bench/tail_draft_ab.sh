#!/usr/bin/env bash
# Draft size past the VRAM line (--spec-draft-n-max-tail, BONSAI_SPEC_DEEP): one arm per size, same server recipe,
# layer off, lookup_ab.py at DEPTH (default 160000). Mid-message checkpoints on (8192) so each arm reads the long
# prompt once.   bash bench/tail_draft_ab.sh 4 6 8   -> receipts/tail_draft_ab.jsonl, receipts/tail_draft_ab.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; OUT=receipts/tail_draft_ab.jsonl; LOG=receipts/tail_draft_ab.log; DEPTH=${DEPTH:-160000}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
for N in "$@"; do
  stop_srv
  env BONSAI_LAYER=0 BONSAI_SPEC_DEEP=$N LLAMA_ARG_CHECKPOINT_EVERY_NT=8192 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\start-server.ps1' -RedirectStandardOutput '$REPO\logs\tail_$N.launcher.log' -RedirectStandardError '$REPO\logs\tail_$N.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" >/dev/null 2>&1 || ok=0
  say "arm tail$N: health=$ok; $(grep '^spec' logs/tail_$N.launcher.log | cut -c1-80); $(grep '^kv' logs/tail_$N.launcher.log)"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "tail$N" --out $OUT --depth $DEPTH 2>&1 | tail -1 | tee -a "$LOG"
done
stop_srv; say "=== done"

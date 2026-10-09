#!/usr/bin/env bash
# PR #11 (patch 0046) on the 12 GB recipe: --checkpoint-every-nt N off (0) against 8192, same root, layer off.
# lookup_ab.py sends one long filler and changes only the end of that one user message, so without mid-message
# checkpoints each request is processed again from the start. Per arm: wall time, text hashes, checkpoints created
# and restored, and the server's system RAM (peak working set, private bytes).
#   bash bench/ckpt_ab.sh <root> name|N|depth ...   -> receipts/ckpt_every_nt_12gb.jsonl, receipts/ckpt_ab.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; ROOT="$(cygpath -w "${1:?root}")"; shift
OUT=receipts/ckpt_every_nt_12gb.jsonl; LOG=receipts/ckpt_ab.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
mem() { powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '$ROOT\\bin\\*' } | ForEach-Object { 'peak_ws_mib=' + [int](\$_.PeakWorkingSet64/1MB) + ' private_mib=' + [int](\$_.PrivateMemorySize64/1MB) }"; }
for A in "$@"; do
  IFS='|' read -r NAME N DEPTH <<< "$A"
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 LLAMA_ARG_CHECKPOINT_EVERY_NT="$N" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\ckpt_$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\ckpt_$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" >/dev/null 2>&1 || ok=0
  say "arm $NAME (checkpoint-every-nt $N, depth $DEPTH): health=$ok; $(grep '^kv' logs/ckpt_$NAME.launcher.log)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "$NAME" --out $OUT --depth "$DEPTH" 2>&1 | tail -2 | tee -a "$LOG"
  say "arm $NAME: $(mem); checkpoints created $(cat logs/ckpt_$NAME.*.log | grep -c 'created context checkpoint'), restored $(cat logs/ckpt_$NAME.*.log | grep -c 'restored context checkpoint')"
done
stop_srv
say "=== done"

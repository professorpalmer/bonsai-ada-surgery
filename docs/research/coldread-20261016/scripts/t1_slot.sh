#!/usr/bin/env bash
# T1-a (4070): slot save / restore with the tiered KV cache and the GDN / conv states (issue #138 track T1, first check).
# Recipe: the 8 GB-like decode path on the 4070 (bundle-20261016 bins ab94810051, q3_0, line pinned 80,640, layer off,
# sparse as the launcher decides), launcher = product start-server.ps1 + one test-only line that passes
# --slot-save-path (root %TEMP%\root-t1). Per depth (64k / 128k / 245k): server 1 cold request A, then save;
# server 2 (fresh) restore, then the same request B; at 64k and 245k server 3 (fresh) the same request with no restore
# (C, the determinism control). Request: 8 facts in the document, "list vaults 1-8", temp 0, thinking off, 96 tokens.
# Gates (declared before the run):
#   G1 save and restore return no error, and the server stays healthy.
#   G2 identity: B == A byte for byte, at every depth. Valid only where the control C == A (else: report, no verdict).
#   G3 no re-read: prompt_n of the request after restore <= 512 tokens.
#   G4 time: restore wall + B's prompt time <= 30 s at 245k (all depths reported), file size and save time reported.
# A pass on G1-G3 means the existing slot save / restore is a usable base for a persistent prefix cache; G4 sizes it.
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "$TEMP/root-t1")"
SP="$(cd "$(dirname "$0")" && pwd)"   # this scripts folder
SLOTW="$(cygpath -w "$TEMP/t1_slots")"; SLOTU="$TEMP/t1_slots"; mkdir -p "$SLOTU"
LOG=docs/receipts/t1_slot_restore.log; OUT=docs/receipts/t1_slot_restore.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
start() {   # $1 name
  local NAME=$1
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  local LL="$REPO\\logs\\t1_${NAME}.launcher.log" SL="$REPO\\logs\\t1_${NAME}.server.log"
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_CTK=q3_0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_SLOT_SAVE_PATH="$SLOTW" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$LL' -RedirectStandardError '$SL'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME: health=$ok; $(grep '^kv' logs/t1_${NAME}.launcher.log | head -1 | cut -c1-90)"
  [ $ok = 1 ]
}
run() { PYTHONUTF8=1 BONSAI_REPO=. python "$SP/t1_slot.py" --key-file artifacts/api_key.txt --slot-dir "$SLOTW" --out $OUT "$@" 2>&1 | tail -1 | cut -c1-400 | tee -a "$LOG"; }
say "=== T1-a start: root $ROOT, engine $("$TEMP/root-t1/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), free disk $(df -h /c | tail -1 | awk '{print $4}')"
for D in 65536 131072 245000; do
  F="t1_${D}.bin"
  start p$D && run --depth $D --phase prime --file $F
  start r$D && run --depth $D --phase restore --file $F
  case $D in 65536|245000) start c$D && run --depth $D --phase fresh --file $F ;; esac
  say "$D: health of the last server: $(curl -s -m 2 http://127.0.0.1:8080/health); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  rm -f "$SLOTU/$F"
done
say "=== T1-a done"

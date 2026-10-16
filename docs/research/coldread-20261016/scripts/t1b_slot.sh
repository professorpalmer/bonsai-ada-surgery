#!/usr/bin/env bash
# T1-b (4070): slot save / restore, then a request that CONTINUES the saved conversation (issue #138, track T1).
# T1-a showed restore works (~0.5 s per GB) but a repeat of the same request reads the whole prompt again: the GDN
# recurrent state cannot roll back past the saved end without a context checkpoint. A continuation needs no rollback.
# Same recipe and root as T1-a. Per depth (64k / 128k / 245k): server 1 request 1 (A), save, then request 2 = request 1
# + A as the assistant turn + a new question (D2, the in-memory continuation users get today); server 2 (fresh)
# restore, request 2 (B2); at 64k and 245k server 3 (fresh) request 2 with no restore (C2, full read, reported).
# Gates (declared before the run):
#   G1 save and restore return no error, the server stays healthy.
#   G2 identity: B2 == D2 byte for byte (restore gives the same answer as the in-memory continuation).
#   G3 no re-read: prompt_n of request 2 after restore <= 1,024 tokens (the new turn is ~150 tokens).
#   G4 time: restore wall + request 2 prompt time <= 30 s at 245k; all depths, file size and save time reported.
#   C2 vs B2 is reported, not gated (a full read and a cached continuation may split the work differently).
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "$TEMP/root-t1")"
SP="$(cd "$(dirname "$0")" && pwd)"   # this scripts folder
SLOTW="$(cygpath -w "$TEMP/t1_slots")"; SLOTU="$TEMP/t1_slots"; mkdir -p "$SLOTU"
LOG=docs/receipts/t1b_slot_continue.log; OUT=docs/receipts/t1b_slot_continue.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
start() {   # $1 name
  local NAME=$1
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  local LL="$REPO\\logs\\t1b_${NAME}.launcher.log" SL="$REPO\\logs\\t1b_${NAME}.server.log"
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_CTK=q3_0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_SLOT_SAVE_PATH="$SLOTW" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$LL' -RedirectStandardError '$SL'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME: health=$ok; $(grep '^kv' logs/t1b_${NAME}.launcher.log | head -1 | cut -c1-90)"
  [ $ok = 1 ]
}
run() { PYTHONUTF8=1 BONSAI_REPO=. python "$SP/t1b_slot.py" --key-file artifacts/api_key.txt --slot-dir "$SLOTW" --out $OUT --state "$SLOTW\t1b_state.json" "$@" 2>&1 | tail -1 | cut -c1-400 | tee -a "$LOG"; }
say "=== T1-b start: root $ROOT, engine $("$TEMP/root-t1/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), free disk $(df -h /c | tail -1 | awk '{print $4}')"
for D in 65536 131072 245000; do
  F="t1b_${D}.bin"
  start p$D && run --depth $D --phase prime --file $F
  start r$D && run --depth $D --phase restore --file $F
  case $D in 65536|245000) start c$D && run --depth $D --phase fresh --file $F ;; esac
  say "$D: health of the last server: $(curl -s -m 2 http://127.0.0.1:8080/health); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  rm -f "$SLOTU/$F"
done
say "=== T1-b done"

#!/usr/bin/env bash
# Side request at depth: one slot (the bundle's launcher) vs two slots on a unified KV cache with idle-slot caching
# off. 12 GB recipe, layer off, bench/side_request.py at DEPTH (default 120000).
#   [SIDE_ARMS='name|VAR=v VAR=v;...'] bash bench/side_ab.sh <root with BONSAI_SLOTS support>   -> receipts/side_ab.{log,jsonl}
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"
LOG=receipts/side_ab.log; OUT=receipts/side_ab.jsonl; DEPTH=${DEPTH:-120000}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4; }
IFS=";" read -ra ARMS <<< "${SIDE_ARMS:-np1|;np2|BONSAI_SLOTS=2 LLAMA_ARG_KV_UNIFIED=1 LLAMA_ARG_CACHE_IDLE_SLOTS=0 BONSAI_VRAM_MARGIN=1300}"
for A in "${ARMS[@]}"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\side_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\side_$NAME.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME ($ENVS): health=$ok; $(grep '^kv\|^ram' logs/side_$NAME.launcher.log | tr '\n' ' ' | cut -c1-170)"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/side_request.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH --tag $NAME 2>&1 | tee -a $OUT | tee -a "$LOG"
  say "$NAME slots line: $(sed 's/\x1b\[[0-9;]*m//g' logs/side_$NAME.server.log | grep -a -o 'n_slots = .*' | head -1)"
done
stop_srv
say "=== done"

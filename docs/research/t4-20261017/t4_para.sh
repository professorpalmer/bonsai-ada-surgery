#!/usr/bin/env bash
# T4 paraphrase gate (plan: #138 comment 6237281393, before the run): needle_paraphrase n24 at 245k, dense vs lexical
# fast read at the round-7 setting.
# 245k: cold TTFT, n24, copies n20.
# 4070, BONSAI_8GB=1, q3_0, line 80,640, layer off. Root %TEMP%\root-t4 (t4-fastread e8c090661). Restores the product
# server (layer :8080 + inner :18080, repo start-server.ps1, defaults) at the end.
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
SP="<scripts dir: this folder>"
LOG=docs/receipts/t4_paraphrase.log; OUT=docs/receipts/t4_paraphrase.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
restore_product() {
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\product_after_t4para.launcher.log' -RedirectStandardError '$REPO\\logs\\product_after_t4para.server.log'"
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "product server restored: health=$ok"
}
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; restore_product' EXIT
BASE="BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_CTK=q3_0"
FRA="LLAMA_FAST_READ=keep=16384,lex=100,lexonly=1,lexnb=16,lexdf=8,lexmin=1,lexn=4"
ROOT="$(cygpath -w "$TEMP/root-t4")"
start() {   # $1 name, rest env
  local NAME=$1; shift
  local SLOG="$REPO\\logs\\${NAME}.server.log" LLOG="$REPO\\logs\\${NAME}.launcher.log"
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  env BONSAI_MODEL="$MODEL" $BASE "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$LLOG' -RedirectStandardError '$SLOG'"
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME: health=$ok ($*); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  [ $ok = 1 ]
}
frline() { say "  fast read lines: $(grep -ac 'fast read:' logs/$1.server.log); last: $(grep -a 'fast read:' logs/$1.server.log | tail -1 | sed 's/.*fast read:/fast read:/')"; }
say "=== T4 paraphrase gate start: $(cat "$TEMP/root-t4/ENGINE.txt")"
PARA=bench/needle_paraphrase.py
for A in "dense|" "lex|$FRA"; do
  N=${A%%|*}; E=${A#*|}
  start t4p_$N $E || continue
  PYTHONUTF8=1 python "$PARA" --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 24 --tag t4p_${N}_245k --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG"
  frline t4p_$N
  python - "$OUT" "t4p_${N}_245k" <<'PY' | tee -a "$LOG"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8') if ('"%s"' % sys.argv[2]) in l and '"fact"' in l]
sym = {'ok': '+', 'miss': '-', 'wrong_other_fact': 'F', 'wrong': 'W'}
print(sys.argv[2] + ': ' + ''.join(sym[r['kind']] for r in rows) + '  (+ ok, - miss, F code of another fact, W other digits); mean wall %.1f s' % (sum(r['wall_s'] for r in rows)/max(1,len(rows))))
PY
done
say "=== T4 paraphrase gate done"

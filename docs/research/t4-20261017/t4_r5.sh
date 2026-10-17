#!/usr/bin/env bash
# T4 round 5 (plan: #138, before the run): lexical-only with a df cap and wide neighbors: keep 16384, lexdf 32, lexnb 16.
# 245k: cold TTFT, n24, copies n20.
# 4070, BONSAI_8GB=1, q3_0, line 80,640, layer off. Root %TEMP%\root-t4 (t4-fastread df34e3ae4). Restores the product
# server (layer :8080 + inner :18080, repo start-server.ps1, defaults) at the end.
cd /c/Users/<user>/Projects/bonsai-2-27b-serve || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
SP="<scripts dir: this folder>"
LOG=docs/receipts/t4_round5.log; OUT=docs/receipts/t4_round5.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
restore_product() {
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\product_after_t4r5.launcher.log' -RedirectStandardError '$REPO\\logs\\product_after_t4r5.server.log'"
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "product server restored: health=$ok"
}
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; restore_product' EXIT
BASE="BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=80640 BONSAI_CTK=q3_0"
FRA="LLAMA_FAST_READ=keep=16384,lex=100,lexonly=1,lexnb=16,lexdf=32"
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
say "=== T4 round 5 start: $(cat "$TEMP/root-t4/ENGINE.txt")"
classify() {   # $1 tag
  python - "$OUT" "$1" <<'PY' | tee -a "$LOG"
import json, re, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8') if ('"%s"' % sys.argv[2]) in l and '"want"' in l]
ok = [r for r in rows if r['ok']]
wrong = [r for r in rows if not r['ok'] and re.search(r'\d{4}', r['answer'])]
miss = [r for r in rows if not r['ok'] and not re.search(r'\d{4}', r['answer'])]
print(f"{sys.argv[2]}: correct {len(ok)}/{len(rows)}, wrong code {len(wrong)}, miss {len(miss)}; pattern " + ''.join('+' if r['ok'] else ('W' if r in wrong else '-') for r in rows))
for r in wrong:
    print(f"  WRONG vault {r['vault']} at {r['position_frac']}: want {r['want']}, got {r['answer']!r}")
PY
}
start t4r5_A_ttft $FRA && {
  PYTHONUTF8=1 python "$SP/t4_req.py" --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 64 --tag r5A_245k < /dev/null 2>&1 | tail -1 | tee -a "$LOG"
  frline t4r5_A_ttft; }
start t4r5_A_n24 $FRA && {
  PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 24 --tag t4r5_A_n24_245k --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG"
  frline t4r5_A_n24; classify t4r5_A_n24_245k; }
start t4r5_A_copies $FRA && {
  PYTHONUTF8=1 python bench/code_needle.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 20 --diff --tag t4r5_A_copies_245k --out $OUT < /dev/null 2>&1 | tail -1 | tee -a "$LOG"
  frline t4r5_A_copies; }
say "=== T4 round 5 done"

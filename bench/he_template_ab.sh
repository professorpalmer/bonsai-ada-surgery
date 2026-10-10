#!/usr/bin/env bash
# HumanEval 164 at medium, raw server (layer off), greedy, with a chat template file. Arms differ only in
# chat_template_kwargs, so the A/B isolates one template block (default: the third-party terse block, terse on/off).
#   bash bench/he_template_ab.sh <template file> [name]  -> artifacts/humaneval-<name>-{on,off}/, receipts/he_template_ab.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; TPLW="$(cygpath -w "$(realpath "${1:?template}")")"; NAME=${2:-terse}; LOG=receipts/he_template_ab.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
env BONSAI_LAYER=0 LLAMA_ARG_CHAT_TEMPLATE_FILE="$TPLW" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\start-server.ps1' -RedirectStandardOutput '$REPO\logs\hetpl.launcher.log' -RedirectStandardError '$REPO\logs\hetpl.server.log'"
ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
say "=== $NAME: template $(basename "$TPLW"), health=$ok"
[ $ok = 1 ] || exit 1
for A in 'on|{"terse": true}' 'off|{"terse": false}'; do
  ARM=${A%%|*}; KW=${A#*|}
  PYTHONUTF8=1 python bench/humaneval_run.py --arm medium --max-tokens 24576 --kwargs "$KW" --out "artifacts/humaneval-$NAME-$ARM" 2>&1 | tail -2 | tee -a "$LOG"
  python -c "import json;r=json.load(open('artifacts/humaneval-$NAME-$ARM/summary.json'))['rows'];t=sorted(x['completion_tokens'] for x in r);print('$NAME $ARM: mean tokens %.0f median %d' % (sum(t)/len(t), t[len(t)//2]))" | tee -a "$LOG"
done
say "=== $NAME done"

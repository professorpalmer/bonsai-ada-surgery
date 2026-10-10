#!/usr/bin/env bash
# Chat template A/B on tool use: the GGUF's own template vs a candidate template file (default: bonsai-sharp from a
# user, kept local in tmp/templates-sharp/, not committed). Raw server (layer off), product launcher defaults otherwise.
# Per arm: the suite's coding (12) + workspace (10) items (bench/plans/tools_template.json), then the tool-call syntax
# stress test. One server at a time; RAM guard on for the whole run.
#   bash bench/tool_template_ab.sh [template file]   -> receipts/tool_template_ab.log, artifacts/eval/tooltpl_<arm>/
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; TPL="${1:-tmp/templates-sharp/bonsai-sharp.jinja}"; TPLW="$(cygpath -w "$(realpath "$TPL")")"
LOG=receipts/tool_template_ab.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
say "=== tool template A/B: gguf template vs $(basename "$TPL")"
for A in "gguf|" "tpl|LLAMA_ARG_CHAT_TEMPLATE_FILE=$TPLW"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  env BONSAI_LAYER=0 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\tooltpl_$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\tooltpl_$NAME.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME: health=$ok"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python suite/run_suite.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --plan bench/plans/tools_template.json \
      --out artifacts/eval/tooltpl_$NAME --label-a $NAME 2>&1 | tail -12 | tee -a "$LOG"
  PYTHONUTF8=1 python bench/toolcall_stress.py --base http://127.0.0.1:8080 --key "$(cat artifacts/api_key.txt)" --n 6 \
      --out artifacts/eval/tooltpl_${NAME}_stress.json 2>&1 | tail -4 | tee -a "$LOG"
done
say "=== done"

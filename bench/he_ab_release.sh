#!/usr/bin/env bash
# Release gate: HumanEval 164 at medium on the raw server (layer off), product root vs a candidate root, greedy.
#   bash bench/he_ab_release.sh <name> <candidate root>   -> artifacts/humaneval-<name>-{old,new}/, receipts/he_ab_release.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; NAME=${1:?name}; CAND=${2:?candidate root}; LOG=receipts/he_ab_release.log
MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
for A in "old|$REPO" "new|$CAND"; do
  ARM=${A%%|*}; R=${A#*|}
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 3
  env BONSAI_LAYER=0 BONSAI_MODEL="$MODEL" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$R\start-server.ps1' -RedirectStandardOutput '$REPO\logs\heab_$ARM.launcher.log'"
  ok=0; for i in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "$NAME $ARM ($R): health=$ok"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/humaneval_run.py --arm medium --max-tokens 24576 --out "artifacts/humaneval-$NAME-$ARM" 2>&1 | tail -2 | tee -a "$LOG"
done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
say "=== $NAME done"

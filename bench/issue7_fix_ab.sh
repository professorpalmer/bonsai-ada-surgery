#!/usr/bin/env bash
# Issue #7, engine fixes against the 107-tool agent load: served recipe with the layer on, 107 varied tools (106.7k
# characters, as Pi sends), Pi's fields, about 64k tokens, server-default sampling and greedy. Arms are
# "name|root|VAR=v,VAR=v" (root "repo" = this repo; another root must have its own bin, layer and start-server.ps1).
#   bash bench/issue7_fix_ab.sh "base|repo|" "fix|C:/.../root-fix|" "fix-gate|C:/.../root-fix|LLAMA_SPEC_LOOKUP_GATE=1"
#   -> receipts/issue7_fix_ab.log, receipts/agent_depth.jsonl (tags i7f-<name>)
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/issue7_fix_ab.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
for A in "$@"; do
  IFS='|' read -r NAME ROOT VARS <<< "$A"
  [ "$ROOT" = repo ] && ROOT="$REPO"
  stop_srv
  ENVS=(BONSAI_MODEL="$MODEL"); IFS=',' read -ra VV <<< "$VARS"; for v in "${VV[@]}"; do [ -n "$v" ] && ENVS+=("$v"); done
  env "${ENVS[@]}" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\i7f-$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\i7f-$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" -Port 18080 >/dev/null 2>&1 || { say "arm $NAME: port 18080 is not served from $ROOT, stop"; ok=0; }
  say "arm $NAME ($ROOT; $VARS): health=$ok"
  [ $ok = 1 ] || continue
  PROBE_MANY_TOOLS=105 PROBE_TOOL_CHARS=976 PROBE_PI=1 PROBE_ARMS=server,greedy PYTHONUTF8=1 python bench/agent_depth_probe.py \
    --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 36000 --tag "i7f-$NAME" 2>&1 | tee -a "$LOG"
  PROBE_MANY_TOOLS=105 PROBE_TOOL_CHARS=976 PYTHONUTF8=1 python bench/toolcall_identity.py --base http://127.0.0.1:8080 \
    --key-file artifacts/api_key.txt --tag "i7f-$NAME" 2>&1 | tee -a "$LOG"
  grep -a "lookup gate" "logs/i7f-$NAME.server.log" | tail -1 | tee -a "$LOG"
done
stop_srv
say "=== done"

#!/usr/bin/env bash
# Issue #7: does lookup drafting slow an agent session? Milor's Pi session at 62k with 30 MCP tools: 37.8 tok/s, draft
# acceptance 0.378 (lookup on); yesterday, before lookup was the default: 45 tok/s at 0.49. Served recipe with the layer
# on (as Milor runs it), one arm with lookup (default) and one with BONSAI_LOOKUP=0; agent_depth_probe at 60k with 30
# MCP-like tools, thinking on, greedy and sampled.
#   bash bench/issue7_lookup_ab.sh   -> receipts/issue7_lookup_ab.log, receipts/agent_depth.jsonl (tags i7-lookup, i7-nolookup)
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/issue7_lookup_ab.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
for arm in "i7-lookup:" "i7-nolookup:BONSAI_LOOKUP=0"; do
  NAME=${arm%%:*}; VARS=${arm#*:}
  stop_srv
  env BONSAI_MODEL="$MODEL" $VARS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME ($VARS): health=$ok; $(grep '^spec' logs/$NAME.launcher.log | cut -c1-120)"
  [ $ok = 1 ] || continue
  PROBE_MANY_TOOLS=30 PROBE_ARMS=greedy,sampled PYTHONUTF8=1 python bench/agent_depth_probe.py --base http://127.0.0.1:8080 \
    --key-file artifacts/api_key.txt --depth 60000 --tag "$NAME" 2>&1 | tee -a "$LOG"
done
stop_srv
say "=== done"

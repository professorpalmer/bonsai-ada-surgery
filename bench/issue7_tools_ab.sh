#!/usr/bin/env bash
# Issue #7, second A/B: Milor's capture shows that Pi sends 107 tools (104k characters of tool definitions) and no
# sampler fields (so the server defaults apply: temperature 1.0, top_k 20). Lookup off gave him 45.9 tok/s at 0.53
# acceptance at 64k; lookup on gave 37.8 at 0.38 (another request). Our first A/B (30 short tools, temperature 0 and
# 0.6) showed no lookup cost. Here: served recipe with the layer on, lookup on and off; each arm sends
#   t107: 107 varied tools of the same total size (106.7k chars), Pi's fields, about 64k tokens in all,
#         server-default sampling and greedy;
#   t2:   2 tools, Pi's fields, about 64k tokens, server-default sampling (same depth without the tool list).
#   bash bench/issue7_tools_ab.sh   -> receipts/issue7_tools_ab.log, receipts/agent_depth.jsonl (tags i7b-*)
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/issue7_tools_ab.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
probe() { PYTHONUTF8=1 python bench/agent_depth_probe.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt "$@" 2>&1 | tee -a "$LOG"; }
for arm in "lookup:" "nolookup:BONSAI_LOOKUP=0"; do
  NAME=${arm%%:*}; VARS=${arm#*:}
  stop_srv
  env BONSAI_MODEL="$MODEL" $VARS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\i7b-$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\i7b-$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" -Port 18080 >/dev/null 2>&1 || { say "arm $NAME: port 18080 (llama-server behind the layer) is not served from this repo, stop"; ok=0; }
  say "arm $NAME ($VARS): health=$ok; $(grep '^spec' logs/i7b-$NAME.launcher.log | cut -c1-120)"
  [ $ok = 1 ] || continue
  PROBE_MANY_TOOLS=105 PROBE_TOOL_CHARS=976 PROBE_PI=1 PROBE_ARMS=server,greedy probe --depth 36000 --tag "i7b-t107-$NAME"
  PROBE_PI=1 PROBE_ARMS=server probe --depth 63000 --tag "i7b-t2-$NAME"
done
stop_srv
say "=== done"

#!/usr/bin/env bash
# Issue #7, real agent content: replay captured agent requests (logs/captured_requests.jsonl, an agent session with
# 27 tools, 47k characters of tool definitions and no sampler fields) with lookup on and off. Served recipe with the
# layer on. Each request is sent greedy (same text in both arms) and with the server's default sampling (as the
# client sent it). Also the first test of bench/capture_replay.py.
#   bash bench/issue7_replay_ab.sh   -> receipts/issue7_replay_ab.{log,jsonl}
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/issue7_replay_ab.log; OUT=receipts/issue7_replay_ab.jsonl
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
CAP=logs/captured_requests.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
for arm in "lookup:" "nolookup:BONSAI_LOOKUP=0"; do
  NAME=${arm%%:*}; VARS=${arm#*:}
  stop_srv
  env BONSAI_MODEL="$MODEL" $VARS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\i7r-$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\i7r-$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" -Port 18080 >/dev/null 2>&1 || { say "arm $NAME: port 18080 is not served from this repo, stop"; ok=0; }
  say "arm $NAME ($VARS): health=$ok"
  [ $ok = 1 ] || continue
  for idx in -1 -3 -5; do
    for mode in greedy server; do
      G=""; [ $mode = greedy ] && G="--greedy"
      PYTHONUTF8=1 python bench/capture_replay.py $CAP --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt \
        --index $idx $G --max-tokens 1500 --tag "i7r-$NAME-$mode" --out $OUT 2>&1 | tee -a "$LOG"
    done
  done
done
stop_srv
PYTHONUTF8=1 python - "$OUT" <<'PY' | tee -a "$LOG"
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
by = collections.defaultdict(dict)
for r in rows:
    _, arm, mode = r["tag"].split("-", 2)
    by[(r["index"], mode)][arm] = r
print("index mode    lookup on: tok/s acc   lookup off: tok/s acc   same text")
for (i, m), d in sorted(by.items()):
    a, b = d.get("lookup"), d.get("nolookup")
    if a and b:
        print(f"{i:5d} {m:7s} {a['decode_tps']:8.1f} {a.get('acceptance', 0):5.3f}   {b['decode_tps']:8.1f} {b.get('acceptance', 0):5.3f}   {a['output_sha'] == b['output_sha']}")
PY
say "=== done"

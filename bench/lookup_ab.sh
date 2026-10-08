#!/usr/bin/env bash
# H1: MTP alone vs MTP plus a lookup drafter, same launcher, layer off. -> receipts/lookup_ab.jsonl, logs/lookup_<arm>.*
#   bash bench/lookup_ab.sh [arms...]   arm = name:spec-type[:extra args with commas for spaces]
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W)"; OUT=receipts/lookup_ab.jsonl
ARMS=("$@"); [ ${#ARMS[@]} -eq 0 ] && ARMS=("mtp:draft-mtp" "mod+mtp:ngram-mod,draft-mtp" "simple+mtp:ngram-simple,draft-mtp")
stop_srv() { powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '*bonsai-2-27b-serve\bin\*' } | Stop-Process -Force" >/dev/null 2>&1; sleep 5; }
for A in "${ARMS[@]}"; do
  NAME=${A%%:*}; REST=${A#*:}; TYPE=${REST%%:*}; EXTRA=""; [ "$REST" != "$TYPE" ] && EXTRA=$(echo "${REST#*:}" | tr ',' ' ')
  stop_srv
  env BONSAI_LAYER=0 BONSAI_SPEC_TYPE="$TYPE" BONSAI_SPEC_ARGS="$EXTRA" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$ROOT\logs\lookup_$NAME.launcher.log' -RedirectStandardError '$ROOT\logs\lookup_$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  echo "=== $(date '+%H:%M') arm $NAME ($TYPE $EXTRA) health=$ok; $(grep '^spec' logs/lookup_$NAME.launcher.log)"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "$NAME" --out $OUT ${DEPTH:+--depth $DEPTH}
done
stop_srv; echo "=== $(date '+%H:%M') done"

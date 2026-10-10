#!/usr/bin/env bash
# Issue #16: server private bytes and working set right after load (no request), per launcher setting.
#   bash bench/ram_load.sh "name|VAR=v,VAR=v" ...   -> receipts/ram_load.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/ram_load.log
for A in "$@"; do
  IFS='|' read -r NAME VARS <<< "$A"
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 3
  ENVS=(BONSAI_LAYER=0); IFS=',' read -ra VV <<< "$VARS"; for v in "${VV[@]}"; do [ -n "$v" ] && ENVS+=("$v"); done
  env "${ENVS[@]}" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\ramload.$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\ramload.$NAME.server.log'"
  ok=0; for i in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  sleep 8
  m=$(powershell -NoProfile -Command "Get-Process llama-server | % { '{0} MiB private, {1} MiB working set' -f [int](\$_.PrivateMemorySize64/1MB), [int](\$_.WorkingSet64/1MB) }")
  echo "$(date '+%H:%M') $NAME ($VARS): health=$ok; $m; $(grep '^kv' logs/ramload.$NAME.launcher.log | cut -c1-110)" | tee -a "$LOG"
done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
echo "=== ram_load finished" >> "$LOG"

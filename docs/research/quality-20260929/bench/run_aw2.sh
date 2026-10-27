#!/usr/bin/env bash
# AW2: AppWorld test_normal, all 168 tasks, simplified_react_code_agent, raw Bonsai on this serve, one arm (b and c withdrawn, see below):
#   a) bonsai-raw      PTQ1_0, the product recipe as shipped (medium effort, budget 20480)  [server already up]
#   b) bonsai-raw-pq2  PQ2_0 (Prism's stock 2.13-bpw file), same product recipe            [server restarted]
#   c) bonsai-raw-max  PTQ1_0, thinking unrestricted, high effort, -n 131072 ("max thinking") [server restarted]
# Waits for E17 to finish first. Restores the product serve (start-server.ps1 + layer) at the end.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
ROOT="$USERPROFILE/Projects/bonsai-2-27b-serve"
BENCH="$ROOT/artifacts/quality-20260929/bench"
SCRIPTS="$ROOT/artifacts/experiments/spec-ab-20260928"
K=$(tr -d '\r\n' < "$ROOT/artifacts/api_key.txt")
export BONSAI_API_KEY="$K" OPENAI_API_KEY="$K"
VP="$TEMP/appworld-venv/Scripts/python.exe"
PQ2="$USERPROFILE\\Projects\\bonsai-2-27b-serve\\models\\donor\\Ternary-Bonsai-2-27B-PQ2_0.gguf"

until [ $(ls "$BENCH"/E17/*.json 2>/dev/null | wc -l) -ge 12 ]; do sleep 60; done
echo "== E17 complete, AW2 starts $(date +%H:%M)"

stop_all() {
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -match 'bonsai_layer' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }; Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 6"
}
wait_health() {  # $1 port
  powershell -NoProfile -Command "\$ok=\$false; for(\$i=0;\$i -lt 120;\$i++){ Start-Sleep 3; try { if((Invoke-RestMethod -Uri 'http://127.0.0.1:$1/health' -TimeoutSec 3).status -eq 'ok'){ \$ok=\$true; break } } catch {} }; \"health($1)=\$ok\"; \$k=(Get-Content '$ROOT/artifacts/api_key.txt' -Raw).Trim(); try { (Invoke-RestMethod -Uri 'http://127.0.0.1:$1/props' -Headers @{Authorization=\"Bearer \$k\"}).model_path } catch {}"
}
run_arm() {  # $1 model entry name
  cd "$TEMP/appworld-src"
  echo "== $1 run start $(date +%H:%M)"
  $VP -m appworld.cli run simplified_react_code_agent/bonsai_local/$1/test_normal 2>&1 | grep -v '^|\|^+\|^│\|^┌\|^└' | tail -4
  $VP -m appworld.cli evaluate simplified_react_code_agent/bonsai_local/$1/test_normal test_normal 2>&1 | grep -v '^|\|^+\|^│\|^┌\|^└' | tail -12
  echo "== $1 done $(date +%H:%M)"
}

# a) product recipe, PTQ1_0 (server as it stands)
run_arm bonsai-raw

# arms b) and c) withdrawn before any result (2026-10-03 21:58): the product recipe as shipped is the arm; the public figures are the comparison.

# restore the product serve
stop_all
powershell -NoProfile -Command "\$env:GGML_CUDA_BATCH_INVARIANT='1'; Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT/start-server.ps1') | Out-Null"
wait_health 8080
echo "== AW2 done, product serve restored $(date +%H:%M)"

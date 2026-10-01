cd C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/quality-20260929/bench
powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3; Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\experiments\spec-ab-20260928\run-teacher.ps1'); for(\$i=0;\$i -lt 120;\$i++){ Start-Sleep 3; try { if ((Invoke-RestMethod http://127.0.0.1:8080/health -TimeoutSec 3).status -eq 'ok') { 'teacher healthy'; break } } catch {} }"
PYTHONUTF8=1 python run_puzzles.py --plan C1-plan.json --out C1 >> C1.log 2>&1
echo "C1 finished $(date)"
powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3"
powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/experiments/spec-ab-20260928/switch.ps1 -Arm A 2>&1 | head -6
echo "A restored $(date)"

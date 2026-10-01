cd C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/quality-20260929/bench
echo "night2 start $(date)"
python C:/Users/pwall/Projects/bonsai-2-27b-serve/tooling/interpreter_proxy.py --port 8081 > proxy_e7.log 2>&1 &
sleep 5
PYTHONUTF8=1 python run_proxycheck.py --plan E7-plan.json --out E7 > E7.log 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -match 'interpreter_proxy' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"
echo "E7 done $(date)"
PYTHONUTF8=1 python agent_contract.py --plan E8-plan.json --out E8 > E8.log 2>&1
echo "E8 done $(date)"

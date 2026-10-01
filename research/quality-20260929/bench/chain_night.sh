cd C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/quality-20260929/bench
echo "night chain start $(date)"
python C:/Users/pwall/Projects/bonsai-2-27b-serve/tooling/interpreter_proxy.py --port 8081 > proxy_e5.log 2>&1 &
sleep 5
PYTHONUTF8=1 python run_proxycheck.py --plan E5-plan.json --out E5 > E5.log 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -match 'interpreter_proxy' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"
echo "E5 done $(date)"
PYTHONUTF8=1 python agent_contract.py --plan E6-plan.json --out E6 > E6.log 2>&1
echo "E6 done $(date)"

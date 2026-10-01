cd C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/quality-20260929/bench
until grep -q "A restored" chain_c1.log 2>/dev/null; do sleep 30; done
python C:/Users/pwall/Projects/bonsai-2-27b-serve/tooling/interpreter_proxy.py --port 8081 > proxy_e3.log 2>&1 &
sleep 5
PYTHONUTF8=1 python run_proxycheck.py --plan E3-plan.json --out E3 > E3.log 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -match 'interpreter_proxy' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"
echo "E3 done $(date)"

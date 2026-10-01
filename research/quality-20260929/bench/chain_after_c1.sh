cd C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/quality-20260929/bench
until [ $(grep -c '"arm"' C1.log 2>/dev/null || echo 0) -ge 7 ]; do sleep 60; done
echo "C1 done $(date)"
powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/experiments/spec-ab-20260928/switch.ps1 -Arm A 2>&1 | head -6
python C:/Users/pwall/Projects/bonsai-2-27b-serve/tooling/interpreter_proxy.py --port 8081 > proxy.log 2>&1 &
PROXY=$!
sleep 5
PYTHONUTF8=1 python proxy_smoke.py > proxy_smoke.json 2>&1; cat proxy_smoke.json
kill $PROXY 2>/dev/null
echo "E2 start $(date)"
PYTHONUTF8=1 python agent_contract.py --plan E2-plan.json --out E2 > E2.log 2>&1
echo "E2 done $(date)"

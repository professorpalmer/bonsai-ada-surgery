#!/usr/bin/env bash
# Issue #7: bench/cache_reuse_repro.py on the product server (12 GB recipe, layer off).
#   bash bench/cache_reuse_repro.sh [tag]   -> receipts/cache_reuse_repro.jsonl, logs/cache_reuse.*.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; TAG=${1:-product}
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
env BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\start-server.ps1' -RedirectStandardOutput '$REPO\logs\cache_reuse.launcher.log' -RedirectStandardError '$REPO\logs\cache_reuse.server.log'"
ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$REPO" >/dev/null 2>&1 || ok=0
echo "$(date '+%H:%M') health=$ok $(grep '^kv' logs/cache_reuse.launcher.log)"
[ $ok = 1 ] && PYTHONUTF8=1 python bench/cache_reuse_repro.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "$TAG"
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
echo "$(date '+%H:%M') === done"

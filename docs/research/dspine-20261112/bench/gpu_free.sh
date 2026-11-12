#!/usr/bin/env bash
# GPU-free check, run twice 2 minutes apart: no gpu.lock, no llama-server / test-backend-ops / python CUDA process.
# Exit 0 = free both times.
GPU_LOCK=${GPU_LOCK:?set GPU_LOCK to the shared lock file}
check() {
  [ -e "$GPU_LOCK" ] && { echo "lock: $(cat "$GPU_LOCK")"; return 1; }
  apps=$(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader | grep -i -E "llama-server|test-backend-ops|python" )
  [ -n "$apps" ] && { echo "apps: $apps"; return 1; }
  procs=$(powershell -NoProfile -Command "Get-Process llama-server,test-backend-ops -ErrorAction SilentlyContinue | ForEach-Object { \$_.Id }")
  [ -n "$procs" ] && { echo "procs: $procs"; return 1; }
  echo "free $(date +%H:%M:%S) $(nvidia-smi --query-gpu=memory.used,clocks.mem --format=csv,noheader)"
  return 0
}
check || exit 1
end=$(( $(date +%s) + 120 ))
until [ "$(date +%s)" -ge "$end" ]; do sleep 5; done
check || exit 1

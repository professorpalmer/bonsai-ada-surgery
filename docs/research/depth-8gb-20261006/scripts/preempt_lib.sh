# Sourced at the top of each filler_*.sh: a filler yields the GPU when a real job lands in queue/pending.
# The watcher checks every 20 s; on a pending job it stops the filler's children and the server, then the filler itself.
# The queue runner then logs the filler exit and runs the job (each job starts with its own stop.ps1).
__filler_pid=$$
(
  while sleep 20; do
    kill -0 $__filler_pid 2>/dev/null || exit 0
    if ls /c/bonsai/8gb/queue/pending/*.sh >/dev/null 2>&1; then
      echo "$(date '+%m-%d %T') filler $(basename "$0") preempted by $(basename "$(ls /c/bonsai/8gb/queue/pending/*.sh | sort | head -1)")" >> /c/bonsai/8gb/receipts/queue.log
      pkill -P $__filler_pid 2>/dev/null
      kill $__filler_pid 2>/dev/null
      powershell -NoProfile -ExecutionPolicy Bypass -File /c/bonsai/8gb/stop.ps1 >/dev/null 2>&1
      exit 0
    fi
  done
) &

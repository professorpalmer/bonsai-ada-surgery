#!/usr/bin/env bash
# After the dose ladder (queue e): stop queue e before its teacher batteries (by PID), run the S3b follow-up first
# (exact-copy probe at presence 1.5 with the presence penalty only inside the thinking, engine branch presence-think
# in %TEMP%\bin-presence), then the teacher batteries that queue e would have run.
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
# queue e logs "9B-base battery start" after its dose-ladder commit and push: stop it there (older runs of the same
# line are in the log, so count them first)
N0=$(grep -c "9B-base battery start" "$Q")
until [ "$(grep -c "9B-base battery start" "$Q")" -gt "$N0" ]; do sleep 10; done
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'queue_20261007e|queue_20261008f|battery_teacher' -and \$_.ProcessId -ne \$PID } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue; 'stopped ' + \$_.ProcessId + ' ' + \$_.Name }" | tee -a "$Q"
powershell -NoProfile -ExecutionPolicy Bypass -File ../bonsai-2-27b-serve/bench/stop_serve.ps1 >/dev/null 2>&1
step "queue g: presence inside the thinking only, probe (9B 4B 2B) start"
BONSAI_SMALL_BIN="$(cygpath -w "$TEMP/bin-presence")" bash bench/run_exact_copy_pt.sh 0 9B 4B 2B > logs/exact_copy_pt.run.log 2>&1
step "presence thinking-only probe exit $?"; commit "Exact-copy probe at presence 1.5, presence only inside the thinking (S3b follow-up)"
for S in 9B 4B 2B; do step "$S-base battery start"; MED_LIMIT=40 bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results (S2b)"; done
step "queue done"

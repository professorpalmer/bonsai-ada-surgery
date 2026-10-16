#!/usr/bin/env bash
# After queue g's thinking-only presence probe: stop queue g before its teacher batteries (by PID), run Plan G1b
# (example check live A/B on the 2B), then the teacher batteries.
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
N0=$(grep -c "9B-base battery start" "$Q")
until [ "$(grep -c "9B-base battery start" "$Q")" -gt "$N0" ]; do sleep 10; done
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'queue_20261008g|battery_teacher' -and \$_.ProcessId -ne \$PID } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue; 'stopped ' + \$_.ProcessId + ' ' + \$_.Name }" | tee -a "$Q"
step "queue h: G1b example check A/B (2B, through the layer) start"
bash bench/run_example_check_ab.sh 2B > logs/example_check_ab.run.log 2>&1
step "G1b exit $?"; commit "G1b: example check live A/B on the 2B (HumanEval medium through the layer)"
for S in 9B 4B 2B; do step "$S-base battery start (queue h)"; MED_LIMIT=40 bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results (S2b)"; done
step "queue done"

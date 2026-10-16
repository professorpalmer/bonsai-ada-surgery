#!/usr/bin/env bash
# Queue after the issue #7 pause (2026-10-07 15:50): teacher batteries 9B, 4B, 2B, then T1. One process, no
# background children; each stage commits. Progress: receipts/queue.log
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
for S in 9B 4B 2B; do step "$S-base battery start"; bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results"; done
step "queue done"
step "T1 start"; bash bench/run_t1.sh > logs/t1.run.log 2>&1; step "T1 exit $?"; commit "T1 results (test-first note, coding family)"

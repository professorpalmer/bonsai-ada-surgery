#!/usr/bin/env bash
# Small-model queue after the 2026-10-07 pause: 4B suite resume -> 2B battery -> teacher batteries 9B, 4B, 2B.
# One process, no background children; each stage commits its results. Progress: receipts/queue.log
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
step "4B suite resume start"; bash bench/suite_only.sh 4B PTQ1_0 > logs/suite_only_4B.run.log 2>&1; step "4B exit $?"; commit "4B battery results (suite resumed)"
step "2B battery start"; bash bench/battery.sh 2B PTQ1_0 > logs/battery_2B.run.log 2>&1; step "2B exit $?"; commit "2B battery results"
for S in 9B 4B 2B; do step "$S-base battery start"; bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results"; done
step "queue done"

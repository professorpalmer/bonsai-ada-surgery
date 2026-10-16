#!/usr/bin/env bash
# Plan S2b (DECISIONS 2026-10-07 19:20): exact-copy probe on six models, then teacher batteries with MED_LIMIT=40.
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
step "exact-copy probe start"; bash bench/run_exact_copy.sh 0 > logs/exact_copy.run.log 2>&1; step "exact-copy exit $?"; commit "Exact-copy edit probe: ternary 9B/4B/2B vs Q4_K_M teachers"
for S in 9B 4B 2B; do step "$S-base battery start"; MED_LIMIT=40 bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results (S2b)"; done
step "queue done"

#!/usr/bin/env bash
# Plan S3b arm (presence 1.5 on the probe, ternary 9B/4B/2B), then the teacher batteries (S2b). Started by
# bench/swap_to_e.sh when queue d logs "exact-copy exit".
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
step "issue7 121k repro start"; (cd ../bonsai-2-27b-serve && OUT=issue7_121k bash bench/issue7_repro.sh 121344 138000 > logs/issue7_121k.run.log 2>&1); step "issue7 121k repro exit $?"; (cd ../bonsai-2-27b-serve && git add receipts/issue7_121k.log && git commit -q -m "Issue #7: decode at 138k with a 121,344 VRAM line, MTP on/off" && git push -q origin main)
step "probe presence 1.5 start"; PROBE_PRESENCE=1.5 PROBE_TAG=exact_copy_pp bash bench/run_exact_copy_pp.sh 0 9B 4B 2B > logs/exact_copy_pp.run.log 2>&1; step "probe presence 1.5 exit $?"; commit "Exact-copy probe at presence 1.5 (S3b)"
step "dose ladder start"; bash bench/run_dose_ladder.sh 9B 4B 2B > logs/dose_ladder.run.log 2>&1; step "dose ladder exit $?"; commit "Dose ladder G1: HumanEval failures continued with R0-R3"
for S in 9B 4B 2B; do step "$S-base battery start"; MED_LIMIT=40 bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results (S2b)"; done
step "queue done"

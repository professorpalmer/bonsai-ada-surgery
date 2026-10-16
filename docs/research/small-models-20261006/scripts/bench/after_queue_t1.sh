#!/usr/bin/env bash
# Starts T1 once the 2026-10-07 queue writes its "queue done" line (no edits to the running queue script).
cd "$(dirname "$0")/.." || exit 1
until grep -q "queue done" receipts/queue.log 2>/dev/null; do sleep 120; done
bash bench/run_t1.sh > logs/t1.run.log 2>&1
git add -A results receipts && git commit -q -m "T1 results (test-first note, coding family)" && git push -q origin master

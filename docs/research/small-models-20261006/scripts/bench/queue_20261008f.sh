#!/usr/bin/env bash
# Resume after the night's 27B engine work (2026-10-08): the exact-copy probe's last two models (2B resumes from its
# results.jsonl, 2B-base new), the 27B lookup record at 250k on the 0041 engine (only when the repo bin is that engine),
# then queue e (issue #7 121k repro, presence 1.5 probe, dose ladder, teacher batteries).
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
B=../bonsai-2-27b-serve
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
until grep -q "=== chain11 done" $B/receipts/overnight_chain_20261008.log 2>/dev/null; do sleep 30; done
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
step "queue resumed after the 27B tier work (queue_20261008f.sh)"
step "exact-copy probe resume (2B, 2B-base) start"; bash bench/run_exact_copy.sh 0 2B 2B-base > logs/exact_copy_resume.run.log 2>&1; step "exact-copy resume exit $?"; commit "Exact-copy edit probe: 2B and 2B-base"
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
if "$B/bin/llama-server.exe" --version 2>&1 | grep -q "9f2b0fe"; then
  step "27B lookup record at 250k start"
  (cd $B && LOOKUP_KINDS=quote,plain DEPTH=250000 bash bench/lookup_ab.sh "d250-mtp:draft-mtp" "d250-mod+mtp-L32:ngram-mod,draft-mtp:--spec-lookup-n-max,32" > logs/lookup_d250.run.log 2>&1)
  step "27B lookup record at 250k exit $?"
else
  step "27B lookup record at 250k skipped: the repo bin is not the 0041 engine yet"
fi
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
bash bench/queue_20261007e.sh

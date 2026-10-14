#!/usr/bin/env bash
# Q07 (docs/research/q3port-20261013, gate written before the run): q3_0 vs q4_0 K/V with sparse on (12288 floor),
# root-q3-55 (q3-on-0055 7c7b47e156), line pinned 32768, graphs on, packed mask on. 200k (20 items), 245k (10 items).
cd "$(dirname "$0")/.." || exit 1
LOG=docs/receipts/q3port_checks.log
say() { echo "$(date '+%F %H:%M') $*" | tee -a "$LOG"; }
( cd /tmp/root-q3-55/bin && PATH="/c/Users/pwall/Projects/bonsai-2-27b-serve/bin:$PATH" ./test-backend-ops.exe perf -o MUL_MAT -b CUDA0 > /dev/null 2>&1 & ); sleep 4
say "=== Q07: q3_0 vs q4_0, sparse 12288 floor, root-q3-55 ($(cat /tmp/root-q3-55/ENGINE.txt)); memory clock under load $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader); driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
taskkill //IM test-backend-ops.exe //F > /dev/null 2>&1; sleep 2
for A in "200000 20 q4_0" "200000 20 q3_0" "245000 10 q4_0" "245000 10 q3_0"; do
  set -- $A; D=$1; N=$2; T=$3
  BONSAI_CTK=$T CN=$N DEPTH=$D SPARSE=12288,64,1024 GRAPHS=on PACKED=1 ARMS="sparse-decode" bash bench/sparse_prefill_n.sh /tmp/root-q3-55 > logs/q07_${D}_$T.run.log 2>&1
  K=$((N + 12))
  miss=$(tail -n $K docs/receipts/sparse_prefill.jsonl | grep '"ok": false' | sed -E 's/.*("fn": "[^"]+"|"vault": [0-9]+).*/\1/' | tr '\n' ';')
  say "Q07 $D $T: $(tail -n 30 docs/receipts/sparse_prefill.log | grep -E 'mean decode|correct' | tail -3 | tr '\n' ' ') misses: ${miss:-none}"
done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
say "=== Q07 done"

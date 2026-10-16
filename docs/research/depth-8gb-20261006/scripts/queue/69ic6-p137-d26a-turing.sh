#!/usr/bin/env bash
# P137 (#21, D26a on Turing): is sparse's 64k cost on the 2060 the line, or engine overhead? The 4070's D26a (PCIe 4.0):
# overhead 0, line cost 2.6 %. On the 2060 (PCIe 3.0) P123 / P127 gave 7-8 % that did not scale with the cells.
# RC bin-rc55 (4de618549) + launcher #49 3035572 test copy, 64k, graphs on, packed on, lookup on; three arms alternated x2:
#   off_short: sparse off, line pinned to the sparse line (BONSAI_KV_VRAM_CELLS=52224);
#   on_short:  BONSAI_SPARSE=1 (line 52,224 from the launcher; MIN_HOST 32768 -> 0 sparse ops at 64k);
#   off_long:  default (sparse off, line ~61.7k).
# Reading (declared before the run): on_short vs off_short = engine overhead; off_long vs off_short = the line cost.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p137; mkdir -p $R
[ -f /c/bonsai/bonsai-ada-surgery/bin-rc55/llama-server.exe ] || { echo "no bin-rc55" > $R/summary.txt; exit 1; }
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
L='C:/bonsai/bonsai-ada-surgery/start-server-rc55.ps1'
V="BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/bin-rc55;BONSAI_LAYER=0"
for r in 1 2; do
  bash run_arm.sh $R off_short_r$r "$V;BONSAI_KV_VRAM_CELLS=52224" "$L" "64000"
  bash run_arm.sh $R on_short_r$r "$V;BONSAI_SPARSE=1" "$L" "64000"
  bash run_arm.sh $R off_long_r$r "$V" "$L" "64000"
done
{ for a in off_short_r1 on_short_r1 off_long_r1 off_short_r2 on_short_r2 off_long_r2; do f=$R/$a.txt; E=$(ls -t logs/*-$a.err.log | head -1); O="${E%err.log}out.log"
    echo "== $a: $(grep -c '(1 tok)' $f) one-token; sparse lines $(grep -c ggml_cuda_fa_sparse_mask "$E"); $(grep -hE '^kv +tiered' "$O" | cut -c1-60)"; grep -E "mean decode|did not" $f; done; } > $R/summary.txt

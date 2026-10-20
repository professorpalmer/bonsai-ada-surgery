#!/usr/bin/env bash
# P223 (post-zip check of bundle-20261019c on the 2060): the zip with no env vars must give draft 1 below the VRAM line and 2 past
# it (the P222 d12 arm). Bins = 19b (0 bytes differ), so only the launcher default changes. quick_tps at 4k and 128k, a fresh
# server per depth. Gate (declared before the run): spec line "draft 1 (2 past the VRAM line)", 0 CUDA errors, and mean decode
# within 2 % of P222 d12 (52.4 at 4k, 29.6 at 128k).
cd /c/bonsai/8gb; R=receipts/p223; mkdir -p $R
L=$(cygpath -w /c/bonsai/serve-1019c/start-server.ps1)
for d in 4000 128000; do
  bash run_arm.sh $R c19_d$d "" "$L" "$d" > /dev/null 2>&1
  echo "c19 d$d: $(grep 'mean decode' $R/c19_d$d.txt); $(grep -hE '^spec' $(ls -t logs/*c19_d$d*.out.log | head -1) | cut -c1-60)" >> $R/run.txt
done
echo "CUDA error logs: $(find logs -name '*.err.log' -newer $R -print0 | xargs -0 grep -l 'CUDA error' 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt

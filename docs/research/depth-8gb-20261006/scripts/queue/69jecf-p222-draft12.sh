#!/usr/bin/env bash
# P222 (P221: the bundle-20261019b default replay + 2 / 2 is -3.3 % at 4k and -3.7 % at 64k in-block vs 1 / 1, while 128k gains
# ~+30 %; P215's deep gain came from SPEC_DEEP = 2): test replay + draft 1 below the VRAM line / 2 past it (BONSAI_SPEC=1,
# BONSAI_SPEC_DEEP=2) on the same zip and launcher, quick_tps, a fresh server per depth and arm, in one block: d12 vs def (2 / 2)
# vs old (BONSAI_RS_REPLAY=0, 1 / 1) at 4k, 64k and 128k. Gate (declared before the run): d12 within 1 % of old at 4k and 64k,
# and within 3 % of def at 128k -> propose d12 as the 8 GB default.
cd /c/bonsai/8gb; R=receipts/p222; mkdir -p $R
L=$(cygpath -w release_1019b/x/start-server.ps1)
for d in 4000 64000 128000; do
  for arm in d12 def old; do
    case $arm in d12) V="BONSAI_SPEC=1;BONSAI_SPEC_DEEP=2";; def) V="";; old) V="BONSAI_RS_REPLAY=0";; esac
    bash run_arm.sh $R ${arm}_d$d "$V" "$L" "$d" > /dev/null 2>&1
    echo "$arm d$d: $(grep 'mean decode' $R/${arm}_d$d.txt); $(grep -hE '^spec' $(ls -t logs/*${arm}_d$d*.out.log | head -1) | cut -c1-60)" >> $R/run.txt
  done
done
echo "CUDA error logs: $(find logs -name '*.err.log' -newer $R -print0 | xargs -0 grep -l 'CUDA error' 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt

#!/usr/bin/env bash
# P221 (P220's sweep vs the cards' old 1 / 1 numbers: 4k -3.2 %, 64k -5.1 %, but those are other days / bundles): an in-block A/B
# on the same bundle-20261019b zip and launcher, quick_tps, a fresh server per depth and arm, twice each in ABAB order:
# def = the new default (replay + 2 / 2) vs old = BONSAI_RS_REPLAY=0 (1 / 1), at 4k and 64k. Reported: mean decode per arm and
# depth, the spread between the two repeats; the R6 speed gate (no depth slower by more than 3 %) is read from this in-block A/B.
cd /c/bonsai/8gb; R=receipts/p221; mkdir -p $R
L=$(cygpath -w release_1019b/x/start-server.ps1)
for d in 4000 64000; do
  for rep in 1 2; do
    for arm in def old; do
      V=""; [ $arm = old ] && V="BONSAI_RS_REPLAY=0"
      bash run_arm.sh $R ${arm}_d${d}_r$rep "$V" "$L" "$d" > /dev/null 2>&1
      echo "$arm d$d r$rep: $(grep 'mean decode' $R/${arm}_d${d}_r$rep.txt)" >> $R/run.txt
    done
  done
done
echo "$(date +%T) done" >> $R/run.txt

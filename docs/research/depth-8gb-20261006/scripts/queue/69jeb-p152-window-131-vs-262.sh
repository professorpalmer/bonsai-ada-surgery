#!/usr/bin/env bash
# P152 (Cary 2026-10-16: "the card says set 131k"): is the 262k window free below 128k? bundle-20261016 zip bins + P150 launcher copy,
# q3_0 default, BONSAI_CTX=131072 vs the default 262144, alternated x2, one server each, extend sweep 4k / 64k / 96k / 128k.
# Rule (declared before the run): if 262k is within 2 % of 131k at every depth, the card and docs can say "the full window costs
# nothing up to 128k; only filling it is slow". Otherwise report the gap per depth and the two VRAM lines.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p152; mkdir -p $R
[ -d release_1016/x ] || { echo "no release_1016/x (P150 extracts it)" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-1016test.ps1'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"; D="4000 64000 96000 128000"
arm() { bash run_arm.sh $R $1 "$2" "$L" "$D"; O=$(ls -t logs/*-$1.out.log | head -1); grep -hE "^(window|kv) " "$O" > $R/$1.launcher.txt; }
arm c131_r1 "$V;BONSAI_CTX=131072"; arm c262_r1 "$V"; arm c131_r2 "$V;BONSAI_CTX=131072"; arm c262_r2 "$V"
{ for a in c131_r1 c262_r1 c131_r2 c262_r2; do echo "== $a: $(grep -c '(1 tok)' $R/$a.txt) one-token"; cat $R/$a.launcher.txt; grep -E "^code|mean decode|did not|min free" $R/$a.txt; done; } > $R/summary.txt

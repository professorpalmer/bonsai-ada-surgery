#!/usr/bin/env bash
source /c/bonsai/8gb/preempt_lib.sh   # yield the GPU to queued jobs
# Default sweep A: the shipped 8 GB preset (newest engine, lookup as main sets it) at 4k..126k, both modes.
cd /c/bonsai/8gb; D=receipts/filler/deep_$(date +%m%d_%H%M); mkdir -p $D
L='C:/bonsai/bonsai-ada-surgery/start-server-262test.ps1'; B=$(cat receipts/newest_bin 2>/dev/null || echo bin-lookup)
bash run_arm.sh $D drafting "BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/$B;BONSAI_LAYER=0" "$L" "4000 32000 64000 96000 126000"
[ -n "$(ls /c/bonsai/8gb/queue/pending 2>/dev/null)" ] && { echo "yield to queue" > $D/yield.txt; exit 0; }
bash run_arm.sh $D long "BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/$B;BONSAI_LAYER=0;BONSAI_MODEL=Ternary-Bonsai-2-27B-PTQ1_0.gguf" "$L" "4000 32000 64000 96000 126000"

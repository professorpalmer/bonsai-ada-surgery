#!/usr/bin/env bash
# Ada data for PrismML #330 (GGML_CUDA_FA_PREFILL_F16): the attention kernel at a served shape (head 256, 4 KV heads
# x 6, 512 queries, KV 4k-128k, q8_0 against f16; test-backend-ops perf cases from the 0040 build), then a serving A/B
# on the 12 GB recipe with the switch off and on, one 100k prompt (below the VRAM line).
#   bash bench/fa_prefill_f16_ada.sh   -> receipts/fa_prefill_f16_ada.log
cd "$(dirname "$0")/.." || exit 1
LOG=receipts/fa_prefill_f16_ada.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
WBIN="$(cygpath -w "$TEMP/build-0040/bin")"
say "=== FLASH_ATTN_EXT perf, RTX 4070, served prefill shape, q8_0 vs f16 (test-backend-ops, $WBIN)"
powershell -NoProfile -Command "\$cu='C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13'; \$env:PATH='$WBIN;'+\$cu+'\bin;'+\$cu+'\bin\x86_64;'+\$env:PATH; Set-Location '$WBIN'; & .\test-backend-ops.exe perf -o FLASH_ATTN_EXT -b CUDA0 2>&1 | Out-String" \
  | grep "hsk=256" | grep "nb=512" | grep "nh=4" | grep -E "type_K=(q8_0|f16)" \
  | sed -E 's/.*type_K=([a-z0-9_]+).*kv=([0-9]+).* ([0-9.]+) us\/run.*/\1 kv=\2 \3 us\/run/' | tee -a "$LOG"
say "=== serving A/B, GGML_CUDA_FA_PREFILL_F16 off / 131072, one 100k prompt"
bash bench/tier_ab.sh 100000 "f16off|repo|GGML_CUDA_FA_PREFILL_F16=0" "f16on|repo|GGML_CUDA_FA_PREFILL_F16=131072" 2>&1 \
  | grep -E "arm |depth|identical|decode mean|===" | tee -a "$LOG"
say "=== done"

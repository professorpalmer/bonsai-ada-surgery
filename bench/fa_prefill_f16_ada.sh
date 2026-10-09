#!/usr/bin/env bash
# Ada data for PrismML #330 (GGML_CUDA_FA_PREFILL_F16): the attention kernel at a served shape (head 256, 4 KV heads
# x 6, 512 queries, KV 4k-128k, q8_0 against f16; test-backend-ops perf cases from the 0040 build), then a serving A/B
# with the switch off and on: all-VRAM cache (64k window, so the pool has room for the f16 copy), one 60k prompt.
# (With the 12 GB tiered recipe the cache fills VRAM to the launcher's margin, and the enabled switch stopped the server
# when its pool grew at 8k: cuMemSetAccess failed. receipts/fa_prefill_f16_ada.log, 10:21.)
#   bash bench/fa_prefill_f16_ada.sh   -> receipts/fa_prefill_f16_ada.log
cd "$(dirname "$0")/.." || exit 1
LOG=receipts/fa_prefill_f16_ada.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
CU=/c/Users/pwall/AppData/Local/Programs/Python/Python312/Lib/site-packages/nvidia/cu13
BIN="$TEMP/build-0040/bin"
say "=== FLASH_ATTN_EXT perf, RTX 4070, served prefill shape (head 256, 4 KV heads x 6, 512 queries), q8_0 vs f16"
(cd "$BIN" && PATH="$BIN:$CU/bin:$CU/bin/x86_64:$PATH" ./test-backend-ops.exe perf -o FLASH_ATTN_EXT -b CUDA0 2>&1) > "$TEMP/fa_perf_ada.txt"
PYTHONUTF8=1 python - "$TEMP/fa_perf_ada.txt" <<'PY' | tee -a "$LOG"
import re, sys
rows = {}
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    if "hsk=256" not in l or "nb=512" not in l or "nh=4," not in l:
        continue
    t = re.search(r"type_K=(\w+)", l); kv = re.search(r"kv=(\d+)", l); us = re.search(r"([\d.]+) us/run", l)
    if t and kv and us and t.group(1) in ("q8_0", "f16"):
        rows[(int(kv.group(1)), t.group(1))] = float(us.group(1))
print("kv       q8_0 us/run   f16 us/run   f16 vs q8_0")
for kv in sorted({k for k, _ in rows}):
    q, f = rows.get((kv, "q8_0")), rows.get((kv, "f16"))
    if q and f:
        print(f"{kv:6d}   {q:11.0f}   {f:10.0f}   {100 * (q / f - 1):+5.1f}% faster")
PY
say "=== serving A/B, all-VRAM cache (64k window), GGML_CUDA_FA_PREFILL_F16 off / 65536, one 60k prompt"
bash bench/tier_ab.sh 60000 "f16off-64k|repo|BONSAI_TIER=0,BONSAI_CTX=65536,GGML_CUDA_FA_PREFILL_F16=0" "f16on-64k|repo|BONSAI_TIER=0,BONSAI_CTX=65536,GGML_CUDA_FA_PREFILL_F16=65536" 2>&1 \
  | grep -E "arm |depth|identical|decode mean|===" | tee -a "$LOG"
say "=== done"

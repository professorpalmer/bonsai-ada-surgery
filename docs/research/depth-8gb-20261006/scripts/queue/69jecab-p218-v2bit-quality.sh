#!/usr/bin/env bash
# P218 (after P216: a full 2-bit KV fails G1, uniform +1.83 % at 64k): V-only 2-bit. bins = kv-fake2v (P216's bins + the V-only
# switch: the fake levels on V cache rows only, K real q4_0). llama-perplexity wikitext-2, as P216 (64k window, 2 chunks; then 16k
# all chunks), the same pinned line. Arms: v2 = V 2-bit uniform, rot on; v3 = V 3-bit uniform, rot on (a control near q3_0).
# Gate G1 (declared before the run): v2 within +1.0 % of P216's q3_0 64k PPL (7.2098). A pass is worth ~-14 % KV bytes
# (K 3.5 + V ~2.5 bits) and would need a mixed K/V FA path.
cd /c/bonsai/8gb; R=receipts/p218; mkdir -p $R
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
P=/c/bonsai/bonsai-ada-surgery/bin-fake2v/llama-perplexity.exe
M=C:/bonsai/bonsai-ada-surgery/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf
F=C:/bonsai/bonsai-ada-surgery/artifacts/eval/wiki.test.raw
for ctx in 65536 16384; do
  CH=""; [ $ctx = 65536 ] && CH="--chunks 2"
  for arm in v2 v3; do
    FB=${arm:1:1}
    env GGML_CUDA_KV_FAKE_BITS=$FB GGML_CUDA_KV_FAKE_V_ONLY=1 GGML_CUDA_FA_PREFILL_F16=32768 GGML_CUDA_FA_CHUNK=32768 \
      $P -m $M -f $F -c $ctx -b 2048 -ub 512 $CH -ngl 99 -fa on -ctk q4_0 -ctv q4_0 --kv-vram-cells 45056 < /dev/null > $R/c${ctx}_$arm.log 2>&1
    echo "ctx $ctx $arm: $(grep -oE 'Final estimate: PPL = [0-9.]+ \+/- [0-9.]+' $R/c${ctx}_$arm.log)" >> $R/summary.txt
  done
done
grep -hiE "cuda error|failed" $R/*.log | grep -v "fit params" | head -5 >> $R/summary.txt
echo "$(date +%T) done" >> $R/summary.txt

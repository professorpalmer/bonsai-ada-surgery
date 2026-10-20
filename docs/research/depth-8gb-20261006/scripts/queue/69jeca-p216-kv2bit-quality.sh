#!/usr/bin/env bash
# P216 (research pass 2, nugget "KV below 3 bits" (TurboQuant / KIVI); the quality probe first): does a 2-bit KV keep quality
# once K/V are rotated (attn-rot, on for every quantized K/V type with head dim % 64 = 0) and the levels are Lloyd-Max?
# bins = fork kv-fake2 c05e7bb89 (product-0069 + 0070 + the P100 hook 4d1c8abe0 + mode 20), 75-real. q4_0 K/V storage as the
# container (the hook writes only 2^b levels); llama-perplexity on wikitext-2 test, as P100: a 16k window (all chunks) and a
# 64k window (2 chunks), the same pinned KV line in every arm.
# Arms: q3 = real q3_0 (the shipped type); b0 = real q4_0; b2 = 2-bit uniform, rot on; b20 = 2-bit Lloyd-Max, rot on;
# b2nr = 2-bit uniform, LLAMA_ATTN_ROT_DISABLE=1 (P100's setting: 16k +3.64 %, 64k +1.86 % vs 4-bit).
# Gate G1 (declared before the run, from the research note): a 2-bit arm passes if its 64k PPL is within +1.0 % of q3 (and
# report 16k). A pass sends that arm to G2 (needles + copies at 160k, item by item vs q3) in a later run.
cd /c/bonsai/8gb; R=receipts/p216; mkdir -p $R
for i in $(seq 1 360); do grep -q "fake2 exit" receipts/build_ahead.log && break; sleep 10; done
grep -q "fake2 exit 0" receipts/build_ahead.log || { echo "$(date +%T) bin-fake2 build missing: stop" >> $R/summary.txt; exit 1; }
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
P=/c/bonsai/bonsai-ada-surgery/bin-fake2/llama-perplexity.exe
M=C:/bonsai/bonsai-ada-surgery/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf
F=C:/bonsai/bonsai-ada-surgery/artifacts/eval/wiki.test.raw
for ctx in 65536 16384; do
  CH=""; [ $ctx = 65536 ] && CH="--chunks 2"
  for arm in q3 b0 b20 b2 b2nr; do
    T=q4_0; FB=0; ROT=""
    case $arm in q3) T=q3_0;; b0) ;; b20) FB=20;; b2) FB=2;; b2nr) FB=2; ROT=1;; esac
    env GGML_CUDA_KV_FAKE_BITS=$FB ${ROT:+LLAMA_ATTN_ROT_DISABLE=1} GGML_CUDA_FA_PREFILL_F16=32768 GGML_CUDA_FA_CHUNK=32768 \
      $P -m $M -f $F -c $ctx -b 2048 -ub 512 $CH -ngl 99 -fa on -ctk $T -ctv $T --kv-vram-cells 45056 < /dev/null > $R/c${ctx}_$arm.log 2>&1
    echo "ctx $ctx $arm: $(grep -oE 'Final estimate: PPL = [0-9.]+ \+/- [0-9.]+' $R/c${ctx}_$arm.log); rot $(grep -oE 'attn_rot_k = [01]' $R/c${ctx}_$arm.log | head -1)" >> $R/summary.txt
  done
done
grep -hiE "cuda error|failed" $R/*.log | grep -v "fit params" | head -5 >> $R/summary.txt
python - "$(cygpath -w $R/summary.txt)" >> $R/summary.txt <<'PY'
import re, sys
v = {}
for l in open(sys.argv[1]):
    m = re.match(r'ctx (\d+) (\w+): Final estimate: PPL = ([0-9.]+)', l)
    if m: v[(m.group(1), m.group(2))] = float(m.group(3))
for ctx in ('65536', '16384'):
    q3 = v.get((ctx, 'q3'))
    for arm in ('b0', 'b20', 'b2', 'b2nr'):
        if q3 and (ctx, arm) in v:
            d = 100 * (v[(ctx, arm)] / q3 - 1)
            print('ctx', ctx, arm, 'vs q3: %+.2f %%' % d, ('G1 PASS' if d <= 1.0 else 'G1 FAIL') if ctx == '65536' and arm != 'b0' else '')
PY
echo "$(date +%T) done" >> $R/summary.txt

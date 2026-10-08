# Int8 score step for prefill attention (plan, 2026-10-08)

Idea credit: syv-ai/HyperQwen, which uses an int8-QK prefill attention kernel for this exact attention shape
(24 query heads, 4 KV heads, head size 256) on vLLM. This note is our route to the same result in this engine.

## The result we want

Prefill at 130k context goes from about 349 tok/s to 550 tok/s or more on the RTX 4070, on Bonsai 2 27B and on
Mirai S, with no measurable quality change (KL by position against today's kernel, HumanEval and the suite paired).

## Why the gain is there

1. **Attention is most of the prefill cost at depth.** One 159k prefill (`receipts/prefill_depth_fit.txt`) fits
   0.509 ms + 0.0181 ms per 1k of depth for each prefill token. The depth term is 53% of the cost at 32k, 82% at
   130k and 85% at 158k.
2. **The score step is the slow half of attention.** In `fattn-mma-f16.cuh`, the score step (K times Q) uses fp16
   inputs with an fp32 accumulator (`T_C_KQ = tile<..., float>`). On GeForce Ada cards that mode runs at half the
   fp16 rate (RTX 4070: about 58 dense TFLOPS against 117 with fp16 accumulation). The value step accumulates in fp16
   (`T_C_VKQ = tile<..., half2>`), at the full rate. With equal FLOPs in both steps, the score step is about two
   thirds of the attention MMA time.
3. **Int8 with int32 accumulation is 4 times the current score-step rate** (about 234 dense TOPS on the RTX 4070).
4. **The K cache is already int8.** The served recipe stores K as q8_0: 32 int8 values and one fp16 scale for each
   block. Today the tile loader converts each K tile to fp16 in shared memory. An int8 score step reads K as it is
   stored, which also removes that conversion.

If the score step runs 4 times faster and the value step stays as it is, attention takes about
2/3 / 4 + 1/3 = 0.5 of its time today. At 130k: 0.509 + 0.5 x 2.357 = 1.69 ms per token, about 590 tok/s.

## Measured kernel baseline (2026-10-08)

`test-backend-ops perf -o FLASH_ATTN_EXT`, served prefill shape (head 256, 4 KV heads x 6, q8_0 K/V, 512 queries),
sm_89 build of `008ac1112`, before any change:

| KV length | Kernel time per layer and 512-token batch | TFLOPS |
| --- | ---: | ---: |
| 4k | 1.27 ms | 40.7 |
| 32k | 11.0 ms | 37.3 |
| 64k | 22.5 ms | 36.7 |
| 128k | 45.4 ms | 36.4 |

With 16 attention layers, the kernel costs about 1.42 ms per prefill token at 128k, about half of the 2.87 ms total.
So the depth term of the fit includes more than this kernel. Correction to the estimate above: if the int8 score
step makes the kernel twice as fast (the combined MMA peak goes from about 78 to about 156 TFLOPS), prefill at 130k
goes from about 349 to about 460 tok/s, about +33%. The gate (+25% at 128k) stays.

## Route

1. **Measure first.** Run `test-backend-ops -o FLASH_ATTN_EXT` in performance mode for the served shapes (head 256,
   GQA 6, q8_0 K/V, 512 queries, KV 32k / 64k / 128k) to get the kernel time today and the split between the score
   step and the value step (`GGML_CUDA_OP_TIMING`, CUDA graphs off).
2. **Q to int8.** When the kernel loads Q into shared memory, quantize it in blocks of 32 along the head dimension
   (int8 values and one float scale for each block: the q8_1 method that the matrix code uses for activations).
   Q is loaded once for each block of queries, so this cost is small.
3. **K tiles as int8.** A q8_0 loader that copies the int8 values and the scales into shared memory without the fp16
   conversion.
4. **The score step on `mma.sync m16n8k32 s8.s8.s32`** (already in `mma.cuh`). For each block of 32 along the head
   dimension: an int32 tile, converted to float and multiplied by (scale of the K row) x (scale of the Q column),
   then added to the float `KQ_C`. This is the arithmetic of `vec_dot_q8_0_q8_1_mma` in the matrix code.
5. **Everything after the score step stays the same:** softcap, mask, the running maximum, exp, the row sums and the
   value step.
6. **Scope:** q8_0 K, head size 256, prefill-sized batches (the path that the 12 GB recipe takes). Decode keeps
   today's kernel. A switch (`GGML_CUDA_FA_INT8_KQ=1`) during the measurements; the default only after the gates.

## Gates

1. `test-backend-ops -o FLASH_ATTN_EXT` passes (its error limit allows int8 Q).
2. KL by position against today's kernel (`bench\kv_kl_sweep.ps1` method) at 4k / 32k / 128k is no larger than the
   KL between q8_0 and f16 K/V (0.00017), so the change costs less than the cache format that we already ship.
3. HumanEval medium and the suite, paired: no loss beyond noise.
4. Prefill at 32k / 64k / 128k: at least 25% faster at 128k, or the work stops there.

## What can go wrong

- The int8 Q error is larger than expected for this model's attention logits (gate 2 catches it).
- Register pressure: the int32 tiles and the scales can lower occupancy. Measure before tuning.
- The per-block scaling adds instructions inside the main loop. The matrix code shows that this is affordable.

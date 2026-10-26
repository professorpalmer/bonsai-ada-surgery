# Prefill at depth: where the time goes, and K·Q on full-rate tensor math (2026-10-26)

Plan written before the runs.

## Why

An independent run on an RTX 3060 12 GB (Doğukan, 2026-10-26) measured decode 53.3 / 46.1 / 40.8 / 32.6 tok/s at 4k /
64k / 128k / 245k with this repo's runtime, but prefill at about 240 tok/s at 245k, the same as a stock runtime: a cold
245k prompt takes about 17 minutes. Prefill at depth is now the slowest part that users see.

## The model, and an estimate

Bonsai 2 27B (`qwen35`): 64 layers, every 4th is full attention (16 layers), 24 query heads, 4 KV heads, head size 256;
the other 48 layers are GatedDeltaNet (their cost does not grow with depth). For one prompt token at depth d, the 16
attention layers do K·Q and V·(KQ), each 2 x 24 x 256 x d multiply-adds per layer: at 245k, about 48 GFLOP each, against
about 54 GFLOP for the weight matmuls.

On GeForce cards the tensor cores run fp16 inputs with **fp32 accumulation at half rate**, and fp16 or int8
accumulation at full rate. In the engine (`fattn-mma-f16.cuh`) K·Q accumulates in fp32 (`T_C_KQ = tile<..., float>`)
and V·(KQ) in fp16 (`T_C_VKQ = tile<..., half2>`); the weight matmuls (MMQ) are int8. So K·Q may be the largest part of
prefill at depth. The estimate for the RTX 3060 (25 / 51 / 102 TFLOPS for fp16-fp32 / fp16-fp16 / int8): K·Q ~1.9 ms,
V·(KQ) ~0.9 ms, weights ~0.5 ms per token at 245k, against 4.2 ms measured.

## Runs

All on the RTX 4070 12 GB (display on the card this session, 274 MiB used by other programs; recorded with each run),
the bundle-20261025 engine binaries (`810d93e5aa`), `llama-bench`, the model file without the MTP head
(`Ternary-Bonsai-2-27B-PTQ1_0.gguf`), `-ctk q4_0 -ctv q4_0 -fa on -ub 512 -b 512 -p 512 -n 0`, one repetition.

- **P1 — depth sweep (measurement, no gate).** Prompt-processing speed of a 512-token batch at depth 0, 32k, 64k, 128k,
  196k and 245k, with `GGML_CUDA_BATCH_INVARIANT=1` (what the 12 GB launcher sets with MTP drafting on) and with it
  unset, at each depth. Result: the marginal cost per token by depth, and the cost of the batch-invariant mode.
- **P2 — the upper bound for K·Q (an engine build, measurement only).** The same sweep with K·Q accumulating in fp16
  (`T_C_KQ` as a half2 tile) on the Ada / Ampere path, if the kernel allows it without other changes. This is not a
  candidate to ship (fp16 accumulation of K·Q over 256-wide heads risks overflow); it shows how much prefill time a
  full-rate K·Q can save. With P2: perplexity on a short text, against P1's build, to see the numeric cost.
- **P3 — the other parts of the attention cost (measurement, no gate).** Added at 10:20, after the first four P1 points
  (batch-invariant on) were seen. The K and V tiles are loaded and dequantized again for each block of query columns, so
  the load can cost as much as the math. At depth 64k, the same pp512 with `-ctk/-ctv` f16, q8_0 and q4_0 (f16 is the
  case with no dequant step). At depth 128k, `-ub 512` against `-ub 2048 -b 2048` with `-p 2048`.

## What decides the next step

- If K·Q at full rate (P2) makes prefill at 245k at least 1.25x faster, the next study is an **int8 K·Q** kernel for
  quantized K caches (int8 tensor math at full rate, with its own gates on speed, perplexity, needles and HumanEval).
- If P1 shows that the batch-invariant mode costs more than 10 % of prefill at depth, that goes to its own study
  (the mode exists for MTP drafting; a prefill exception must keep the drafted output identical).
- If neither, the time is somewhere else, and P1 says where to look next.

## Results

### P1 — depth sweep (10:07-10:44)

GPU memory used by other programs at the start: 539 MiB; memory clock 11,751 MHz. Engine `810d93e5aa`. Records:
`runs.jsonl`, `data/p1_inv1.jsonl`, `data/p1_inv0.jsonl`.

| Depth | tok/s, batch-invariant on | tok/s, off | ms per token (on) |
|---|---|---|---|
| 0 | 1,406.2 | 1,415.9 | 0.711 |
| 32k | 990.8 | 983.7 | 1.009 |
| 64k | 727.0 | 727.4 | 1.375 |
| 128k | 482.2 | 483.3 | 2.074 |
| 196k | 362.4 | 363.9 | 2.759 |
| 245k | 305.5 | 305.5 | 3.273 |

- **The cost per token is a straight line in depth:** 0.711 ms + 10.4 ns per token of depth (the line gives 2.077 ms at
  128k against 2.074 measured). At 245k, the part that grows with depth is 2.56 ms of 3.27 ms (78 %).
- **That part runs at about half of the tensor-math rate.** K·Q and V·(KQ) at 245k are 96.6 GFLOP for each token, in
  2.56 ms: 37.7 TFLOPS. At the RTX 4070's dense rates (about 58 TFLOPS for fp16 with fp32 accumulation, 117 with fp16
  accumulation), the math alone takes 1.24 ms. So about half of the time is not tensor math: loading and dequantizing
  the K and V tiles, the softmax, and synchronization. P3 measures the load part.
- **The batch-invariant mode costs nothing here** (all cells within 0.7 %). That is as expected from the code: the mode
  changes only the kernels for 1-8 columns (decode and drafting), not the 512-column prompt batches. Decision rule 2
  (more than 10 %) does not apply.
- **A hint from the RTX 3060 report:** about 240 tok/s at 245k there, 305.5 here, a ratio of 0.79. The ratio of the
  tensor rates (fp16 with fp32 accumulation) is about 0.44, and the ratio of the memory bandwidths is 0.71 (360 against
  504 GB/s). So the 3060 number agrees better with an attention cost set by loads than by math. This is only a hint:
  that number is from a full server prompt on a different system, not from this bench.

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
- **P3b — a profile of the attention kernel (measurement, no gate).** Added at 11:25, after P2 and the three KV-type
  cells of P3. Nsight Compute on one `flash_attn_ext_f16` launch near depth 64k (q4_0 and f16 K/V, `-ub 512`), clocks
  not locked: warp stall reasons, tensor-pipe use, L2 and DRAM traffic. It says which part of the non-math time to
  attack: global-load latency (then a register prefetch of the quantized tiles, P4), the dequantization work, or the
  barriers.
- **P4 — a register prefetch of the quantized V tile (an engine build).** Added at 11:30, after P3; P3b could not run
  (no access to the GPU performance counters). With a quantized cache, the kernel loads each K and V tile
  synchronously (no pipeline stages), so every warp waits for the global loads. In P4, each thread reads the words of
  its V block pair (9 for q4_0, 17 for q8_0, 7 for q3_0) into registers at the start of the tile, before the K
  dequantization, and dequantizes them into shared memory after the K·Q and softmax steps. The V load then overlaps
  with that work. The arithmetic does not change. Gates: **E1** the output is identical to the bundle engine (KL run
  as in P2: mean KLD 0 and same top token 100 %); **E2** pp512 at 64k, 128k and 245k (q4_0, batch-invariant off) at
  least 1.08x faster at 128k and 245k (above the 5 % noise of one run), no depth slower than 0.97x. If E1 and E2 pass,
  the next step is the same prefetch for the next K tile, then the RTX 2060 check.
- **P5 — P4 for small batches, and the next K tile (added 12:20, after P4).** (a) Decode and drafting run the same
  kernel with few columns. Null against P4, back to back, q4_0 K/V, batch-invariant on (as the 12 GB launcher with
  drafting): `tg128` at depth 4k, 64k and 128k, and `pp4` (a draft check of 4 tokens) at 64k and 128k. Gate **S1**: no
  cell slower than 0.97x. (b) P5b: during the V·(KQ) step, fetch the words of the next K tile into registers, so the
  K loads overlap too. Gates as P4: byte-identical logits; pp512 at 128k and 245k at least 1.04x faster than P4
  in **two** back-to-back pairs (P4, P5b, P4, P5b), because one run has up to 5 % noise and only the K part is new.
  S1 uses `-r 3` for `tg128` and `-r 5` for `pp4`.

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

### P2 — K·Q with fp16 accumulation (10:44-11:18), and its KL check (11:18)

Build: the bundle engine `810d93e5aa` plus one change on the Ampere / Ada path (columns per warp not 8): the K·Q tensor
operations accumulate into a half2 tile, which expands to the fp32 tile before the softmax. Measurement build only,
for the RTX 4070 (`89-real`). Records: `runs.jsonl`, `data/p2_inv1.jsonl`, `data/p2_inv0.jsonl`, `data/kl_p2.txt`.

| Depth | P2 tok/s (batch-invariant on) | against P1 | P2 tok/s (off) | against P1 |
|---|---|---|---|---|
| 0 | 1,405.8 | 1.000x | 1,403.5 | 0.991x |
| 32k | 1,037.5 | 1.047x | 1,043.1 | 1.060x |
| 64k | 789.2 | 1.086x | 799.9 | 1.100x |
| 128k | 535.2 | 1.110x | 534.6 | 1.106x |
| 196k | 402.9 | 1.112x | 403.4 | 1.109x |
| 245k | 340.9 | **1.116x** | 342.5 | **1.121x** |

- **The rule for the int8 K·Q study (1.25x at 245k) is not met:** 1.12x. Full-rate K·Q removes 0.34 ms of the 2.56 ms
  that grows with depth. That is near the 0.41 ms that the tensor rates predict, so the K·Q math was not the large part.
  An int8 K·Q kernel would run at the same full rate (and adds a quantization step for Q), so it cannot give much more
  than this upper bound. **No int8 K·Q study.**
- **Numeric cost (KL against the bundle engine,** `wiki.test.raw`, context 8,192, 2 chunks, q4_0 K and V): PPL 6.6422
  against 6.6370 (ratio 1.00078 ± 0.00051), mean KLD 0.000925, 99 % KLD 0.0074, maximum 0.174, same top token 98.62 %.
  Small, but not zero. The base run against itself was not measured (the kernels are deterministic for a fixed batch).
- Decision rule 3 applies: the time is somewhere else. About 1.3 ms of the 2.56 ms is not tensor math (P1). P3 measures
  the load and dequantization part.

### P3 — KV type and batch size (11:18-11:25), and P3b

Batch-invariant mode off, engine `810d93e5aa`. Records: `runs.jsonl`, `data/p3_*.jsonl`.

| Cell | Depth | tok/s | ms per token | part that grows with depth |
|---|---|---|---|---|
| f16 K and V | 64k | 711.3 | 1.406 | 0.695 ms |
| q8_0 K and V | 64k | 672.3 | 1.487 | 0.777 ms |
| q4_0 K and V | 64k | 723.0 | 1.383 | 0.672 ms |
| q4_0, `-ub 2048 -b 2048 -p 2048` | 128k | 487.5 | 2.051 | (P1, ub 512: 483.3) |

- **The number of bytes does not set the speed.** f16 moves 3.5x the bytes of q4_0 (and 1.9x those of q8_0), but it is
  as fast as q4_0 and faster than q8_0. The f16 path has two pipeline stages (asynchronous copies); the quantized
  paths load synchronously and dequantize. q8_0 is the slowest: its block pair is 17 words against 9 for q4_0, so a
  thread waits for more loads and does more work before the K·Q step can start.
- **A larger batch does not help** (+0.9 % at 128k, within noise).
- The q4_0 cell at 64k repeats P1 (727.4) within 0.6 %.
- **P3b did not run:** Nsight Compute stopped with `ERR_NVGPUCTRPERM` (no access to the GPU performance counters for
  this user). That is a system setting; it stays as it is unless Cary changes it. P4 tests the load-wait question
  directly instead.

### P4 — register prefetch of the quantized K and V tiles (11:32-12:16)

The change (engine branch `research/pkq-prefetch`, commit `57d2928d04` on `810d93e5aa`): the quantized tile loader is
split in two. At the start of each tile, every thread reads the words of its K block pair and of its V block pair into
registers (q4_0: 9 + 9 words for the Ada configuration). The K words are dequantized into shared memory at the old
place; the V words are dequantized after the K·Q and softmax steps, also at the old place. So the V loads are in flight
during that work, and the arithmetic is the same. It applies only when the tile is one chunk (true for head size 256)
and the cache is quantized with no pipeline stages.

**A control.** The P4 build has its own configuration (`89-real` only, its own build folder), so I built the
unchanged source with the same configuration ("null") and measured it too.

**E1, identical output: pass.** The logits that `llama-perplexity --kl-divergence-base` writes (wiki.test.raw, context
8,192, 2 chunks, q4_0 K/V; 4,067,612,676 bytes) are **byte-identical** for the bundle engine, the null build and P4
(SHA-256 `95bf9bb01a3ff444...`). This is stricter than the KL numbers in the gate text: the KL statistics cannot show
0 / 100 % even for one binary against itself, because the base file holds compressed logits (the null against the
bundle gives max KLD 0.000059 and same top 99.988 %, the same as P4 against the null).

**E2, speed: pass.** pp512, q4_0 K/V, batch-invariant off; memory clock 11,751 MHz in all 96 samples under load.

| Depth | P1 (bundle) | null | P4, back to back | P4 / null | P4, first run | first run / P1 |
|---|---|---|---|---|---|---|
| 64k | 727.4 | 724.1 | 767.9 | 1.060x | 772.9 | 1.063x |
| 128k | 483.3 | 481.7 | 525.4 | **1.091x** | 524.7 | 1.086x |
| 245k | 305.5 | 306.0 | 338.5 | **1.106x** | 339.7 | 1.112x |

- The null is as fast as the bundle (within 0.5 %), so the build configuration does not cause the gain.
- The two P4 runs agree within 0.7 %.
- At 245k the prefetch removes about 0.32 ms of the 2.56 ms that grows with depth, about as much as full-rate K·Q in
  P2. The two changes are on different parts, so they may add.

**Next (P5).** Before this can ship: decode and drafting must not get slower (the same kernel runs for small batches),
and the 8 GB card (Turing tiles: 2 block pairs per thread) must gain too. In parallel, the next speed step is to fetch
the next K tile during the V·(KQ) step, so the K loads overlap as well.

### P5a — P4 with small batches (12:17-12:34)

Null against P4, q4_0 K/V, batch-invariant on, memory clock 11,751 MHz. `tg128` with 3 repetitions, `pp4` with 5.
Records: `runs.jsonl`, `data/p5a_*.jsonl`.

| Cell | Depth | null tok/s | P4 tok/s | P4 / null |
|---|---|---|---|---|
| tg128 | 4k | 65.28 ± 0.28 | 64.63 ± 0.30 | 0.990x |
| tg128 | 64k | 52.75 ± 0.20 | 55.38 ± 0.19 | **1.050x** |
| tg128 | 128k | 43.71 ± 0.05 | 47.83 ± 0.15 | **1.094x** |
| pp4 | 64k | 140.05 ± 21.42 | 144.55 ± 20.24 | 1.032x |
| pp4 | 128k | 126.08 ± 13.40 | 130.58 ± 14.43 | 1.036x |

- **S1 passes** (no cell below 0.97x). The 4k decode cell is 1 % slower, about two standard deviations; at 4k the
  attention is a small part of a token, so the cost of the extra registers can show there. It is a point to check
  again on the release candidate.
- **Decode at depth gains too** (+5 % at 64k, +9 % at 128k): with one query column the kernel waits for the K and V
  loads even more than in prefill.
- `pp4` has a large spread (about 15 %) in `llama-bench`; the means agree with a small gain.

# P190 and P191: far-context samples in the T5 window (2026-10-18, kernel session); lead 2 closes

Plans: #138 comments 6245772229 (P190) and 6246295014 (P191), declared before each run. Result: comment 6246585161.

**Question.** P189 showed that the drift hardly falls from a 32k to a 64k window. Does a sparse sample of the far
context remove the drift? If so, a far-context summary in the kernel is worth the build.

**Code.** Fork branch `t5-stride` on `release/t5-candidate` (mask only, `src/llama-kv-cache.cpp`; edit scripts
`stride_patch.py` here and `../p191/bias_patch.py`):
- `LLAMA_PREFILL_WINDOW=...,stride=N`: every N-th 256-position block of the far part stays visible to the windowed
  queries. The chunk skip still skips the blocks that are fully masked.
- `bias=1` (f16 mask only): the sampled far cells get a +log(N) mask value, so each sampled block stands for the N
  blocks it samples (an unbiased estimate of the far attention mass).

**Runs.** Test roots: a copy of the release bins `r-t5` with only `llama.dll` replaced. 8 GB preset on the 4070, line
80,640, layer off, the P170 code and prose sets, the P189 driver and drift score (vs the P189 off base). Scripts
`p190.sh`, `../p191/p191.sh`; logs and answers next to them. 10 runs, 0 CUDA errors. P191 runs with the f16 mask
(`LLAMA_ARG_KQ_MASK_PACKED=0`), so its read has no chunk skip and shows quality only.

| arm | mask | cold 245k (code) | ok of 48 | lost vs off | drift median / p90 |
| --- | --- | --- | --- | --- | --- |
| off (P189) | packed | 451.8 s | 31 | - | - |
| null, chunk 16384 (P189) | packed | 455.7 s | 32 | 0 | 0.004 / 0.012 |
| window 32k (identity: 48/48 equal to P189) | packed | 255.6 s | 32 | 3 | 0.028 / 0.086 |
| window 32k, stride 16 | packed | 284.7 s | 30 | 4 | 0.022 / 0.103 |
| window 32k, stride 8 | packed | 314.3 s (1.44x) | 30 | 1 (prose 18) | 0.014 / 0.060 |
| window 32k, stride 8 | f16 | (no skip) | 28 | 3 (code 15; prose 13, 18) | 0.013 / 0.059 |
| window 32k, stride 8, log(8) bias | f16 | (no skip) | 30 | 2 (prose 13, 18) | 0.029 / 0.091 |

**Decisions (by the declared rules).**
- P190: no candidate. Stride 8's median (0.0143) is just above the "lever" line (0.014) and well under the "not the
  lever" line (0.021), so no claim.
- P191: the bias does not help, it hurts (median 2.2x the no-bias arm; line 0.8x). Lead 2 closes with the map. A likely
  reason (not tested): with the bias, each sampled block carries 8x weight on its own content, so the estimate has a
  high variance.

**Note on the release clause.** The packed stride 8 arm lost only 1 item, inside the #174 R2 limit. The same setting on
the f16 path (only the rounding differs; the same median drift) loses 3. A single run's lost count at this size is not
a stable pass; a future window round should gate on the drift median and p90 against a null arm.

**Map at 245k.** Window 32k: 1.77x, drift 7x the null. Stride 8 or window 64k: 1.44x, drift 3.5-6x the null. No setting
reaches the null band. Work on the window stops.

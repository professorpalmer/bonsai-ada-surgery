# Attention kernel config for the quantized cache (fa-config-20261026)

Plan written before the runs (2026-10-26, 17:45).

## Question

The tensor-core flash-attention kernel picks a config per head size and column count (threads, occupancy, KV cells
per tile, Q in registers). Upstream tuned the Ampere+ rows for f16 K/V with 2 `cp.async` pipeline stages. Our 12 GB
cache is q4_0, which has no pipeline stages (each tile loads and dequantizes synchronously, with the 0072 prefetch).
Does another config of the prefill row (head size 256, 64 columns: `128` threads, occupancy `2`, `32` cells, Q in
registers) run the q4_0 path faster?

Register estimate for that row with q4_0, per thread: Q about 64, VKQ accumulators about 128, KQ about 16, 0072
prefetch 18, which is near the 255 limit. A 64-cell tile adds about 16 + 18, so it needs Q in shared memory, or it spills.

Engine: `research/fa-cfg-sweep` (`7c98a8d64b`) = `a38714c63d` + compile-time overrides for that row (defaults = the
normal config). Base: the release build of `a38714c63d`. All `89-real`.

| Variant | Threads | Occupancy | Cells per tile | Q |
|---|---|---|---|---|
| base | 128 | 2 | 32 | registers |
| E | 128 | 2 | 32 | shared memory |
| B | 128 | 2 | 64 | shared memory |
| C | 128 | 1 | 64 | registers |

This row also runs the verify batches of drafting (up to 33 tokens: 17-32 rows x 2 heads of the group = 64 columns).

## Runs and gates (declared before the runs)

| Run | What | Gate |
|---|---|---|
| C0 | `test-backend-ops -o FLASH_ATTN_EXT`, each variant | all pass |
| C1 | `llama-bench` q4_0, batch-invariant on: pp512 at 32k, 64k, 128k and pp32 at 64k (`-r 3`), base and the variants in turns, 2 rounds | speed |
| C2 | `llama-perplexity` q4_0, context 8,192, 2 chunks, `-ub 512`: E against base byte-identical (only where Q is read from changes); B and C against base: `--kl-divergence` mean KLD at most 0.00005 and same top at least 99.9 % (the tool floor for identical builds: max KLD 0.000059, same top 99.988 %) | quality |

Keep a variant: C0 pass, C2 pass, pp512 at least 1.03x at 64k and at 128k in both rounds, and no C1 cell below 0.98x.
Then: a config that depends on the K/V type (f16 keeps its row), and a server A/B with its own gates. Else: logged, not kept.

## Results (17:46-18:43)

Log: [`data/cfg.log`](data/cfg.log). Rows: [`runs.jsonl`](runs.jsonl). Scripts: `data/cfg.sh`, `data/build_cfg.cmd`.

| Run | E | B | C |
|---|---|---|---|
| C0 | 3115 / 3115 | FAIL: a head-128 q4_0 case asks for more shared memory than the card has (`cudaFuncSetAttribute` "invalid argument"); the 64-cell tile is in the table row of head 256, but the shared-memory size uses the largest row | 3115 / 3115 |
| C2 | logits not identical (Q from shared memory changes the arithmetic) | mean KLD 0.000899, max 0.143, same top 98.66 % | mean KLD 0.000859, max 0.106, same top 98.66 % |

C1, tok/s, mean of 2 rounds (each round `-r 3`), ratio against base:

| | pp512 32k | pp512 64k | pp512 128k | pp32 64k |
|---|---|---|---|---|
| base | 1015.0 | 775.7 | 529.1 | 505.2 |
| E | 900.3 (0.887x) | 644.8 (0.831x) | 413.8 (0.782x) | 439.2 (0.869x) |
| B | 929.6 (0.916x) | 670.9 (0.865x) | 438.8 (0.829x) | 451.3 (0.893x) |
| C | 1015.7 (1.001x) | 772.2 (0.996x) | 523.3 (0.989x) | 500.3 (0.990x) |

Verdict: no variant is kept. The upstream row is the best of the four for the q4_0 cache.

### What this shows

- Q in registers is necessary: reading Q from shared memory costs 11-22 %, more at depth, because each K·Q step then
  reads Q again for every KV tile.
- A 64-cell tile with Q in registers (C) gives the same speed, so the per-tile work (synchronization, softmax
  rescale) is not the limit at 32 cells.
- Side result: a change of only the tile size (C) moves the logits by mean KLD 0.00086 and same top 98.66 %. P2 of
  `prefill-kq-20261026` (fp16 accumulation of K·Q) gave 0.000925 and 98.62 %. So P2's change was the same size as a
  change of the summation order, not a sign of lost precision. P2 stays not kept, because the releases prefer
  bit-identical changes (0072 is one), but the number is now in context.

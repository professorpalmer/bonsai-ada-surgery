# Where the prefill time goes at depth (prefill-profile-20261027)

Plan written before the runs (2026-10-27, 13:50). A measurement study: no change is tested, so there is no keep gate.

## Why

Three changes to the attention kernel were measured on the RTX 2060 SUPER: patch 0072 (loads ahead, shipped, prefill
unchanged on 8 GB), the V-tile prefetch (P230, not faster), fp16 K·Q accumulation (P231, 1.02-1.03x at 64k). On the
RTX 4070, P2 gave only 1.04x on a cold read. Each one guessed at the cost. This study measures it.

## Method

The engine has a per-op GPU timer (`GGML_CUDA_OP_TIMING=1`, with CUDA graphs off): a CUDA event before every graph
node, and the time to the next event goes to that node. Every 100 graphs it prints the ms per graph of each op type
(matmuls by weight shape and column count). `llama-bench -p 512 -d D` first fills the cache to depth D in 512-token
graphs, so the table of the first 100 graphs is the average graph of a cold read from depth 0 to ~51k, and the
second table (graphs 101-200) covers ~51k-102k. The flash-attention op includes its f16 copy of the cache (8 GB
settings), so a run without the copy (`GGML_CUDA_FA_PREFILL_F16=0`) separates the copy from the kernel.

The events add a small cost per node, so the absolute speed of a timed run is not used; only the shares.

## Runs

| Run | Card | Shape |
|---|---|---|
| Q1 | RTX 4070 | 12 GB: q4_0 in place, `-ub 512`, batch-invariant on, `-d 131072` (two tables: 0-51k, 51k-102k) |
| Q2 | RTX 4070 | 8 GB settings: q3_0, the f16 copy (`GGML_CUDA_FA_PREFILL_F16=32768`, `GGML_CUDA_FA_CHUNK=32768`), `-d 131072` |
| Q3 | RTX 4070 | Q2 without the copy (`GGML_CUDA_FA_PREFILL_F16=0`, `GGML_CUDA_FA_CHUNK=0`) |
| P232 | RTX 2060 SUPER | Q2 and Q3 at `-d 65536` (one table, 0-51k; 128k does not fit the card without the tier) |

Engine: the bundle-20261026 release build (`a38714c63d`).

## Results, RTX 4070 (13:45-13:55)

Full tables: [`data/prof_4070.log`](data/prof_4070.log). (A first run printed no table: `llama-bench` drops the engine's
log lines unless it runs with `-v`; the script now passes `-v`.) 0 CUDA errors. ms per 512-token graph, grouped:

| Run | Depth range | Total | Attention (FLASH_ATTN_EXT) | Weight matmuls (PTQ1_0, bf16) | Recurrent layers (GATED_DELTA_NET, SSM_CONV) | Other |
|---|---|---|---|---|---|---|
| Q1 12 GB q4_0 in place | 0-51k | 474.9 | 113.9 (24.0 %) | 272.5 (57.4 %) | 28.9 (6.1 %) | 59.5 (12.5 %) |
| Q1 | 51k-102k | 715.2 | 343.1 (48.0 %) | 280.3 (39.2 %) | 29.8 (4.2 %) | 61.9 (8.7 %) |
| Q2 q3_0 f16 copy | 0-51k | 490.9 | 123.2 (25.1 %) | 278.3 (56.7 %) | 29.1 (5.9 %) | 60.2 (12.3 %) |
| Q2 | 51k-102k | 723.6 | 358.3 (49.5 %) | 276.5 (38.2 %) | 29.0 (4.0 %) | 59.8 (8.3 %) |
| Q3 q3_0 in place | 0-51k | 477.0 | 117.1 (24.5 %) | 272.4 (57.1 %) | 28.6 (6.0 %) | 59.0 (12.4 %) |
| Q3 | 51k-102k | 713.9 | 347.3 (48.6 %) | 275.7 (38.6 %) | 29.4 (4.1 %) | 61.6 (8.6 %) |

(Groups summed from the 30 rows of each table; "Other" = the total minus the three groups.)

What this shows on the 4070:

- The attention time per graph grows linearly with depth (Q1: 114 ms at a mean depth of ~26k, 343 ms at ~77k, about
  4.5 ms per 1k cells). The rest of a graph does not grow (~360 ms). Extended to a 245k cold read (480 graphs at a mean
  depth of ~122k): attention ~550 ms per graph on average, about 60 % of the read; weight matmuls about 30 %. That
  sum (~430 s) agrees with the measured 447 s.
- On the 4070 the f16 copy costs ~3-5 % more attention time than the in-place read (Q2 against Q3), as in the T0c rerun.
- The largest single op is the FFN matmul `5120x17408` (x128 per graph, ~125 ms): 26 % of a shallow graph.

P232 runs Q2 and Q3 on the 2060 at `-d 65536` (issue to follow).

## Results, RTX 2060 SUPER (P232, 2026-10-27 12:57-13:04 CDT, issue #252)

Full tables: [`data/prof_2060_p232.log`](data/prof_2060_p232.log). Engine `a38714c63d`, the published MTP file with its
Q4_0 head, stock clocks (memory 7,001 MHz), 0 CUDA errors. One table per arm (graphs 1-100 = depth 0 to ~51k), grouped
by the rig:

| Group | q2 (8 GB preset: q3_0 + f16 copy) | q3 (q3_0 in place) | RTX 4070 Q2, same range | 2060 / 4070 |
|---|---|---|---|---|
| total per graph | 1,525.7 ms | 1,622.9 ms | 490.9 ms | 3.1x |
| weight matmuls | 881.9 (57.8 %) | 905.8 (55.8 %) | 278.3 (56.7 %) | 3.2x |
| attention | 366.9 (24.1 %) | 435.0 (26.8 %) | 123.2 (25.1 %) | 3.0x |
| recurrent layers (GATED_DELTA_NET, SSM_CONV) | 169.4 (11.1 %) | 174.0 (10.7 %) | 29.1 (5.9 %) | **5.8x** |
| other | 103.5 (6.8 %) | 104.0 (6.4 %) | 60.2 (12.3 %) | 1.7x |

The deeper table does not fit this card without the tier (a 102k-cell q3_0 cache plus the model is above 8 GB, so the
run would spill to system RAM and its numbers would not be valid). The depth split comes from R7's cold reads instead:
the two cold reads (64,009 tokens in 221.2 s, 127,340 tokens in 560.3 s) fit `T(N) = a N + b N^2 / 2` with
a = 2.504 ms per token and b = 29.8 ns per token per token of depth. That model gives 1,496 s for the 243,896-token cold
read that took 1,489 s (P156c). So a 245k cold read on the 2060 is:

| Part | Time at 245k | Share |
|---|---|---|
| the depth-dependent part (attention over the earlier tokens) | ~894 s | 59 % |
| the fixed part per token (2.5 ms) | ~613 s | 41 % |
| of which weight matmuls (1.72 ms per token in this table) | ~422 s | ~28 % |
| of which recurrent layers (0.33 ms per token) | ~81 s | ~5 % |

What this shows:

- **No single op holds the cold read.** Attention is ~59 % of a 245k read on both cards, and three kernel changes to
  it did not move the 2060 (0072: prefill unchanged; V-tile prefetch: slower; fp16 K·Q accumulation: +2-3 %).
- **The weight matmuls run at a lower share of the card's peak on Turing.** Per graph 2 x 27.3 B x 512 = ~28 TOP: the
  4070 runs them at ~100 TOPS (about 43 % of its int8 tensor peak), the 2060 at ~31 TOPS (about 27 %). The PTQ1_0
  prompt matmul on Turing is the largest fixed cost (~28 % of a 245k read) and has room.
- **The recurrent layers are 5.8x slower on the 2060, against ~3x for everything else.** The cause is in the code: the
  chunked tensor-core GDN prefill (`gated-delta-net-mma`) uses BF16 MMA, which only Ampere+ has, so Turing runs the
  recurrent kernel (`gdn_cols_per_warp` gives 1 column per warp below Ampere, 4 on Ampere+). That is ~5 % of a 245k
  read: real, but small.

Candidate leads for the 8 GB cold read, in order of size: (1) the PTQ1_0 prompt matmul on Turing (~28 %, room to the
card's peak); (2) the recurrent layers on Turing (~5 %: an fp16 form of the chunked GDN prefill, or 4 columns per warp
in the recurrent kernel). Each needs the rig for speed (the Turing proxy is not valid for speed).

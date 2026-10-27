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
| Q1 12 GB q4_0 in place | 0-51k | 474.9 | 113.9 (24.0 %) | 272.4 (57.4 %) | 29.0 (6.1 %) | 59.6 (12.5 %) |
| Q1 | 51k-102k | 715.2 | 343.1 (48.0 %) | 280.5 (39.2 %) | 29.8 (4.2 %) | 61.8 (8.6 %) |
| Q2 q3_0 f16 copy | 0-51k | 490.9 | 123.2 (25.1 %) | 274.5 | 29.1 | 64.1 |
| Q2 | 51k-102k | 723.6 | 358.3 (49.5 %) | 274.4 | 29.0 | 61.9 |
| Q3 q3_0 in place | 0-51k | 477.0 | 117.1 (24.5 %) | 272.6 | 28.6 | 58.7 |
| Q3 | 51k-102k | 713.9 | 347.3 (48.6 %) | 274.6 | 29.4 | 62.6 |

What this shows on the 4070:

- The attention time per graph grows linearly with depth (Q1: 114 ms at a mean depth of ~26k, 343 ms at ~77k, about
  4.5 ms per 1k cells). The rest of a graph does not grow (~360 ms). Extended to a 245k cold read (480 graphs at a mean
  depth of ~122k): attention ~550 ms per graph on average, about 60 % of the read; weight matmuls about 30 %. That
  sum (~430 s) agrees with the measured 447 s.
- On the 4070 the f16 copy costs ~3-5 % more attention time than the in-place read (Q2 against Q3), as in the T0c rerun.
- The largest single op is the FFN matmul `5120x17408` (x128 per graph, ~125 ms): 26 % of a shallow graph.

P232 runs Q2 and Q3 on the 2060 at `-d 65536` (issue to follow).

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

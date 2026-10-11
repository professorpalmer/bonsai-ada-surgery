# Depth: decode and prefill past the VRAM line

Work log for speed at 128k-262k context, where the KV cache does not fit in VRAM and its tail lives in pinned system
RAM (the tiered cache). Everything here is measured on this repo's model (Ternary Bonsai 2 27B `PTQ1_0`) with the
receipts named in each section. What shipped is marked **shipped**; the rest are experiments on fork branches, not in
a release.

- [Where the time goes](#where-the-time-goes)
- [CUDA graphs and the tier prefetch (shipped, patch 0053)](#cuda-graphs-and-the-tier-prefetch-shipped-patch-0053)
- [Sparse reads of the host tail](#sparse-reads-of-the-host-tail)
- [Chunked gated-delta-net prefill](#chunked-gated-delta-net-prefill)
- [What did not help](#what-did-not-help)
- [Switches (fork branch `fa-sparse-proto`)](#switches-fork-branch-fa-sparse-proto)
- [Receipts](#receipts)

## Where the time goes

The model has 16 full-attention layers (4 KV heads x 256) and 48 gated-delta-net layers. Only the 16 attention layers
read the cache, so the cost per cache cell is small, but at depth there are a lot of cells:

| KV type | bytes per cell (16 layers, K + V) | 192k cells |
| --- | ---: | ---: |
| q8_0 (12 GB recipe) | 34.8 KB | 6.7 GB |
| q4_0 (8 GB recipe) | 18.4 KB | 3.5 GB |

- **12 GB recipe, RTX 4070 (PCIe 4.0, ~24 GB/s measured).** About 121k-129k cells fit in VRAM. Past that line, every
  decode step moves the host part over PCIe.
- **8 GB recipe, RTX 2060 SUPER (PCIe 3.0, ~11 GB/s).** About 43k-59k cells fit. At 245k, ~3.5 GB crosses the link
  per step: ~320 ms, which is the measured 5.7 tok/s with MTP (~1.8 tokens per step).

Per-op timing (`GGML_CUDA_OP_TIMING=1`, graphs off, `receipts/depth_arms.log`, tag `optime6`), RTX 4070, 192k, dense:
attention plus the wait for the staged host rows is ~35 % of a step. The wait shows up on the op just before
attention (ROPE, 22 %), because that is where the stream waits for the copy. So at this depth on 12 GB, both the copy
and the attention itself matter.

## CUDA graphs and the tier prefetch (shipped, patch 0053)

The tier prefetch pipeline (the copy engine moves the next attention op's host rows into VRAM while the current op
computes) only ran without a CUDA graph, and the launcher keeps CUDA graphs on. Patch 0053 turns CUDA graphs off only
for graphs whose attention reads the host tail; graphs below the line keep them. Details and the release gates are in
the release notes and #22. RTX 4070, 12 GB recipe, mean decode: 192k 23.6 -> 29.4 tok/s, 250k 12.7 -> 14.6, 192k with
lookup off 19.8 -> 25.0; 4k-128k unchanged. RTX 2060 SUPER, 8 GB recipe: 128k +16 %, 192k +9 %, 245k +8 %; 4k / 32k
unchanged.

## Sparse reads of the host tail

Issue #21. The idea (Quest, arXiv 2406.10774): split the host tail into pages, keep the per-page max and min of K for
each dimension, and bound each page's best attention score from the query: sum over d of max(q_d max_d, q_d min_d).
Each query keeps the B cells of the highest-bound pages, the last R cells, and the whole VRAM part; the rest of the
host tail is masked. If the kernel then skips masked rows, they never cross PCIe.

### Implementation steps (fork `fa-sparse-proto`)

| commit | change |
| --- | --- |
| `f5f273aed` | emulation: page bounds, top pages per query, mask; fast mode with page bounds cached per K tensor |
| `346b123b5` | vec kernel skips 128-cell tiles that are `-inf` for every column (exact) |
| `fcc5b8283` | cached bounds follow writes into the K cache (set_rows, buffer writes), `CHECK` / `NOTRACK` debug modes |
| `9f2df0a8f` | page selection on the device (no host copies, no stream sync per op) |
| `71371d4cb` | fast path for up to `MAXQ` queries (draft verify batches); staged ops copy only the kept pages |
| `2f47c38b7` | the written rows come from the host copy of the index input: no sync per K write |
| `03d904ac4`, `615b93cb7` | MMA kernel skips KV tiles that are `-inf` for a whole query tile (tile visibility map) |
| `c803e03ea` | `SINKS`: select over the whole context, the VRAM part too |
| `85d949f5e` | any op with a sparse mask takes the MMA tile map |
| `d6c6e9f01` | tile map entries of 64 cells (page-64 masks skip at their own size) |
| `028f606fc` | vec kernel also skips a warp's 32 cells when all are masked |

**Correctness of the cached bounds** (`bench/sparse_edit.sh`, `receipts/sparse_edit.log`; RTX 4070, 160k, a file at
91 % of the context replaced, 24,966 tokens written again deep in the host tail, then the same request again):

| arm | ops with stale bounds (base / edit / again) | device vs host page choice | answer |
| --- | --- | --- | --- |
| tracking on | 0 / 0 / 0 | 0 differences | the same all three times |
| tracking off (`NOTRACK=1`) | 0 / 208 / 208 | 0 differences | changed after the edit |

### Quality

Retrieval deep in the host tail (`bench/needle_depth.py`, 12 facts; `bench/code_needle.py`, exact copies of 10 short
Python functions). RTX 4070 with the VRAM line pinned at 32,768 cells unless noted:

| run | budget B, page | needles | exact copies |
| --- | --- | --- | --- |
| dense | - | 12/12 | 10/10 |
| 160k, host tail (`receipts/needle_ab.log`, `code_needle_ab.log`) | 8192, 64 | 12/12 | 10/10 |
| 160k, host tail | 4096, 64 | 12/12 | 8/10 |
| 160k, host tail, decode only (`sparse_prefill.log`) | 8192, 256 | 12/12 | 9/10 (misses `_div_nearest` in two runs) |
| 160k, host tail, decode only | 8192, 64 | 12/12 | 10/10 |
| 160k, host tail, prefill sparse too (`MAXQ=4096`) | 8192, 256 | 11/12 | 8/10 |
| 160k, whole context, 12 GB line (`sparse_whole.log`) | 8192, 256, sinks 1024 | 7/12 | 8/10 |
| 245k, RTX 2060 SUPER (#21, P101, emulation build) | 8192 and 16384, 64 | 12/12 | 10/10 |
| 160k, RTX 2060 SUPER, decode only (#21, P105, `d6c6e9f01`) | 8192, 64 | 12/12 | 10/10 |
| 245k, RTX 2060 SUPER, decode only (#21, P105, `d6c6e9f01`) | 8192, 64 | 12/12 | 9/10 (misses `_calc_julian_from_U_or_W`) |

Reading: 64-cell pages hold quality at B = 8192 on the host tail; 256-cell pages lose one short function; sparse
prefill and selection over the VRAM part lose retrieval at these settings.

### Speed

RTX 4070, 160k, VRAM line pinned at 32,768 cells (an 8 GB-like layout: ~127k cells of host tail), dense prefill,
mean decode over code / prose / bash (`receipts/sparse_prefill.log`):

| arm | decode | vs dense |
| --- | ---: | ---: |
| dense | 13.6 tok/s | |
| sparse, page 256, no tile map (`2f47c38b7`) | 9.1 | -33 % |
| sparse, page 256, MMA tile map | 31.1 | x2.3 |
| sparse, page 64, 256-cell tile map | 18.9 | x1.4 |
| **sparse, page 64, 64-cell tile map (`d6c6e9f01`)** | **27.6** | **x2.0** |

The first sparse arm was slower than dense because its decode ops (MTP verify, 5 queries) run on the MMA kernel, which
then read every masked host tile in place over PCIe. The dense arm moves the same rows by DMA, which is faster than SM
reads of host memory. With the tile map, only the kept pages cross the link.

RTX 4070, 12 GB recipe's own line (121,344 cells), 192k (`receipts/sparse_whole.log`): dense 22.8 tok/s, host tail
sparse 25.2, whole context sparse 36.3 (but 7/12 needles, see above).

RTX 2060 SUPER, 8 GB recipe (#21; VRAM line ~46k with the f16 mask; MTP tail 1, so decode ops have 2 queries and run
on the vec kernel; lookup off; `quick_tps.py` mean decode; B = 8192, page 64):

| depth | dense | sparse | build |
| --- | ---: | ---: | --- |
| 64k | 34.5 tok/s | 29.0 (-16 %) | `028f606fc` (P106) |
| 160k | 9.7 | **18.3 (x1.9)** | `d6c6e9f01` (P105) |
| 160k | 9.7 | **18.5 (x1.9)** | `028f606fc` (P106) |
| 245k | 5.7 | 4.3 | `d6c6e9f01` (P102e) |
| 245k | 5.7 | 4.9 | `028f606fc` (P106) |

With lookup verifies (code items), 160k: 12.8 -> 21.5 tok/s (P105). Open on 8 GB: (1) at 245k sparse is still below
dense: something in the sparse decode path grows with the host tail (~3,077 pages at 245k against ~1,753 at 160k);
(2) the 512-token follow-up prefill drops with the sparse settings (160k 107 -> 85, 245k 79 -> 39-44 tok/s; not the
write tracking: `NOTRACK` gives the same, P106; not seen on the 4070); (3) sparse costs ~16 % at 64k (small host
tail), so a default needs a depth threshold. MTP tail 4 is not a way out on 8 GB: three more rollback planes drop the
line from 46,592 to 20,992 cells and MTP acceptance from 0.79 to 0.55 (160k: dense 9.1, sparse 11.5; P105).

**Status:** an experiment. It needs CUDA graphs off and the f16 mask (the page bounds live on the host). On a real
8 GB card it is ~1.9x at 160k, not yet faster at 245k, and it costs ~16 % at 64k and 20-45 % on follow-up prefill
at depth.

## Chunked gated-delta-net prefill

Fork branch `gdn-chunked` (`31c337bbb`), on the release engine: a port of the chunked MMA kernel from
ggml-org/llama.cpp#29353 for the 48 gated-delta-net layers in prefill, with three changes for this model:

- **Raw gates.** Our graph passes the gates before activation (the recurrent kernel activates them); the MMA path
  activates them into temporaries first, with the same formulas.
- **Snapshots for speculative decoding.** With MTP on, every prefill keeps K > 1 recurrent states for rollback. The MMA
  kernel runs the first n - K tokens into a temporary state, and the recurrent kernel runs the last K tokens from it
  and writes the K snapshot slots exactly as before. (Upstream falls back to the slow kernel whenever K > 1.)
- **Fused state gather.** The served graph reads the live state straight from its cache row; the MMA path copies those
  rows into a contiguous state first. Without this the kernel never engaged in the server (first A/B: no change).

Results (`bench/gdn_prefill_ab.sh`, `receipts/gdn_prefill_ab.log`; RTX 4070, 12 GB recipe, drafting on; recurrent vs
MMA, same binary): prefill 4k 1203.9 -> 1280.9 tok/s (+6.4 %), 32k 1021.3 -> 1080.5 (+5.8 %), 128k 581.1 -> 600.7
(+3.4 %); decode unchanged; exact copies 10/10 and needles 12/12 at 32k in both arms. `GATED_DELTA_NET` op tests 57/57
(7 new cases in this model's shape). It needs BF16 MMA (Ampere GA10x, Ada and newer); on Turing the runtime check falls
back to the recurrent kernel, and the sm_75 build compiles clean. **Status:** HumanEval parity gate pending, then a
patch.

## What did not help

| idea | result | receipt |
| --- | --- | --- |
| attention for the host rows on the CPU | ~110 ms per layer for 192k rows on a 6-core CPU vs ~19 ms over PCIe | `docs/8GB.md` |
| sparse prefill (`MAXQ=4096`) | +6 % prefill, but 8/10 copies, 11/12 needles | `sparse_prefill.log` |
| selection over the VRAM part (`SINKS`), B 8192, page 256 | decode 36.3 vs 22.8, but 7/12 needles | `sparse_whole.log` |
| V skip in the vec kernel (`GGML_CUDA_FA_V_SKIP=1`: skip V rows whose weights are all below exp(-20)) | exact (op tests 3007/0, 10/10, 12/12), decode 19.7 -> 19.7 at 192k: the copy dominates there | `vskip_ab.log` |
| larger prefill micro-batch at depth | 512 is best: 654 / 524 tok/s at 128k / 192k; 1024 -36 %, 2048 -85 % | `ubatch_depth.log` |

Not tried, on purpose: dropping prompt tokens from prefill with a small scoring model (speculative prefill). The big
model never sees the dropped tokens, now or in later turns, which does not fit agent work that copies code exactly.

## Switches (fork branch `fa-sparse-proto`)

| variable | meaning |
| --- | --- |
| `GGML_CUDA_FA_SPARSE=B,P,R` | budget B cells, page P cells, recent R cells (unset or B = 0: off) |
| `GGML_CUDA_FA_SPARSE_FAST=1` | cached page bounds, device selection (needs `GGML_CUDA_DISABLE_GRAPHS=1`, `LLAMA_ARG_KQ_MASK_PACKED=0`) |
| `GGML_CUDA_FA_SPARSE_MAXQ=N` | fast path for ops of up to N queries (default 64; larger makes prefill sparse) |
| `GGML_CUDA_FA_SPARSE_SINKS=N` | select from cell N on, the VRAM part too |
| `GGML_CUDA_KV_TIER_STAGE_MIN_Q=9` | ops below 9 queries read the host tail in place (with the tile skip, only kept pages) |
| `GGML_CUDA_FA_TILE_SKIP=1` | MMA tile map for every masked op (on by itself for sparse masks since `85d949f5e`) |
| `GGML_CUDA_FA_SPARSE_CHECK=1` | debug: recompute all bounds each op, log stale pages and device-vs-host selection differences |
| `GGML_CUDA_FA_SPARSE_NOTRACK=1` | debug: writes do not invalidate cached bounds |
| `GGML_CUDA_FA_V_SKIP=1` | vec kernel skips V rows of 32-cell groups with weights below exp(-20) |

## Receipts

`receipts/`: `sparse_edit.log`, `needle_ab.log` / `.jsonl`, `code_needle_ab.log` / `.jsonl`, `sparse_speed.log`,
`sparse_prefill.log` / `.jsonl`, `sparse_whole.log` / `.jsonl`, `vskip_ab.log`, `ubatch_depth.log`,
`gdn_prefill_ab.log`, `depth_arms.log`. Scripts in `bench/` with the same names. The RTX 2060 SUPER runs are on #21
(P101-P105) and #22 (P103).

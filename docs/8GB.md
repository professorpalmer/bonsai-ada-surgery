# Bonsai 2 27B on an 8 GB card that also draws the desktop

> DRAFT (2026-10-07). Numbers are from the development builds of the night (same code paths as the release candidate);
> they are replaced by the release-candidate verification run before this page ships.

Measured 2026-10-06/07 on an RTX 2060 SUPER 8 GB (Turing sm_75, PCIe 3.0 x16, stock clocks, power limit 175 W, fan
100%) that also draws the Windows desktop at 1280x1024 (idle 323-404 MiB), Ryzen 5 2600, 32 GB. Bonsai 2 27B `PTQ1_0`,
one slot, 131,072-token window, greedy, thinking off, `bench/quick_tps.py` (4k -> 16k -> 32k -> 60k, each depth
extending the previous prompt). Plans and gates were written before each run; raw log and receipts on the rig.

## Two modes

| | drafting (default) | long context |
| --- | --- | --- |
| K/V | q4_0 | q4_0 |
| MTP head | ProCreations, requantized to Q4_0 (`build/make_mtp_q4head.ps1`) | none |
| draft / past the VRAM line | 1 / 1 | - |
| positions in VRAM | 47,360 | 53,248 |
| micro-batch | 512 | 1024 |
| f16 prefill (`GGML_CUDA_FA_PREFILL_F16`) | up to 32,768 cells | up to 65,536 cells |
| decode 4k / 16k / 32k / 60k (tok/s) | 51.7 / 48.0 / 43.5 / 29.5 | 43.6 / 38.8 / 34.1 / 22.4 |
| prefill 4k / 16k / 32k / 60k (tok/s) | 411 / 369 / 309 / 190 | 433 / 391 / 328 / 256 |

Same weights on this card with a community 8 GB recipe (64k window, q4_0, all in VRAM, no head) measured decode
37.2 / 30.4 / 24.5 / 17.5 and prefill 427 / 382 / 320 / 256 at the same depths.

## What decides it on 8 GB

1. **Positions are the product.** Past the VRAM line, decode on PCIe 3.0 reads the host tail: q8_0 with 16,384
   positions in VRAM fell from 37 tok/s at 4k to 13.5 at 32k and 3.0 at 120k.
2. **q4_0 K/V.** At the same VRAM it holds 2.3x the positions of q8_0 (32.0 vs 14.1 tok/s at 32k). The cost on this
   card (wikitext-2, 8-16k depth, vs f16 K/V): mean KLD 0.002096, top-1 agreement 97.90% (1 flip in 48); q8_0 0.000167,
   99.42%. Same as the 4070's receipt within 5%.
3. **Turing one-column decode** ([PrismML #325](https://github.com/PrismML-Eng/llama.cpp/pull/325)): Turing takes the
   planar PT mat-vec from #218 at one column, as Ampere does. +13.7% decode (38.07 -> 43.3 tok/s).
4. **Cheap draft head.** Q4_0 head -214 MiB (acceptance 0.875 -> 0.848, decode -1%). Tail draft 1 instead of 2 drops one
   recurrent-state snapshot plane (149.6 MiB) because the rollback ring is sized max(draft, tail). Shared CUDA pool
   (`GGML_CUDA_SHARED_POOL=1`, `LLAMA_MTP_DRAFT_UBATCH=256`) -62 MiB and no prefill cliff in this mode.
5. **f16 prefill from pool memory.** Prefill-sized attention batches convert the q4_0 cache to f16 in transient pool
   memory sized by the actual context (128 MiB at 32k) and run the f16 tensor-core kernel; decode keeps the in-place
   quantized read, and nothing is reserved at load (a reserved copy would be 512 MiB at a 131k window). Prefill +9% at
   16k, +18% at 32k, +26% at 60k; output byte-identical; `test-backend-ops -o FLASH_ATTN_EXT` 2994/2994 on sm_75.
6. **The desktop.** 4K -> 1280x1024 returned ~250-280 MiB (~15-17k q4_0 positions). `nvidia-smi` reports
   `display_active: Disabled` on this WDDM driver while the card draws the desktop; the launcher now asks Windows.

## Margin

77,568 positions (no head, ub 512) held two soaks with 244-257 MiB free: no decode drift beyond 0.9%, llama-server
shared GPU memory flat. Prefill there dropped to ~240 tok/s in 6 of 7 loads when its scratch had to grow under that
margin, so the long-context mode trades positions for prefill headroom: at 53,248 positions with ub 1024 and f16
prefill the lowest free VRAM during a 60k prefill was 118 MiB, with no cliff.

## Not used

- Memory overclock: +250..+1000 MHz moved decode by less than run-to-run drift (decode is core-bound on Turing).
- Core +150 / 215 W: +2-4%; 86 C without extra airflow, 74 C with desk fans; outputs matched stock 25/25 in one
  10-minute soak and 25/26 in the second (cause of the one divergence unresolved).
- PrismML #314's L2 prefetch at its 4070 defaults (16 MiB): -2.4% on this 4 MB-L2 card (receipt on the PR).
- Packed 1-bit KQ mask: exact without the draft head (-128 MiB), but combined with MTP drafting the output past 16k was
  corrupted; not used in either mode.
- Draft 1 / tail 2: rare one-token answers after a long prompt-cache restore (2 of 6 runs); tail 1 0 of 54.

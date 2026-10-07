# Bonsai 2 27B on an 8 GB card that also draws the desktop

> DRAFT (2026-10-07). Numbers below were measured on a development build that also carried PrismML #314 (L2 prefetch,
> capped at 1 MiB) and #209. The release build (Turing fix + shared pool, no #314/#209) is re-measured before this page
> ships; expect decode about 1.5% lower where noted.

Measured 2026-10-06/07 on an RTX 2060 SUPER 8 GB (Turing sm_75, PCIe 3.0 x16, stock clocks, power limit 175 W, fan 100%)
that also draws the Windows desktop at 1280x1024 (idle 323-404 MiB), Ryzen 5 2600, 32 GB. Bonsai 2 27B `PTQ1_0`, one
slot, 131,072-token window, greedy, thinking off, `bench/quick_tps.py` probes. Plan and gates written before each run;
the raw log is in the rig's DECISIONS.md and receipts.

## Two modes

| | drafting (default) | long context |
| --- | --- | --- |
| K/V | q4_0 | q4_0 |
| MTP head | ProCreations, requantized to Q4_0 (`build/make_mtp_q4head.ps1`) | none |
| draft / past the VRAM line | 1 / 1 | - |
| positions in VRAM | 47,360 | 67,840 |
| decode 4k / 16k / 32k / 60k | 52.3 / 48.3 / 43.6 / 29.7 | 44.3 / - / 34.4 / - (77,568: 43.9 / 39.1 / 34.4 / 28.4) |
| prefill 4k / 32k | 405 / 263 | 417 / 302 (at 77,568: ~240 / 186 in 6 of 7 loads) |

Use the long-context mode when conversations regularly run past ~60k; below that the drafting mode is faster.

## What decides it on 8 GB

1. **Positions are the product.** Past the VRAM line, decode on PCIe 3.0 is bound by reading the host tail: q8_0 with
   16,384 positions in VRAM fell from 37 tok/s at 4k to 13.5 at 32k and 3.0 at 120k.
2. **q4_0 K/V.** At the same VRAM it holds 2.3x the positions of q8_0 (32.0 vs 14.1 tok/s at 32k). The cost, measured
   on this card (wikitext-2, 8-16k depth, vs f16 K/V): mean KLD 0.002096, top-1 agreement 97.90% (1 flip in 48); q8_0
   0.000167, 99.42%. Same as the 4070's receipt within 5%.
3. **Turing one-column decode** ([PrismML #325](https://github.com/PrismML-Eng/llama.cpp/pull/325)): Turing now takes
   the planar PT mat-vec from #218 at one column, as Ampere does. +13.7% decode (38.07 -> 43.3 tok/s).
4. **Cheap draft head.** Q4_0 head -214 MiB; tail draft 1 instead of 2 drops one recurrent-state snapshot plane
   (149.6 MiB) because the rollback ring is sized max(draft, tail); shared CUDA pool (`GGML_CUDA_SHARED_POOL=1`,
   `LLAMA_MTP_DRAFT_UBATCH=256`) -62 MiB and keeps prefill scratch shared with the draft context.
5. **The desktop.** 4K -> 1280x1024 returned ~250-280 MiB (~15-17k q4_0 positions). `nvidia-smi` reports
   `display_active: Disabled` on this WDDM driver even while the card draws the desktop; the launcher now asks Windows.

## Margin

Long-context mode uses 67,840 positions (395 MiB free at load, prefill normal); 77,568 was the soaked limit.


77,568 positions held two soaks (10 minutes alternating depths; 4 x 4-minute blocks at 4k / 64k) with 244-257 MiB free:
no decode drift beyond 0.9%, llama-server shared GPU memory flat. Prefill in the long-context mode dropped to ~240 tok/s at 4k
in 6 of 7 loads, when its scratch had to grow under that margin (open: reserve it at load); never seen in the drafting
mode, whose pool is shared with the draft context. At 58,112 or 67,840 positions (395-574 MiB free) prefill was normal.

## Not used

- Memory overclock: +250..+1000 MHz moved decode by less than run-to-run drift (decode is core-bound on Turing).
- Core +150 / 215 W: +2-4%; 86 C without extra airflow, 74 C with desk fans; outputs matched stock 25/25 in one
  10-minute soak and 25/26 in the second (cause of the one divergence unresolved).
- #314's L2 prefetch at its 4070 defaults (16 MiB): -2.4% on this 4 MB-L2 card (receipt on the PR).

# Bonsai 2 27B on an 8 GB card that also draws the desktop

```powershell
.\build\make_mtp_q4head.ps1   # once, after make_mtp_procreations.ps1: the drafting mode's head file
.\start-server.ps1             # detects an 8 GB card: drafting mode if the Q4_0 head file is present
$env:BONSAI_MODEL = 'Ternary-Bonsai-2-27B-PTQ1_0.gguf'; .\start-server.ps1   # long-context mode
```

Needs `bundle-20261007-8gb` or later (patches 0036-0038: `GGML_CUDA_SHARED_POOL`, `GGML_CUDA_FA_PREFILL_F16`, the
Turing one-column decode). An older engine ignores the switches; the measured fixed costs then do not hold, and the
launcher warns before the start. `BONSAI_8GB=0` turns the preset off.

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
| positions in VRAM | sized at launch: 47,360-53,760 here | sized at launch: 53,248-58,880 here |
| micro-batch | 512 | 1024 |
| f16 prefill (`GGML_CUDA_FA_PREFILL_F16`) | up to 32,768 cells | up to 65,536 cells |
| decode 4k / 16k / 32k / 60k (tok/s) | 51.2 / 47.5 / 43.1 / 29.4 | 43.7 / 39.0 / 34.3 / 22.5 |
| prefill 4k / 16k / 32k / 60k (tok/s) | 411 / 369 / 309 / 192 | 433 / 391 / 329 / 257 |

Same weights on this card with a community 8 GB recipe (64k window, q4_0, all in VRAM, no head) measured decode
37.2 / 30.4 / 24.5 / 17.5 and prefill 427 / 382 / 320 / 256 at the same depths.

## Quality

HumanEval 164 (`bench/humaneval_run.py --arm medium`, temp 0, 20,480-token cap, layer off), drafting mode on this card:
q4_0 K/V 157/164, q8_0 K/V 159/164 (the 12 GB q8_0 runs: 159-161). The two failure sets overlap except for two problems
q4_0 also missed. For exact-syntax work that fits in ~20k tokens, `BONSAI_CTK=q8_0` trades positions in VRAM (about
21k instead of 47k) for that margin; the launcher sizes the line for it.

## Lookup drafting

The drafting mode also takes lookup drafting (patch 0039, on by default; `BONSAI_LOOKUP=0` turns it off): an n-gram
drafter proposes up to 32 tokens of text that is already in the context, and the MTP head drafts new text. A long
lookup draft uses the server's state checkpoint, not more recurrent-state planes, so the VRAM line does not change.
`bench/lookup_ab.py`, drafting preset, decode tok/s (`receipts/lookup_ab_8gb.jsonl`):

| depth | file rewrite | edit call | plain |
| --- | --- | --- | --- |
| 0, MTP only / with lookup | 58.2 / 125.9 | 56.9 / 60.5 | 52.5 / 52.8 |
| 64k, MTP only / with lookup | 32.5 / 69.3 | 32.5 / 37.7 | 31.4 / 31.3 |

At depth 0 the text is the same with and without lookup (11 of 11). At 64k one file rewrite of 11 items differs: a wider
verify batch changes attention rounding, as MTP drafting itself does. Lowest free VRAM at 64k: 82 MiB with lookup, 90 MiB without it (at depth 0: 207 and 211 MiB), so lookup adds
about 8 MiB and the low point comes from the depth.

## What decides it on 8 GB

1. **Positions are the product.** Past the VRAM line, decode on PCIe 3.0 reads the host tail: q8_0 with 16,384
   positions in VRAM fell from 37 tok/s at 4k to 13.5 at 32k and 3.0 at 120k.
2. **q4_0 K/V.** At the same VRAM it holds 2.3x the positions of q8_0 (32.0 vs 14.1 tok/s at 32k). The cost on this
   card (wikitext-2, 8-16k depth, vs f16 K/V): mean KLD 0.002096, top-1 agreement 97.90% (1 flip in 48); q8_0 0.000167,
   99.42%. Same as the 4070's receipt within 5%.
3. **Turing one-column decode** ([PrismML #325](https://github.com/PrismML-Eng/llama.cpp/pull/325)): Turing takes the
   planar PT mat-vec from #218 at one column, as Ampere does. +13.7% decode (38.07 -> 43.3 tok/s).
4. **Cheap draft head.** Q4_0 head -214 MiB (acceptance 0.875 -> 0.848, decode -1%). Tail draft 1 instead of 2 drops one
   recurrent-state snapshot plane (149.6 MiB) because the rollback ring is sized max(draft, tail). A smaller draft
   micro-batch (`LLAMA_MTP_DRAFT_UBATCH=256`). The shared CUDA pool (`GGML_CUDA_SHARED_POOL=1`) saved 62 MiB more, but
   with MTP drafting it gave 1-token answers to fresh long prompts on this card (60k: 3 of 3 with it, 0 of 3 without),
   so the preset does not set it.
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

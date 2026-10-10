# Bonsai 2 27B on an 8 GB card that also draws the desktop

```powershell
.\build\make_mtp_q4head.ps1   # once, after make_mtp_procreations.ps1: the drafting mode's head file
.\start-server.ps1             # detects an 8 GB card: drafting mode if the Q4_0 head file is present
$env:BONSAI_MODEL = 'Ternary-Bonsai-2-27B-PTQ1_0.gguf'; .\start-server.ps1   # long-context mode
```

Needs `bundle-20261007-8gb` or later (patches 0036-0038: the Turing one-column decode, `GGML_CUDA_FA_PREFILL_F16`);
`bundle-20261008-8gbfix` or later is recommended (no 1-token answers, lookup drafting, patches 0041-0045). An older
engine ignores the switches; the measured fixed costs then do not hold, and the launcher warns before the start.
`BONSAI_8GB=0` turns the preset off.

Measured 2026-10-06/07 on an RTX 2060 SUPER 8 GB (Turing sm_75, PCIe 3.0 x16, stock clocks, power limit 175 W, fan
100%) that also draws the Windows desktop at 1280x1024 (idle 323-404 MiB), Ryzen 5 2600, 32 GB. Bonsai 2 27B `PTQ1_0`,
one slot, 131,072-token window, greedy, thinking off, `bench/quick_tps.py` (4k -> 16k -> 32k -> 60k, each depth
extending the previous prompt). Plans and gates were written before each run; raw log and receipts on the rig.

## The 262k window (patches 0047-0049)

With an engine that has patches 0047-0049 and 24 GB of system RAM or more, the drafting mode uses the full 262,144-token
window. Three changes make it fit, and together they put more positions in VRAM than the earlier 131k preset had:

| change | VRAM it returns (this card) |
| --- | --- |
| Packed (1-bit) KQ mask (0048/0049) | the f16 mask is window x micro-batch x 2 bytes: 128 MiB at 131k, 256 MiB at 262k; packed is 1/16 |
| Shared CUDA pool (now safe with drafting, patch 0045) | ~51 MiB |
| Partial staging (0047) | the staging buffer stops growing with the window: 81,920 staged positions at any window |

Same card and method, drafting preset with lookup, `quick_tps.py` 4k -> 128k (decode = mean of code / prose / bash;
prefill = a 512-token follow-up request at that depth):

| | 4k | 32k | 64k | 96k | 128k | 160k |
| --- | --- | --- | --- | --- | --- | --- |
| 131k preset before (50,176 positions in VRAM): decode | 51.0 | 46.0 | 30.5 | 17.8 | 13.0 | - |
| 262k now (59,904 in VRAM): decode | 51.7 | 46.5 | 37.8 | 20.1 | 14.2 | 10.4 |
| 131k preset before: prefill | 350 | 257 | 152 | 118 | 96 | - |
| 262k now: prefill | 359 | 262 | 156 | 121 | 99 | 59 |

Fresh 60k prompts: 37.3 / 37.2 tok/s (before: 28.2 / 28.2). Lowest free VRAM in the run: 116 MiB. 0 one-token answers.
With MTP drafting and lookup, the packed mask gave the same text as the f16 mask in 22 of 22 requests at 32k and 64k.
Past the staged depth (the VRAM line + 81,920, about 140k here) the host rows are read in place, so a follow-up
prefill there is slower (59 tok/s at 160k against 99 at 128k).

Chunked prefill (patch 0051, on in the preset with an engine that has it) runs prefill attention past the f16 prefill
limit in chunks of 32,768 cells: each chunk is copied to VRAM once, converted to f16 and run on the tensor-core kernel,
and the chunks are merged with the softmax max and sum. Same card, 262k, `quick_tps.py` 4k -> 64k -> 128k -> 192k -> 250k:

| depth | 64k | 128k | 192k | 250k |
| --- | --- | --- | --- | --- |
| code-prompt prefill, before / chunked (tok/s) | 234 / 282 | 121 / 171 | 58 / 116 | 25 / 90 |
| 512-token follow-up, before / chunked (tok/s) | 153 / 204 | 100 / 136 | 35 / 97 | 19 / 80 |
| decode (tok/s) | 34.7 / 32.3 | 11.6 / 11.8 | 8.4 / 8.1 | 5.7 / 5.7 |

Decode does not change (the 64k pair differs by the VRAM line: 59,392 / 57,600 at those two starts). A 58k-token
paste at 250k took ~38 min before and ~11 min chunked. Quality: perplexity at a 64k window (wikitext-2, 2 x 65,536)
7.2106 in place, 7.2107 with a whole-cache f16 copy, 7.2074 chunked (+/- 0.071); with drafting at 64k, 8 of 11 texts
match the unchunked run; the three that differ are the near-tie plain items, and a whole-cache f16 copy against
chunked gives the same 8 of 11. `GGML_CUDA_FA_CHUNK=0` turns it off. `BONSAI_STAGE_CELLS` sets the staged depth;
`BONSAI_CTX=131072` gives the earlier window (the launcher does that by itself with less than 24 GB of RAM).

Past the VRAM line, decode reads the host part of the cache over PCIe on every token. This card has PCIe 3.0 x16
(about 13 GB/s). A PCIe 4.0 x16 card (RTX 3060 Ti / 3070 class) has about 1.8x that link (the RTX 4070 measured 23.7 GB/s
in this read), so its deep end should be faster than the table; not measured on an 8 GB card. RTX 4060 / 4060 Ti /
5060-class cards use 8 lanes, which on a PCIe 4.0 board is about the same link as this card.

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

The deep end on `bundle-20261008-8gbfix` (engine `142d5105d`, drafting preset with lookup, same method; 4k-64k from the
release check, 96k-126k from the same engine family `8a6d2ea12`):

| depth | 4k | 32k | 64k | 96k | 126k |
| --- | --- | --- | --- | --- | --- |
| decode (tok/s, mean of code / prose / bash) | 51.5 | 46.4 | 30.4 | 17.7 | 14.1 |
| prefill (tok/s) | 410 | 331 | 193 | 140 | 112 |

Past the VRAM line (about 54k positions here) decode reads the host part of the cache over PCIe 3.0 on every token.
For copy-heavy work, lookup drafting keeps the deep end usable (file rewrites: 69 tok/s at 64k, 42 at 120k).

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

## Long prompts that change inside a message

This model keeps context checkpoints (its recurrent state) at user-message starts and at the prompt end. Without more,
a prompt that changes inside one long message (an edited tool result, a file sent again) is processed again from the
start: about 4.5 minutes at 64k on this card. Patch 0046 (`--checkpoint-every-nt`) also keeps a checkpoint every N
tokens inside a message; the 8 GB preset sets 8192 when the engine has it (`BONSAI_CKPT_EVERY` changes it, 0 turns it
off). RTX 2060 SUPER, `lookup_ab.py` at 64k, requests after the first: 18-58 s instead of 272-294 s, and the text of all
22 requests is identical to the run without it (`receipts/ckpt_every_nt_8gb.jsonl`). Each checkpoint takes about
170 MiB of system RAM (at most 32).

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
   micro-batch (`LLAMA_MTP_DRAFT_UBATCH=256`). The shared CUDA pool (`GGML_CUDA_SHARED_POOL=1`) first gave 1-token
   answers to fresh long prompts with MTP drafting (60k: 18 of 18); patch 0045 orders the two streams (0 of 38), and the
   preset now turns it on with engines that have it (~51 MiB, P83: 0 of 3 fresh 60k, decode +7 % at 64k).
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

- Core +150 / 215 W: +2-4%; 86 C without extra airflow, 74 C with desk fans; outputs matched stock 25/25 in one
  10-minute soak and 25/26 in the second (cause of the one divergence unresolved).
- PrismML #314's L2 prefetch at its 4070 defaults (16 MiB): -2.4% on this 4 MB-L2 card (receipt on the PR).
- Packed 1-bit KQ mask, first test: corrupted output past 16k with MTP drafting. That build had the shared pool race and
  staging buffers shared by the main and draft contexts. On the current engine: 22 of 22 texts identical; now used.
- Draft 1 / tail 2: rare one-token answers after a long prompt-cache restore (2 of 6 runs) - those runs had the shared
  CUDA pool on. With it off: 0 of 81 answers (tail 1 and tail 2). Tail 2 is still not used: more drafts past the VRAM
  line gained at most +9 % at 126k and cost up to 41 % at 32k (fewer positions in VRAM).
- Partial staging at 131k (40,960 staged positions): +6-9 % decode at 64k-128k, but prefill -50 % at 128k. Not used.
- Reading the host tail in place for decode (`GGML_CUDA_KV_TIER_STAGE_MIN_Q=2`): the same decode as staging on this card.

## Optional: memory clock

On this card decode reads the ternary weights at about 80 % of the memory bandwidth, so the memory clock matters.
llama-bench, plain decode: +500 MHz +4.2 %, +1000 MHz +7.7 %. With the drafting preset (server): +1000 MHz gives
+2.4-2.7 % at 4k-32k, and a 60-minute soak gave byte-identical text with no driver errors. +1250 MHz faulted the GPU
after about 10 minutes of load, and +1500 MHz stopped the PC (bugcheck). Set the clock before the server starts:
switching it while a server runs stopped the server twice. Clocks are the owner's choice; the launcher does not touch
them.

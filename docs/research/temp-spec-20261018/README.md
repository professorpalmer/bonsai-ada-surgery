# MTP drafting against sampling temperature (2026-10-18)

Data run (no default change was at stake, so no gate). Question: does MTP drafting still pay at chat temperatures, and
does the draft p-min gate (`LLAMA_ARG_SPEC_DRAFT_P_MIN=0.5`) help there? Note: this README was written after the run;
the setup is in `tempspec_run.sh` / `tempspec.py` (scratchpad copies below).

Setup: bundle-20261018e root (engine a6d4fc698f), 8 GB preset (`BONSAI_8GB=1`, VRAM line 80,640), layer off.
Prompts: a 4k or 16k filler, then "write a ~600-word story" or "write an LRU cache module"; 400 tokens, top_p 0.95 when
T > 0, thinking off. T 0 (one run), T 0.7 and T 1.0 (seeds 1-3). Arms: spec (default: MTP draft 1 + lookup), pmin5
(the same + p-min 0.5), nospec (`BONSAI_SPEC=0`). 0 CUDA errors.

| depth | prompt | T | nospec tok/s | spec tok/s (acceptance) | pmin5 tok/s (acceptance) |
|---|---|---|---|---|---|
| 4k | code | 0 | 66.6 | **90.0** (0.83) | 83.6 (0.88) |
| 4k | code | 0.7 | 66.5 | **87.7** (0.76) | 78.5 (0.81) |
| 4k | code | 1.0 | 66.4 | **83.3** (0.66) | 75.2 (0.69) |
| 4k | story | 0 | 67.0 | **77.1** (0.58) | 62.9 (0.74) |
| 4k | story | 0.7 | 66.5 | **76.1** (0.53) | 61.8 (0.66) |
| 4k | story | 1.0 | 66.4 | **75.5** (0.51) | 63.2 (0.62) |
| 16k | code | 0 | 62.5 | **85.0** (0.83) | 79.6 (0.88) |
| 16k | code | 0.7 | 62.7 | **82.0** (0.71) | 72.0 (0.77) |
| 16k | code | 1.0 | 62.5 | **77.8** (0.60) | 69.2 (0.68) |
| 16k | story | 0 | 63.0 | **76.4** (0.63) | 62.4 (0.77) |
| 16k | story | 0.7 | 62.6 | **72.8** (0.54) | 59.2 (0.66) |
| 16k | story | 1.0 | 62.4 | **69.4** (0.45) | 60.2 (0.60) |

Findings:
- Drafting pays at every temperature tested: +11 % (story, 16k, T 1.0) to +36 % (code, 16k, T 0) over no drafting.
  Acceptance falls with temperature (code 0.83 -> 0.60-0.66, story 0.58-0.63 -> 0.45-0.51), speed falls 2-9 %.
- p-min 0.5 is slower in all 12 cells (-6 % to -18 % against the default), although its acceptance is higher: it drops
  drafts that would have been accepted often enough to pay. Not adopted; the default stays (no p-min).
- At T 0 to 1.0 the no-drafting speed is flat (sampling cost is not visible).

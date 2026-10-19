# A DFlash 2 drafter on the 12 GB preset (2026-10-19)

**Result: rejected for 12 GB.** Decode is slower at every depth (mean -14.8 %, 245k -32.6 %); the drafter costs
about 1.2 GB of VRAM plus a fixed ~722 MiB host-side part. See [EXPERIMENTS.md](EXPERIMENTS.md).

Plan written before the runs. One entry per run goes to `EXPERIMENTS.md`, one line per run to `runs.jsonl`.

## Question

Is the DFlash 2 drafter `naklitechie/Qwen3.8-27B-DFlash2-ternary-bonsai2` (file `Qwen3.8-27B-DFlash2-r3-Q4_K_M.gguf`,
1,143,006,912 bytes, repo commit 0059b38a, Apache-2.0) faster than the MTP head on the RTX 4070 12 GB, over the whole
window? Its card reports +2-8 % acceptance over its base drafter and 2.15x on an NVIDIA L4, but against plain decode,
not against an MTP head. P033 (2026-10-07, `../depth-8gb-20261006/experiments/P033.md`) rejected an earlier DFlash 2
fine-tune on 8 GB (mean decode below the MTP mode, ~645 MiB more VRAM, prefill -33 %) and named 12 GB as the open case.
This drafter was not tested.

## Setup

- RTX 4070 12 GB, display on the iGPU, bundle-20261019a root (engine with DFlash 2 support from the base fork,
  `--spec-type draft-dflash`), the 12 GB default (q4_0, 262k window), layer off.
- Control (C): the 12 GB default (`ngram-mod,draft-mtp`, draft 2, 4 past the VRAM line), the fresh-server table of
  2026-10-19 (`docs/receipts/depth_table_bundle-20261019a-12gb-fresh.log`).
- DFlash arm (D): `BONSAI_SPEC_TYPE=ngram-mod,draft-dflash`, `BONSAI_SPEC_ARGS="-md <drafter> -ngld 99"`, the same
  model file. The launcher does not count a separate drafter's weights in its VRAM budget, so:
  - D0 probe: start with the margin raised by 1,400 MiB, one 4k request, read free VRAM; then set
    `BONSAI_KV_VRAM_CELLS` so that the free VRAM at a 245k request stays at or above the control's margin.
  - D1: `bench/depth_table.sh` with a fresh server for each depth, 4k / 32k / 64k / 128k / 192k / 245k (the control's
    depths and prompts).
- Control check: C at 4k and 128k again after D1 (fresh server each). Each must be within 2 % of the morning table,
  or the whole control runs again.

## Gates (declared before the runs)

- G1: D's mean decode over the six depths is at least 5 % above C's.
- G2: no depth is more than 5 % below C.
- G3: cold prefill (the code prompt) at 128k is not more than 10 % below C.
- G4: 0 CUDA errors, 0 spill lines, every request answers.

All pass: document D as an opt-in 12 GB setting (a knob, not a default; the default needs an agent-suite run). Any
fail: documented as measured and dropped for 12 GB.

# Adaptive MTP draft depth on the 8 GB preset, with replay rollback (2026-10-19)

**Result: not adopted.** Gates G1 and G2 fail (code +2.3 % against +5 % required; story -9.4 % / -5.6 % at 64k against
-3 % allowed). Deeper drafts past the VRAM line help at 128k; arm F2 (a fixed draft of 2 / 2) tells whether a fixed
size gets that gain without the story loss. Entries: [EXPERIMENTS.md](EXPERIMENTS.md). Receipts: [receipts/](receipts/).

## Idea

The draft size climbs after runs of fully accepted MTP drafts and drops after misses. The controller comes from
zgsndzq/llama.cpp-qwen38-flash (MIT): climb after 2 / 4 / 6 full accepts at depth 1 / 2 / 3, drop when the missed tokens
reach max(5 x depth, 20). A fixed draft of 2-3 was rejected on 8 GB before (P35: code +3 / +7 %, prose -10 %), and each
extra draft token cost a 150 MiB rollback plane. With replay rollback (patch 0070) a plane costs about 7 MiB. So a depth
that climbs on predictable text (code) and stays at 1 on prose can keep the gain without the loss.

Engine: `serve/mtp-adaptive` = `serve/gdn-replay` (5b79541ebb) + `--spec-draft-adaptive` / `--spec-draft-n-min-adaptive`,
commit dc8a6b4fef. (The server's version string says 5b79541ebb: the incremental build did not regenerate build-info.
`llama-common.dll` holds the new flag, so the binaries are the new build.)

## Arms (declared before the runs)

All arms: RTX 4070, `BONSAI_8GB=1`, layer off, `LLAMA_RS_REPLAY=1`, the 8 GB split pinned (`BONSAI_KV_VRAM_CELLS`).

| Arm | Draft | VRAM line |
|---|---|---|
| F1 | fixed 1 below and past the line (the 8 GB recipe + replay) | 90,880 |
| A4 | adaptive 1..4 below the line, `BONSAI_SPEC_DEEP=4` past it (the cap the depth can climb to) | 90,624 |
| A3 | adaptive 1..3, `BONSAI_SPEC_DEEP=3` | 90,624 |
| F2 | fixed 2 / 2 (added after P215 in #138 proposed it as the 8 GB default with replay) | 90,112 |

Requests (`receipts/r2.py`): story / code / quote, greedy and temperature 0.8, 300 tokens, thinking off, at 4k, 32k,
64k and 128k. One server per arm.

| Gate | Condition |
|---|---|
| G1 | an adaptive arm beats F1 by 5 % or more on the mean decode of the code requests (all depths) |
| G2 | that arm loses no more than 3 % against F1 on any story request mean per depth |
| G3 | 0 CUDA errors; every request answers |

G1-G3 pass: the adaptive depth becomes the 8 GB default together with replay. Any fail: not adopted; log why.

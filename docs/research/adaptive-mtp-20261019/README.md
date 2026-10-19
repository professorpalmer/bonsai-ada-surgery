# Adaptive MTP draft depth on the 8 GB preset, with replay rollback (2026-10-19)

**Result: not adopted.** Gates G1 and G2 fail (code +2.3 % against +5 % required; story -9.4 % / -5.6 % at 64k against
-3 % allowed). A fixed draft of 2 / 2 (AD2) is the best balance: code +4.6 %, story +1.4 %, quote +11.6 % over all
depths, 128k code +19.6 %; its weak depth is 64k (story -3.1 %). It supports 2 / 2 as the 8 GB default with replay. Entries: [EXPERIMENTS.md](EXPERIMENTS.md). Receipts: [receipts/](receipts/).

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

## AD3 (declared 2026-10-19 15:35): fixed 2 below the line, 4 past it

AD1 / AD2 data: past the VRAM line the step is PCIe-bound, and A4 (draft 4 past the line) was ahead of F2 at 128k on
story (+3.6 %) and quote (+15 %). Arm **F2T4**: `BONSAI_SPEC=2 BONSAI_SPEC_DEEP=4`, the same bins as AD1 / AD2, the line
lowered by the two extra replay depths (2 x 7 MiB, rounded up: 90,112 - 1,024 = 89,088). Compared with F2 (AD2 data).

| Gate | Condition |
|---|---|
| T1 | 128k: the mean of the code / story / quote means is at least 5 % above F2 |
| T2 | 4k-64k (below the line, the same draft size): no prompt type more than 2 % below F2 per depth (a noise check) |
| T3 | 0 CUDA errors; every request answers |

T1-T3 pass: 2 / 4 replaces 2 / 2 in the proposal for the 8 GB default with replay (#138). Any fail: 2 / 2 stays.

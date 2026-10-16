# Release plan: patches 0060-0063 (saved-conversation draft sidecar + Turing prefill tiles)

Written 2026-10-16, before any gate runs. Engine candidate: kernel fork `product-0060` **1bee9252a** =
product-0059 (`ab9481005`) +

| patch | commit | what |
| --- | --- | --- |
| 0060 | 3b7e0f210 | server: slot save / restore also writes / reads the draft context (MTP) in `<file>.draft` |
| 0061 | 303f01131 | server: the restore loads the sidecar for real (the first commit only read its 12-byte header) |
| 0062 | 8f1516fae | cuda: `GGML_CUDA_FA_PREFILL_NCOLS2=2` (2 Q heads per column group for prefill attention, GQA 6) |
| 0063 | 1bee9252a | cuda: NCOLS2=2 by default on Turing only; `GGML_CUDA_FA_PREFILL_NCOLS2=8` turns it off, `=2` on elsewhere |

Why: with `BONSAI_SLOT_SAVE_PATH` (merged, #145) a saved conversation restores in seconds (#138 T1; 4070 T1-b 245k
2.2 s vs 468 s; 2060 P153 5.2 s vs 28 min), but on the 2060 the first big turn after a restore read at 12-24 tok/s
because the MTP draft context was not in the file (P157b); 0060/0061 fix that. 0062/0063 make a cold 245k read on
2060-class cards 1.147x faster (P156c: 1,707 -> 1,489 s; PPL +0.02 %, KL 0, P156).

## Gates (declared now)

| gate | where | rule |
| --- | --- | --- |
| R1 sidecar on sm_75 | 2060, P158 (product-slotdraft 303f01131) | `.draft` written; "draft context state restored" in the log; new-token prompt eval >= 150 tok/s at 64k and >= 100 tok/s at 131k after a fresh restore; answers equal to memory; 0 CUDA errors over 3+ restores |
| R2 Turing tiles items | 2060, P156d (T2a-2 Q2) | n 20 / n 24 / n 28 at 245k item by item vs the default on the same bins (gains allowed, no lost item) |
| R3 op tests | 4070, release bins | ADD, RMS_NORM, GET_ROWS, SET_ROWS, CPY, FLASH_ATTN_EXT, GATED_DELTA_NET: 0 FAIL |
| R4 sm_89 unchanged | 4070, release bins vs bundle-20261016 bins | d27 hashes (3 prompts, temp 0) identical on the 12 GB default and on `BONSAI_8GB=1` (NCOLS2 stays off on sm_89); cold 128k prefill within 2 % |
| R5 launcher paths (T1) | 4070, staged zip | default -> q4_0 (12 GB); `BONSAI_8GB=1` -> q3_0 + sparse auto; `BONSAI_TOTAL_MIB=24576` -> q8_0; `BONSAI_SLOT_SAVE_PATH` -> the slots line, save + restore of a short prompt; each answers one request; 0 control bytes in tracked text files |
| R6 saved conversation on the release zip | 4070, staged zip, `BONSAI_8GB=1`, 131k | T1-h flow: both files, restore line, answer = memory |
| R7 publish | - | zip from the release commit, GitHub + Hugging Face, SHA on both, bins installed, 2060 post-zip check; in that check one fresh-server restore at 64k + ~4k new tokens with MTP on (the shipped sm_75 bins): >= 150 tok/s new-token eval, the restore line, 0 CUDA errors |

If R2 fails: drop 0062/0063 and ship 0060/0061 alone (R1, R3-R7 on a rebuilt sidecar-only engine). If R1 fails: no
release; `BONSAI_SLOT_SAVE_PATH` stays documented with the limit (the first big turn after a restore is slow on 8 GB
cards).

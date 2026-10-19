# Results

2026-10-19, RTX 4070 12 GB. Receipts: `release_1019b.log` (the gate run 17:49-18:00 and the recheck 18:11-18:12),
scripts `make_bundle_1019b.py`, `rel1019b.sh`, `recheck.sh`. Published zip: sha256 `d5a53c2b2ad238e2...` (the recheck
zip; it differs from the gated zip only in `docs/8gb/README.md`, see R1).

| Gate | Result |
|---|---|
| R1 zip | PASS. Outside `docs/`: no new or removed entries, the CUDA runtime identical, `--version` `810d93e5aa`. `docs/`: the restructured docs (89 entries in all), 0 broken relative links after the 17:50 amendment. The gated zip had 1 file with a control byte (`docs/8gb/README.md`: a backspace where `.\build\` was, from the restructure); fixed in the repo, the zip made again: it differs from the gated zip only in that file, 0 control-byte files |
| R2 launcher | PASS on its intent (see below). Default (12 GB): spec 2 / 4, replay off. `BONSAI_8GB=1`: spec 2 / 2, replay on (`replay rollback: one S plane + pending inputs of 2 tokens`). `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`: spec 1 / 1, replay off. 24 GB: health. Every arm: a short greedy answer, 0 CUDA errors |
| R3 graph line | PASS: 2 `ggml_cuda_graph_check_compability` warnings past a 32,768-position line (at most 2), 6 / 6 requests, 0 CUDA errors |
| R4 saved conversations | PASS: 3 turns of a 20k conversation (slot files 1, 2, 3), two conversations that take turns (A2 and B2 each read 24 new tokens after their own save), 0 CUDA errors |
| R5 file compatibility | carried over from release-20261019 (the slot code is the same) |
| R6 speed, 12 GB | PASS: 4k 95.9 tok/s (96.5 in the morning table, -0.6 %), 32k 86.1 (86.8, -0.8 %) |

R2, the buffer sizes: the plan named 299.25 MiB for the 12 GB default and 156.77 MiB for the 8 GB default. Those were
the values of the staged release's configurations (draft 1 / 1), copied by mistake. Measured with log verbosity 4:
12 GB default 748.12 MiB (five ~150 MiB planes for draft 4, replay off), 8 GB default 163.92 MiB (one plane + 2
pending tokens; 156.77 MiB is the value for 1 pending token, so a token adds 7.15 MiB), `BONSAI_RS_REPLAY=0` 299.25 MiB
(two planes, replay off). What the gate checks, replay off / on / off in the three arms, holds.

Verdict: publish bundle-20261019b as the latest release.

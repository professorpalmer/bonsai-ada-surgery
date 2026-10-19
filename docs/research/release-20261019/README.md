# Release bundle-20261019 (replay rollback, opt-in)

Date: 2026-10-19. Engine release: `bin/` from the engine build at `5b79541ebb` (`serve/gdn-replay` = bundle-20261018f's
engine `a6d4fc698f` + patch 0070); every other file from `git archive` of the release commit 44fd1c4 (#201). What is new:
`BONSAI_RS_REPLAY=1` turns on replay rollback (the recurrent state keeps one plane instead of one per draft token,
142 MiB less VRAM; on the 8 GB preset the VRAM line grows by ~10,000 cells). Off by default: the default path gives
the same bytes as bundle-20261018f (`docs/research/gdn-replay-20261018`).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | the same entries as 1018f; changed: the engine `bin/` files, `start-server.ps1`, docs; the CUDA runtime DLLs identical; 0 text files with control bytes; `--version` reports `5b79541ebb` |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors; the RS buffer is 299.25 MiB (replay off) |
| R3 replay on | `BONSAI_8GB=1 BONSAI_RS_REPLAY=1` (the launcher's own sizing): RS buffer 156.77 MiB, the launcher's VRAM line 10,240 +- 256 cells above R2's 8 GB line, a short greedy answer equal to R2's 8 GB answer, 0 CUDA errors |
| R4 replay + saved conversations | `BONSAI_8GB=1 BONSAI_RS_REPLAY=1`, layer, slot folder: 3 turns of a 20k conversation (slot files 1, 2, 3), then two conversations that take turns (A2 and B2 each restore their own last save); 0 CUDA errors |
| R5 file compatibility | a slot file saved with replay off restores with replay on (turn 2 reads only its new tokens); a file saved with replay on, offered to a server with replay off, is refused and the request is still answered (it reads the conversation again); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

R3 as run could not check the line or the RS buffer: on this 12 GB card the 8 GB preset holds the whole window in
VRAM (no tier line), and the server's INFO lines (RS buffer) need `LLAMA_ARG_LOG_VERBOSITY=4`. R3b (declared before
its run): both arms with `BONSAI_TOTAL_MIB=8192` (the launcher sizes for an 8 GB card) and verbose server logs; the
same conditions as R3 (RS 299.25 -> 156.77 MiB, line +10,240 +- 256 cells, equal short answer, 0 CUDA errors).

R3b result: RS buffer 299.25 MiB (off) -> 156.77 MiB (on), equal answers, 0 CUDA errors; but no line: `BONSAI_TOTAL_MIB`
changes only the card size the preset sees, the line is sized from the real free VRAM. Also, R3's bound was
imprecise: the launcher spends the freed 142 MiB at its per-cell cost (14,336 B x 15/16 minus the sparse page bounds),
so the line grows by ~11,000-11,700 cells, not 10,240.

R3c (declared before its run): a ballast process (PyTorch) holds VRAM until ~7,600 MiB is free (an 8 GB card with the
desktop on it); the launcher's own sizing with `BONSAI_8GB=1`, replay off vs on: the line grows by 10,500 to 12,000
cells; each server starts, answers the short question with equal text, runs a 128k request with 0 CUDA errors, and
nvidia-smi free VRAM stays at 100 MiB or more during that request.

R3c result: void. Under the ballast (7,576 MiB free) the launcher sized the line to 66,560 cells (the 2060 SUPER with
the desktop sizes 80,640), and the replay-off arm itself spilled into system memory (17 MiB free, prefill 53 tok/s
instead of ~750): this card plus a second CUDA context does not stand in for an 8 GB card. Stopped.

## Decision: not published

R1, R2, R4 and R5 pass (R5: a file saved with replay off restores with replay on and continues identically; a file
saved with replay on is refused by an engine without replay, and the request is answered by reading the conversation
again). R3 passes on the RS buffer (299.25 -> 156.77 MiB) and equal answers, but its VRAM-line part cannot be checked on
this machine (the RTX 4070 holds the whole 8 GB window, and the ballast emulation spills). Per the declared rule the
bundle is not published until the line check runs on the RTX 2060 (R6 of docs/research/gdn-replay-20261018). The
staged zip stays at `artifacts/release/bonsai-bundle-win-x64-20261019.zip` (SHA-256
`91d3dd0dde56dbac93cf9b6b3762482d4195f4e3523e69dc0ff82a69b5c109be`).

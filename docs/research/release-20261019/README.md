# Release bundle-20261019 (replay rollback, opt-in)

Date: 2026-10-19. Engine release: `bin/` from the engine build at `5b79541ebb` (`serve/gdn-replay` = bundle-20261018f's
engine `a6d4fc698f` + patch 0070); every other file from `git archive` of the release commit 44fd1c4 (#201). What is new:
`BONSAI_RS_REPLAY=1` turns on replay rollback (the recurrent state keeps one plane instead of one per draft token,
142 MiB less VRAM; on the 8 GB preset the VRAM line grows by ~10,000 cells). Off by default: the default path gives
the same bytes as bundle-20261018f (`docs/research/gdn-replay-20261018`).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | the same entries as 1018f; changed: the engine `bin/` files, `start-server.ps1`, docs, `patches/0070`; the CUDA runtime DLLs identical; 0 text files with control bytes; `--version` reports `5b79541ebb` |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors; the RS buffer is 299.25 MiB (replay off) |
| R3 replay on | `BONSAI_8GB=1 BONSAI_RS_REPLAY=1` (the launcher's own sizing): RS buffer 156.77 MiB, the launcher's VRAM line 10,240 +- 256 cells above R2's 8 GB line, a short greedy answer equal to R2's 8 GB answer, 0 CUDA errors |
| R4 replay + saved conversations | `BONSAI_8GB=1 BONSAI_RS_REPLAY=1`, layer, slot folder: 3 turns of a 20k conversation (slot files 1, 2, 3), then two conversations that take turns (A2 and B2 each restore their own last save); 0 CUDA errors |
| R5 file compatibility | a slot file saved with replay off restores with replay on (turn 2 reads only its new tokens); a file saved with replay on, offered to a server with replay off, is refused and the request is still answered (it reads the conversation again); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

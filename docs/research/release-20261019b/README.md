# Release bundle-20261019b (8 GB: replay rollback and draft 2 / 2 by default)

Plan written before the runs. Engine: `serve/graph-log-once` (810d93e5aa) = bundle-20261019a's engine `a6d4fc698f` +
patch 0070 (replay rollback) + patch 0071 (the tiered-KV CUDA graph line once per state). Launcher: the 8 GB preset
turns replay on and drafts 2 / tail 2 by default (`BONSAI_RS_REPLAY=0` keeps 1 / 1); other cards are unchanged
(replay opt-in with `BONSAI_RS_REPLAY=1`).

Evidence for the 8 GB defaults, from the RTX 2060 SUPER (#138): P213 (replay: identical text, +10.5k positions in VRAM,
a soak), P214 (200k), P215 (2 / 2: 128k decode 26.1 -> 31.8 tok/s), P217 (the code-set gate: 21 / 24, 0 confident-wrong
changes against 1 / 1 and the rounding null); RTX 4070 with the 8 GB split: `../adaptive-mtp-20261019` AD2 (128k code
+19.6 %, quote +25.2 %). The staged release-20261019 (the same replay engine without 0071) passed R1, R4 and R5.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | the same entries as bundle-20261019a (bundles carry no `patches/`); changed: the engine `bin/` files, `start-server.ps1`, docs; the CUDA runtime DLLs identical; 0 text files with control bytes; `--version` reports `810d93e5aa` |
| R2 launcher | default (12 GB): spec 2 / 4, replay off (RS 299.25 MiB). `BONSAI_8GB=1` (layer on, slot folder): spec 2 / 2, replay on (RS 156.77 MiB). `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`: spec 1 / 1, RS 299.25 MiB. `BONSAI_TOTAL_MIB=24576`: health. Each: health ok, a short greedy answer, 0 CUDA errors |
| R3 graph line | `BONSAI_8GB=1`, the line pinned at 32,768, a 40k request: the `ggml_cuda_graph_check_compability` warning appears at most twice (once per state); 0 CUDA errors |
| R4 saved conversations | `BONSAI_8GB=1` (replay on by default), layer, slot folder: 3 turns of a 20k conversation (slot files 1, 2, 3), then two conversations that take turns (each turn 2 restores its own save); 0 CUDA errors |
| R5 file compatibility | carried over from release-20261019 (patch 0071 does not touch the slot code) |
| R6 speed, 12 GB | default, fresh server per depth, 4k and 32k quick_tps mean decode within 5 % of bundle-20261019a's fresh table (96.5 and 86.8) |

All pass: publish as the latest release. Any fail: no publish; log why.

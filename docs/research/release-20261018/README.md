# Release bundle-20261018 (patch 0067, 8 GB saves every 4096 tokens, save after the answer opt-in)

Date: 2026-10-18. Hardware: RTX 4070 12 GB. Engine: fork c5e73e7d81 (product 96f6e49cdc + patch 0067), release build
`tooling/build-release-20261007` (GGML_NATIVE off, AVX2, sm 75/86/89). Every other file: `git archive` of the release
commit. The layout and the CUDA runtime files: bundle-20261017b.

What is new for users:

- Patch 0067 (#183): a speculative draft stops at the end of the answer. The next turn of a conversation reuses the whole
  state after the answer, and the server no longer verifies draft tokens after the end.
- 8 GB preset: saved conversations save every 4096 new tokens (#182; RTX 2060 SUPER: restart turns -48.5 %, session
  -18.7 %).
- Opt-in `BONSAI_SLOT_CACHE_AFTER=1` (#184): save after the answer.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | the same file set as 1017b; the engine files report commit c5e73e7d81; `ggml-cuda.dll` / `ggml-cpu.dll` byte-identical to 1017b (a server-only patch); 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder set) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 0067 from the zip | `diag.py` (20k tokens, 10 turns, 8 GB preset): `cache_n` = the previous slot size on 9/9 turns; answers 10/10 the same as `diag_0067.jsonl` |
| R4 speed | `bench/quick_tps.py` 4k and 16k, 8 GB preset: decode within -3 % of 1017b at each depth |
| R5 8 GB GROW | with `BONSAI_8GB=1` and a slot folder, a 20k conversation of 3 turns through the layer saves at 4096 growth (the layer log shows a save on a turn that grew 4096-8191 tokens) |

All pass: publish as the latest release. Any fail: no publish; log why.

## Results (`release_1018.log`, `r3_diag.jsonl`)

Zip `bonsai-bundle-win-x64-20261018.zip`, 616,677,417 bytes, SHA-256
`f8347f4e9ba8fa7786ec0702fcddd2b34f46bd58814d21b9550e2a9bbdc7b169`.

| Gate | Result |
|---|---|
| R1 zip | PASS: 67 entries, the same set as 1017b; engine commit c5e73e7d81; `ggml-cuda.dll` and `ggml-cpu.dll` byte-identical; changed: README, `start-server.ps1`, `docs/8GB.md`, the two layer files, and the engine files that carry the commit; 0 control-byte files |
| R2 launcher | PASS: default (q4_0), 8 GB (q3_0, layer on, slot folder), 24 GB (q8_0): each answers "Red, blue, and yellow."; 0 CUDA errors |
| R3 0067 | PASS: full reuse after the answer on 9 of 9 turns; answers 10/10 the same as `diag_0067.jsonl` |
| R4 speed | PASS: 4k 88.6 -> 88.6 tok/s, 16k 93.4 -> 93.7 tok/s (1017b -> 1018) |
| R5 8 GB GROW | PASS: turns that grew ~7,100 tokens saved each time (1, 2, 3 slot files; with 8192 turn 2 would not save) |

All pass: published as `bundle-20261018`.

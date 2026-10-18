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

# Release bundle-20261018c (delta saves)

Date: 2026-10-18. Engine: fork a6d4fc698f = product 96f6e49cdc + 0067 + 0068 + 0069 (delta slot saves), release build
`tooling/build-release-20261007` (GGML_NATIVE off). Every other file: `git archive` of the release commit 99fdd46 (#189).
Layout and CUDA runtime files: bundle-20261018b.

What is new: a save after the answer writes only the tokens since the last save (a delta; a full save every 8). On the
dev drive the full save of a 173k state took 70.6 s, a delta 0.08 s; G1 with think time: mean wait -44 %, normal turns
-56 %, answers = the cache-off reference 30/30 (`docs/research/delta-saves-20261018`).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | the same file set as 1018b; engine commit a6d4fc698f; `ggml-cuda.dll` / `ggml-cpu.dll` byte-identical to 1018b; 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 exact | `d1_test.py` at 20k from the zip (8 GB preset): the chain restore gives the same answer, `prompt_n` and `cache_n` as the full-file restore |
| R4 speed | `bench/quick_tps.py` 4k and 16k, 8 GB preset: decode within -3 % of 1018b |
| R5 default | `BONSAI_8GB=1`, layer, slot folder, no cache variables: `/props` says `slot_save_delta: true`; a 5-turn 20k conversation through the layer leaves at least one delta (an index entry with a parent); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

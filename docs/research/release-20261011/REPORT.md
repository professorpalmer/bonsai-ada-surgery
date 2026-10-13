# Report

## Bottom line

- **The tier prefetch never ran with CUDA graphs on.** `ggml_cuda_tier_graph_begin(..., enable = !use_cuda_graph &&
  ...)`: the copy-engine prefetch of the next attention op's host rows (patch 0041) was off whenever the graph ran as
  a CUDA graph, and the launcher keeps CUDA graphs on. Past the VRAM line, each attention op waited for its own copy.
- **Patch 0053** turns CUDA graphs off only for graphs whose attention reads the host tail. Graphs below the line keep
  them. One WARN line per switch; `GGML_CUDA_KV_TIER_GRAPHS=1` keeps the old behaviour.
- **Result:** RTX 4070, 12 GB recipe: 192k 23.6 -> 29.4 (+25 %), 250k 12.7 -> 14.6 (+15 %), 192k lookup off 19.8 ->
  25.0 (+26 %) tok/s; 4k-128k unchanged. RTX 2060 SUPER, 8 GB recipe: 128k +16 %, 192k +9 %, 245k +8 %; 4k / 32k
  unchanged. HumanEval 164 on the release binaries: all 164 outputs identical.
- **PrismML #346** (a crash on PrismML's engine with prompt checkpoints) was a scratch-size mismatch between a
  short-query route (PrismML #189) and the in-place K/V path (our PrismML #221). Fixed in PrismML #350. The Bonsai
  engine does not have that route.

## Promoted

- Patch 0053 into the next bundle: done, bundle-20261011 published 2026-10-13 (GitHub release and HF; SHA-256 f8899cbf...da8bf8 checked on both).

## Not promoted

- `LLAMA_ARG_KQ_MASK_PACKED=0` (f16 mask): no gain alone (R01).

## Order of the work

1. R01: the depth research's sparse arms ran with CUDA graphs off and a dense "fair" arm beat the shipped settings
   (`../depth-20261010/`, D-entries on sparse speed). Isolating the two differences on the release bin found the gain
   was graphs off alone.
2. R02: reading the source gave the cause; the patch is 40 lines in `ggml-cuda.cu`.
3. R03-R07: the gates on both cards, then the release build, stack verify and smoke.
4. R08: PrismML #346 came in mid-way (issues first) and took priority until the fix PR was open.
5. R09: the Mirai engine has the same gating; the patch applies cleanly (results in the Mirai repo).

## Lessons

- **A "fair" baseline can hide a product win.** The graphs-off arm was meant to make sparse comparable; its gain over
  the shipped arm was the real finding. Always run the shipped arm next to any "fair" arm.
- **Server logs drop ggml INFO lines.** The switch line and the op-timing tables were invisible until WARN.
- **Test the release binaries, not a dev root.** The first two gate-2 attempts on the unzipped bundle failed on the
  harness (no `models\`, then a fresh API key), not on the engine; both were fixed in `bench/he_template_one.sh`.
- **Out-of-bounds writes need not crash.** #346 never faulted on the 4070; an assert on the reservation made it
  visible without a sanitizer.

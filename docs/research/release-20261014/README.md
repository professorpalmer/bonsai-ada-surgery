# Release research, 2026-10-14: sparse host-tail reads (patch 0055, 8 GB)

How patch 0055 (sparse host-tail reads for tiered KV decode, PR #56) and the 8 GB launcher preset (PR #49) go to a
bundle. Kernel research: D16-D24 in `../depth-20261010/`; the 2060 side: P105-P133 in `../depth-8gb-20261006/`.
Read `REPORT.md` first (when it exists); one entry per step in `EXPERIMENTS.md`.

## Gates (written here before the runs, 2026-10-14 03:15)

**Decision 2026-10-14 07:20 (after P127, #21): sparse is opt-in for 0055 (`BONSAI_SPARSE=1`, launcher #49 `d927d6b`).**
With the page-bound reserve the VRAM line moves down and 64k decode is about 8 % slower on 8 GB (P127, int8 bounds),
so default-on missed the 5 % rule. Default off = no reserve and no change below the line; the deep sessions opt in
(1.9x at 160k, 2.3x at 245k, R05). A reserve without a line cost is D26 (next bundle). R04 / R05 below forced sparse
on by environment, which is the opt-in path, so they stand; R06 on the 2060 runs the default-off check plus the
`BONSAI_SPARSE=1` deep arms.

The budget rule inside sparse was decided by D23 (per-head normalized page ranking at B 8192) and D24 (page-rank trace):
NORM on if D23 passes at 245k, else the budget fraction (`GGML_CUDA_FA_SPARSE_FRAC=0.0625`, B = max(8192, host tail /
16)). Every gate runs on the bundle's own binaries with the default switches of the bundle's launcher.

| Gate | Card | Pass when |
| --- | --- | --- |
| R01 op tests | 4070 | `FLASH_ATTN_EXT` and `GATED_DELTA_NET` 0 FAIL |
| R02 12 GB same text | 4070 | HumanEval 164 at medium on the bundle's binaries: the same 164 answers as bundle-20261013 (sparse is off by default on 12 GB, so the engine path is unchanged) |
| R03 12 GB speed | 4070 | prefill and mean decode at 4k / 32k / 128k within 2 % of bundle-20261013, same session, memory clock noted |
| R04 8 GB-like quality | 4070 | line 32,768, default sparse switches: 160k and 245k copies 10/10 and needles 12/12; if FRAC is the default, also 200k copies 10/10 |
| R05 8 GB-like speed | 4070 | sparse mean decode at 160k and 245k at least 1.8x dense, same session. **Amended 2026-10-14 07:18, before R05b runs:** for the opt-in mode with the launcher floor B 12288, 160k at least **1.5x**, 245k at least 1.8x, 200k reported as measured (no gate) |
| R06 8 GB release check | 2060 | the tester's release-style check with the bundle zip and launcher: SHA, op tests, 4k-128k within 3 % of bundle-20261013 (same session), 160k / 245k at least 1.8x dense, 245k copies and needles equal to dense, fresh 60k, 0 one-token answers, minimum free at least 60 MiB, HumanEval on the bundle's binaries |
| R07 publish | - | R01-R06 pass: zip from the release commit, GitHub release, Hugging Face, SHA on both, bins installed |

A result that misses a gate stops the publish; its entry says why and what changes.

**Gate amendment (2026-10-14 07:18, before R05b).** R04 failed at 200k with FRAC 1/16 alone, so the launcher floor became B 12288
(#49 `dfc994e`). That floor raises the 160k budget from 8192 to 12288 and lowers 160k decode. Quality is the hard
constraint, and the copy data is thin (10-20 items per depth), so the kernel session declared the 160k speed gate for
the opt-in mode as at least 1.5x (245k stays at 1.8x), instead of a depth-dependent floor tuned to one 10/10 sample.
D25 (per-layer budget) is the planned route to win 160k speed back without a quality loss.

## Engines

- Patch 0055 candidate: fork `product-0055` `5782626102` (= `c8bbb1898` tree) plus the default chosen after D23 / D24
  (NORM `8d6e0d3f4`, or FRAC `6dddfd6f0`); squashed into 0055 by the kernel session before the release build.
- Base: bundle-20261013 (`de873117e1`, 54 patches).

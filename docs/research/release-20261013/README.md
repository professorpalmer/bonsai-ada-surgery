# Release research, 2026-10-13: chunked gated-delta-net prefill (patch 0054)

How patch 0054 (chunked gated-delta-net MMA prefill, port of ggml-org/llama.cpp#29353) goes from a merged patch to
a bundle: the late device check, the release build, the gates, and the publish. RTX 4070 12 GB, 12 GB recipe, unless
an entry says otherwise. Read `REPORT.md` first; one entry per step in `EXPERIMENTS.md`, one JSON line per entry in
`runs.jsonl`. The kernel research itself is D14 in `../depth-20261010/`.

| Path | What |
| --- | --- |
| `REPORT.md` | Bottom line, decisions, lessons, open items |
| `EXPERIMENTS.md` | One entry per step, G01-G08 |
| `runs.jsonl` | One JSON line per entry: id, date, hw, engine, script, question, arms, gate, verdict, receipts, gpu_h |
| `../../../patches/0054-*.patch` | The change (PR #40) |
| `../depth-20261010/` (D14) | The kernel port, the prefill A/B, the "did it engage" lesson |
| `../../receipts/release_0054.log` | The gate log (G05-G07) |

## Gates (written here before the runs)

The gates for G05-G07 are fixed in this file before `queue-0054` reaches them (2026-10-13 18:00). A result that
misses a gate stops the publish; the entry then says why and what changes.

| Gate | Pass when |
| --- | --- |
| G05 op tests | `test-backend-ops -b CUDA0`: `GATED_DELTA_NET` 55/55, `FLASH_ATTN_EXT` 3007/3007 (as for 0053), 0 FAIL |
| G06 HumanEval | 164 at medium, greedy, `bench/he_template_one.sh` with `HE_ROOT=/tmp/root-0054`: at least 157/164 (D14 gave 158 against 160; the kernel changes the float order, so the same-text gate of 0053 does not apply) |
| G07 speed | `bench/depth_arms.sh bench/arms/release_0054.txt` at 4k / 32k / 128k, 0053 bin vs 0054 bins: prefill not slower at any depth (D14: +3-6 %), mean decode within 2 % of 0053 |

The perplexity gate (G01), the RTX 2060 check (G02) and the device-check op test (G03) ran before this folder; their gates were declared in chat and
on PR #40.

## Engines

- Release candidate: PrismML `adfffbe` + 54 patches = fork `product-0054` `de873117e1`, tree `165e10e3` (main
  `a698946eb`, PR #40). An earlier `product-0054`, `e63ce36d9`, had the device check after the temporaries; it was
  force-pushed over.
- Before: bundle-20261011, `90ca41e40` (53 patches), the product `bin/` since 2026-10-13.
- Release build: `tooling/build-release-20261007` (not in git), CUDA archs `75-real;86-real;89-real;89-virtual`;
  test root `/tmp/root-0054` = the bundle-20261011 layout with the 0054 bins.

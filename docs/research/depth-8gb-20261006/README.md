# 8 GB research, 2026-10-06 to 2026-10-14 (ongoing)

How to make Bonsai 2 27B (PTQ1_0 ternary, 48 gated-delta-net + 16 attention layers, MTP head) fast, correct and stable on
one 8 GB card, to the end of its 262,144-token window. All runs on one RTX 2060 SUPER 8 GB (Turing, sm_75, PCIe 3.0)
with the Windows desktop on the same card, unattended, from a job queue. Each experiment (P1 to P126b; P119, P120,
P124, P125 and P127-P132 open) has a plan and a gate written before its result; the timestamped plan is in
`NOTEBOOK.md` before the result entry.

The companion folder `../depth-20261010/` (RTX 4070 12 GB, D01-D17) has the 12 GB side of the depth work: the sparse
host-tail reads and tier-graphs were built there and checked here on 8 GB (P101-P107).

Read `REPORT.md` first. For a single experiment, read `experiments/P###.md`. For the levers we can reuse on the next
model, read `TOOLBOX.md`.

P133 to P155b (2026-10-14 to 2026-10-16: driver 610.88, the sparse opt-in release bundle-20261014, q3_0 by default in
bundle-20261015 / 15b / 15c, automatic sparse in bundle-20261016 and the 8 GB card, the cold read-in work on #138) are in
[`experiments/index-p133-p155.md`](experiments/index-p133-p155.md) and
[`experiments/events-p133-p155.md`](experiments/events-p133-p155.md). P149b, P152, P155 and P155b were open (pending
or running) when that range was written. `REPORT.md` is not updated for this range yet.

P156 to P161 (2026-10-16: T2a-2 and bundle-20261016b with the Turing prefill tiles, the saved-conversation restore
crash on 8 GB and its cause in the shared CUDA pool, the 0060p pool fix, T3 kept opt-in, the 200k demo clip, the layer
cache PR #157) are in [`experiments/index-p156-p161.md`](experiments/index-p156-p161.md) and
[`experiments/events-p156-p161.md`](experiments/events-p156-p161.md), E57-E66. The P155 / P155b results were added to
[`experiments/P155.md`](experiments/P155.md). `REPORT.md` is not updated for this range yet.

P162 to P168 (2026-10-16 to 2026-10-17: read ahead (T1-d) on the 2060, the post-zip check of bundle-20261017
(release-0062: saved conversations on every card), a 30-turn soak and the demo clip on the served bundle, the spill
guard G4 / G5 tests with the forward-slash fault that made three runs void, the VRAM line 86,784) are in
[`experiments/index-p162-p168.md`](experiments/index-p162-p168.md) and
[`experiments/events-p162-p168.md`](experiments/events-p162-p168.md), E67-E75. `REPORT.md` is not updated for this
range yet.

| Path | What |
| --- | --- |
| `REPORT.md` | Bottom line, what shipped, what was rejected, results by day, open items |
| `TOOLBOX.md` | Every lever, method and tool: how to turn it on, measured effect on 8 GB, status, model-specific or general |
| `experiments/P###.md` | One record per experiment: setup, frozen gate, method, every number, deviations, verdict, later corrections, what it changed |
| `experiments/index-*.md` | One row per experiment |
| [`experiments/index-p133-p155.md`](experiments/index-p133-p155.md) | P133-P155b (events: [`experiments/events-p133-p155.md`](experiments/events-p133-p155.md), E38-E56) |
| [`experiments/index-p156-p161.md`](experiments/index-p156-p161.md) | P156-P161 (events: [`experiments/events-p156-p161.md`](experiments/events-p156-p161.md), E57-E66) |
| [`experiments/index-p162-p168.md`](experiments/index-p162-p168.md) | The latest range: P162-P168 (events: [`experiments/events-p162-p168.md`](experiments/events-p162-p168.md), E67-E75) |
| `runs.jsonl` | One JSON line per experiment: id, date, card, engine commit, script, env, metrics, verdict, receipts (same fields as `../depth-20261010/runs.jsonl`, for comparing future models and engines) |
| `experiments/events-*.md` | Entries that are not experiments: incidents, rig baseline changes, releases, PRs, coordination, decisions |
| `NOTEBOOK.md` | The full lab notebook, in time order, unchanged (plans, results, corrections, incidents) |
| `scripts/` | Every script that ran an experiment: `pNN.sh`, `queue/NN-pNN-*.sh` (queue jobs), probes (`*.py`), `benchx/`, launch helpers (`serve.ps1`, `run_arm.sh`, `stop.ps1`), queue runner and fillers, Afterburner profile tools, the CPU attention bench |
| `results-raw.zip` | Every receipt (1,120 files): `receipts/pNN/` summaries, per-run JSON lines, server command lines, text compares. The API key is redacted |
| `releases/` | Release notes of the 8 GB bundles checked on this card |
| `drafts/` | PR, issue and reply texts sent upstream (PrismML #325, #330, #314, #317, #338 and others) |

Not included: one 2 GB KL logits dump (`receipts/p8c/kl_base_bundle_soa_f16_ub1.bin`, regenerate with `p8_build_ab.sh`),
server stdout/stderr logs (557 MB; the lines each experiment used are in its receipts), and binaries.

## The card and the method

- RTX 2060 SUPER 8 GB, Windows 11, desktop on the card (1280x1024 from 2026-10-06 21:05), remote access by Chrome
  Remote Desktop (~8 MiB GPU). Fan fixed at 100 % from 2026-10-06 21:41 (Afterburner slot 5). Clocks are stock
  unless a record says otherwise. Memory +1000 MHz is a documented opt-in (P42: +2.5 % drafting decode); +1250
  faulted the GPU and +1500 crashed the PC (P38, P39b). The clock is never changed while a server runs (P39c).
- 32 GB RAM. 16 GB machines are simulated with committed ballast (`scripts/ballast.py`).
- A/B arms run on the same binary where possible, alternated in order, with fixed prompts. Texts are compared only
  within one session history (P92 to P94: the lookup drafter's history changes near-tie tokens).
- Engine: fork `professorpalmer/llama.cpp-ada-ternary`; each record names its branch and commit. Launcher and patch
  stack: this repo (`start-server.ps1`, `patches/`).

## Running it again

The scripts ran from `C:\bonsai\8gb\` (rig folder) with the repo at `C:\bonsai\bonsai-ada-surgery\` and the API key at
`artifacts/api_key.txt` in the repo. Jobs were queued as files in `queue/pending/` and run one at a time by
`scripts/queue_runner.sh` under a Windows scheduled task (a shell started from the app dies with the app). To rerun
one experiment: build the engine commit its record names, copy the bin dir its record names, start the server with
the launcher and variables in its record (or its `scripts/` file), then run the probe it names, e.g.
`python scripts/benchx/quick_tps.py`, `python scripts/realtext_probe.py`, `python scripts/deep_soak.py`.

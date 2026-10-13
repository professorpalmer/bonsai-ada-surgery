# Thinking length research, 2026-10-10 to 2026-10-13

Why Bonsai thinks long on some coding requests, and whether a change to the chat template or the thinking budget can
cut that without hurting agent work. RTX 4070 12 GB, 12 GB recipe, raw server (layer off), greedy. Read `REPORT.md`
first; one entry per experiment in `EXPERIMENTS.md`, one JSON line per experiment in `runs.jsonl`.

| Path | What |
| --- | --- |
| `REPORT.md` | Bottom line, what was rejected, lessons |
| `EXPERIMENTS.md` | One entry per experiment, TH01-TH14 |
| `runs.jsonl` | One JSON line per experiment: id, date, hw, engine, script, question, arms, gate, verdict, receipts, gpu_h |
| `../../receipts/he_template_ab.log` | Every HumanEval run here (one header line and the summary per run) |
| `../../receipts/tool_template_ab.log`, `../../receipts/budget_agent_ab.log` | The agent-side runs |
| `../../QUALITY.md` | The user-facing summary (section 2, "Thinking length and the system turn") |

## About the gates

The gates were declared in the session chat before each run, not frozen in a plan file. HumanEval: "the same score
(160/164 +- noise) with fewer tokens". Agent side: "the same workspace score (13/15) as the product". Each entry says
which gate applied.

## Setup common to all entries

- HumanEval 164, `bench/humaneval_run.py --arm medium` (thinking on, effort medium), `--max-tokens 24576`, greedy,
  through `bench/he_template_one.sh` (one server per arm; the server's own render of a HumanEval-style request is
  saved next to the results).
- Agent work: `suite/run_suite.py` with `bench/plans/tools_workspace.json` (5 workspace tasks x 3 seeds), plus
  `bench/toolcall_stress.py --n 6`.
- Engine: the bundle-20261010 engine (`2cadbfb64`) for TH01-TH13, bundle-20261011 (`90ca41e40`) for TH14. Patch
  0053 only changes the CUDA graph choice when attention reads the host KV tail; these prompts stay in VRAM.
- The community template in TH01-TH02 (a third-party "terse" template, v22.4) stays local; only its effect is recorded.

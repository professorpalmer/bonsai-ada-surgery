# Quality research, 2026-09-29 to 2026-10-01

What makes Bonsai 2 27B (PTQ1_0, 1.58-bit) answer correctly more often, measured on one RTX 4070 with paired runs
and gates frozen before results. Read `REPORT.md` first; `DECISIONS.md` is the append-only log with every plan
hash, result and correction.

| Path | What |
| --- | --- |
| `REPORT.md` | Results by round, what was promoted and what was rejected |
| `DECISIONS.md` | Chronological log: hypotheses, frozen plans (sha256), outcomes, corrections |
| `bench/*.py` | Runners and task generators (puzzles, tool workspaces, regex loops, agentic contract tasks, proxy checks) |
| `bench/*-plan.json` | The frozen plan of every experiment |
| `bench/*.log` | One JSON line per run (the summary each analysis was computed from) |
| `results-raw.zip` | Every raw request/response/trajectory (505 files) |
| `serve-arms/` | Pinned server launch arms (A / B / KV / teacher), switch scripts, receipts |
| `layer/` (snapshot of the sandbox / proxy / cards / linter code; the working copy is in the gitignored `tooling/`) | `wasi-python/sandbox.py` (WASI sandbox + canaries), `interpreter_proxy.py`, `apicards.py`, `apilint.py` |

## Running it again

The scripts were run from `artifacts/quality-20260929/bench/` (gitignored working area) and use paths relative to
that location: the API key at `artifacts/api_key.txt`, the sandbox at `tooling/wasi-python/`, and for the agentic
contract tasks the frozen prompts/oracles from the Mac evidence bundle unpacked at
`artifacts/quality-20260929/evidence/` (not in this repo). To reproduce: copy `bench/` to
`artifacts/quality-20260929/bench/`, run `tooling/wasi-python/fetch_runtime.ps1` once (downloads the WASI Python,
verifies its checksum, runs the 12 isolation canaries), start the server with `serve-arms/switch.ps1 -Arm A`
(copy `serve-arms/` to `artifacts/experiments/spec-ab-20260928/`), then
`python run_puzzles.py --plan H2-plan.json --out H2` and so on.

Model-written code is only ever executed inside the WASI sandbox (no host files, network or processes).
The teacher reference needs `Qwen3.8-27B-UD-Q4_K_M.gguf` (unsloth, sha256 `322e194f...3482`) in `models/donor/`.

# Long-exact-work suite

A small, self-contained benchmark for the capability that single-turn reasoning benchmarks miss and that aggressive
weight compression loses first: long, exact work. It was built while diagnosing Bonsai 2 27B (1.58-bit) against its
teacher; see `research/quality-20260929/REPORT.md` for what it found. It runs against any OpenAI-compatible chat
endpoint and can pair two endpoints request by request (for example a raw server and the same server behind the
Bonsai layer, or two quantizations of one model).

## What it measures

| family | tasks | what fails when it fails |
| --- | --- | --- |
| coding | three contracts: a gzip-compressed POSIX tar bundle, a canonical ZIP archive, a MIME email with attachments. The model writes `solution.py` with `write_file` and tests it with `run_python` (12 responses), then hidden requests are graded by properties of the output (never by byte equality with a reference) | recall of exact standard-library APIs; the habit of hand-rolling binary formats; finishing with a solution that fails even the given example |
| computation | single requests with brute-force integer truths: 0/1 knapsack (13 items), digit-constrained counting, LCS count; and two data questions over a 150-200 row table or a 200-line web log | per-step reliability over 20k-40k tokens of bookkeeping; retyping data into code |
| workspace | tool-using data tasks graded on the final state (invoice, dedupe, ledger, a chained lookup, a byte-exact copy) | exact copying through tool calls; multi-step state |

Every grader is deterministic. Reference solutions pass every hidden request and negative controls fail
(`python suite/cases.py`). Model-written code runs only inside the WASI sandbox from `layer/` (no host files, no
network, no processes, memory and time capped).

## Run

```powershell
layer\fetch_runtime.ps1                      # once: the sandbox runtime (checksummed) + wasmtime; runs the canaries
python suite\run_suite.py --base http://127.0.0.1:18080 --key-file artifacts\api_key.txt --out suite-out
```

Paired, raw server vs the layer in front of it:

```powershell
python suite\run_suite.py --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --label-a raw --label-b layer --out suite-out
```

`--limit 1` runs one item per family as a smoke test. Results go to `results.jsonl` (one line per run), full traces
(every tool call, tool result, file written, and the model's reasoning text) to `traces/`, and a `scoreboard.md`
with per-task counts and, in paired mode, rescues/losses per task. The default plan is 12 coding runs, 15 computation
runs and 10 workspace runs per endpoint, about 3 GPU-hours on an RTX 4070 for a 27B.

## Reading the numbers

Pair by request and count rescues and losses; do not compare totals across machines or settings. Declare a gate
before running (the project used "at least 2-4 rescues and 0-1 losses" per experiment) and report whether it was
met. The sets are small by design (a gate, not a leaderboard): a result on 3-4 seeds per task is a development
signal, and anything within one rescue of its gate should be rerun with fresh seeds before it is believed.

Reference runs of this suite itself (2026-10-03): Bonsai 2 27B PTQ1_0 on one RTX 4070, raw llama-server vs the
same server behind the Bonsai layer. Two independent seed sets, 74 runs each.

Pooled: raw **34/74**, layer **57/74**; 26 rescues, 3 losses; tokens 0.70x. The two draws agree (layer 28/37 and
29/37; raw 17/37 both), which is about the spread to expect from one run of the default plan.

Seed set 1 (default plan):

| family | task | raw | layer | rescues / losses (B vs A) |
| --- | --- | ---: | ---: | --- |
| coding | suite-tar-01 | 0/4 | 2/4 | 2 / 0 |
| coding | xfer-mime-01 | 1/4 | 1/4 | 1 / 1 |
| coding | xfer-zip-01 | 1/4 | 4/4 | 3 / 0 |
| computation | digits | 0/3 | 3/3 | 3 / 0 |
| computation | knapsack | 3/3 | 3/3 | 0 / 0 |
| computation | lcs | 0/3 | 2/3 | 2 / 0 |
| computation | sales | 1/3 | 3/3 | 2 / 0 |
| computation | weblog | 3/3 | 3/3 | 0 / 0 |
| workspace | chain | 2/2 | 2/2 | 0 / 0 |
| workspace | copy | 1/2 | 1/2 | 0 / 0 |
| workspace | dedupeH | 2/2 | 1/2 | 0 / 1 |
| workspace | invoiceH | 2/2 | 2/2 | 0 / 0 |
| workspace | ledgerH | 1/2 | 1/2 | 0 / 0 |
| **total** | | **17/37** | **28/37** | **13 / 2** |

completion tokens: raw 777,825, layer 572,550

Seed set 2 (`S2-plan.json` in the research bench: coding seeds 5-8, computation 4-6, workspace 3-4):

| family | task | raw | layer | rescues / losses (B vs A) |
| --- | --- | ---: | ---: | --- |
| coding | suite-tar-01 | 0/4 | 4/4 | 4 / 0 |
| coding | xfer-mime-01 | 1/4 | 0/4 | 0 / 1 |
| coding | xfer-zip-01 | 1/4 | 3/4 | 2 / 0 |
| computation | digits | 1/3 | 3/3 | 2 / 0 |
| computation | knapsack | 2/3 | 3/3 | 1 / 0 |
| computation | lcs | 0/3 | 3/3 | 3 / 0 |
| computation | sales | 2/3 | 3/3 | 1 / 0 |
| computation | weblog | 3/3 | 3/3 | 0 / 0 |
| workspace | chain | 2/2 | 2/2 | 0 / 0 |
| workspace | copy | 1/2 | 1/2 | 0 / 0 |
| workspace | dedupeH | 2/2 | 2/2 | 0 / 0 |
| workspace | invoiceH | 2/2 | 2/2 | 0 / 0 |
| workspace | ledgerH | 0/2 | 0/2 | 0 / 0 |
| **total** | | **17/37** | **29/37** | **13 / 1** |

completion tokens: raw 870,344, layer 586,105

Workspace requests carry their own tools and pass through the layer untouched (all 10 pairs identical in set 2,
9 of 10 in set 1; the odd one is sampling noise between two runs of an identical request). The losses are MIME
swaps at the model's floor and that one workspace pair.

## Requests

Per request: temperature 1.0, top-p 0.95, top-k 20, min-p 0.05, `reasoning_effort` medium, `reasoning_budget_tokens`
20480 (honoured by this repo's llama.cpp fork; other servers ignore it, so their thinking is capped only by
`max_tokens`, which makes token counts across servers not comparable; correctness still is). Seeds are fixed per
item. The chat template is whatever the server applies; for cross-model comparisons use the same template file.

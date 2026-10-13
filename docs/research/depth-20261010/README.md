# Depth research, 2026-10-10 to 2026-10-11

Speed at 128k-262k context, where the KV cache tail lives in pinned system RAM: why decode and prefill slow down,
what moves them, and what does not. One RTX 4070 12 GB (PCIe 4.0) for most runs; the RTX 2060 SUPER 8 GB runs are on
issue #21 and #22. Read `REPORT.md` first. Every experiment has an entry in `EXPERIMENTS.md` (question, gate, setup,
result, verdict, receipts) and one line in `runs.jsonl` (machine-readable, for comparing future models and engines).
`OUTSIDE.md` summarises the outside work (papers, other engines' techniques) that shaped the plan.

| Path | What |
| --- | --- |
| `REPORT.md` | Bottom line, what was promoted and what was rejected, the order of the work |
| `EXPERIMENTS.md` | One entry per experiment, D01-D18 |
| `runs.jsonl` | One JSON line per experiment: id, date, engine commit, script, env, metrics, verdict, receipts |
| `OUTSIDE.md` | Techniques from papers and other projects that were considered, and why each was tried or not |
| `../../receipts/` | The raw run logs named in each entry (one line per request or per arm) |
| `../../../bench/` | The scripts named in each entry |
| `../../DEPTH.md` | The user-facing summary of the same work |

## About the gates

Gates were declared before results, in chat, in the issue threads or in the scripts' header comments, but not frozen
in a plan file as in `docs/research/quality-20260929/`. Each entry says where its gate was declared, or that a run was a
measurement without a gate. That is weaker than a frozen plan; future rounds should write `<ID>-plan.json` first.

## Engines

All experiment engines are on the fork (`professorpalmer/llama.cpp-ada-ternary`), on top of the release engine
`2cadbfb64` (PrismML `adfffbe` + 52 patches): branch `fa-sparse-proto` for the sparse work and `gdn-chunked` for the
gated-delta-net prefill. Each entry names the exact commit. Test roots were copies of the release bundle with the
experiment's `ggml-cuda.dll` (and `test-backend-ops.exe`) in `bin/`, named `root-sparse2` ... `root-sparse11` and
`root-gdn` / `root-gdn2` in the entries; they were local and are not kept.

## Running it again

Start from a bundle checkout, build the named commit (`cmake --build ... --target llama-server test-backend-ops`,
`-DCMAKE_CUDA_ARCHITECTURES=89-real` for the 4070), copy its `bin/` over a copy of the bundle, then run the entry's
script from the repo root with the root path, for example `bash bench/sparse_prefill.sh <root>`. The scripts start
`tools/ramguard.ps1` (kills `llama-server` / `llama-perplexity` when free memory gets low) and stop the server at the
end. The retrieval tests need `artifacts/eval/pycode.raw` (Python standard library sources) and the API key at
`artifacts/api_key.txt`.

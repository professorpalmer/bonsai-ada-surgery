# DSpine drafter research, 2026-11-12

Does the DSpine block drafter (`tencent/Qwen3.8-27B-DSpine-b16`) make Bonsai 2 27B (PTQ1_0) decode faster than the
MTP head that the bundle uses, on one RTX 4070 12 GB? Issue #258 (idea from Milor123). Read `REPORT.md` first.

| Path | What |
| --- | --- |
| `REPORT.md` | Bottom line, the result table, decisions, lessons, open items |
| `DS1-plan.json` | The plan and the gate, written before the first GPU run |
| `runs.jsonl` | One JSON line per experiment (DS0a-c load checks, DS1a-c per depth): speeds, draft counts, VRAM, verdict |
| `receipts/` | Raw bench output (`cells.jsonl`), full texts (`texts.jsonl`), `table.md` (per cell), server log excerpts, `ds0-load-checks.txt` |
| `bench/dspine_bench.py` | The runner: one fresh server per cell, code and prose prompts, server timings |
| `bench/make_arms.py`, `bench/DS1-arms.json` | The concrete server arguments of every arm (`bt` was added by hand: `b` with `--chat-template-file`) |
| `bench/one_shot.ps1`, `bench/graft_target_tensors.py` | The DS0 load checks; the head graft |
| `bench/summarize.py`, `bench/gpu_free.sh` | The per-cell table; the shared-GPU check before each GPU phase |

## Engine

Fork `professorpalmer/llama.cpp-ada-ternary`, branch `research/dspine`: the bundle-20261105 engine (`21fd9beda`)
plus the DSpine part of the open upstream PR ggml-org/llama.cpp#31941 and the DFlash causal-attention flag from
upstream (DSpine drafts are block-causal; the engine had only non-causal DFlash). Built for sm_89. Every arm in this
folder uses the same binary, also the no-draft and the MTP arms.

## Draft files

`convert_hf_to_gguf.py <DSpine dir> --target-model-dir <Qwen3.8-27B dir> --outtype bf16` from the branch above
(the converter reads only the target's config and tokenizer files, not its weights), then `llama-quantize` to
`q8_0` and `q4_0`. A DFlash draft without its own head uses the target's token embeddings and output head; its own
code book (1024 x 248,320) is in the file. On Bonsai 2 the ternary head breaks the drafts (REPORT, DS0), so the speed
arms use files with the Qwen3.8-27B output head (Q6_K) added: `bench/graft_target_tensors.py <draft> <Qwen3.8-27B gguf>
<out> output.weight`.

## Running it again

Build the branch (`--target llama-server llama-quantize`), make the two draft files, run
`python bench/make_arms.py DS1-plan.json bench/DS1-arms.json` after you edit the paths in `DS1-plan.json`, then
`python bench/dspine_bench.py --plan bench/DS1-arms.json --cells a:1500,b:1500,... --out cells.jsonl
--texts texts.jsonl --logdir logs`. The runner needs `artifacts/eval/pycode.raw` and `artifacts/eval/wiki.test.raw`
(filler text) and stops if a `llama-server` already runs.

Local paths in the plan, the arms file and the receipts are replaced by `<repo>`, `<engine-bin>`, `<draft-dir>` and `<this-folder>`.

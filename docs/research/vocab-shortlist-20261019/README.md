# A draft vocabulary shortlist for the MTP head (2026-10-19)

Plan written before the runs. One entry per run goes to `EXPERIMENTS.md`, one line per run to `runs.jsonl`.

## Question

Each MTP draft step scores all 248,320 rows of the output head, and with a fixed draft of 2 / 2 (AD2 in
`../adaptive-mtp-20261019`, the proposed 8 GB default with replay) a token takes two draft steps. A shortlist of the
tokens the model actually writes lets a draft step read about a tenth of the head. Does that make decode faster without
lower draft acceptance? The target model verifies every token with the full vocabulary, so the answers can change only
through the verify step's rounding, as with any change of draft size.

## Engine

`serve/draft-vocab` on the engine fork = `serve/graph-log-once` (patches 0070 + 0071) + `--spec-draft-vocab-map`
(`LLAMA_ARG_SPEC_DRAFT_VOCAB_MAP`). Design from zgsndzq/llama.cpp-qwen38-flash (MIT): the MTP draft context keeps a
compact copy of the shortlisted rows of the head in the head's own format, so one matmul reads only those rows; the
backend sampler maps its picks back to token ids (the shortlist ids are its candidates). The activation takes the head's
Hadamard fold first. Without draft backend sampling, or with a per-row head scale, the draft keeps the full head. Only
the static map is ported (no adaptive part).

## Our shortlist

We make our own map; we do not use the reference's map. Token counts over:

- model output: the saved HumanEval answers of this serve (`artifacts/humaneval-*/samples.jsonl`, about 1.4 MB);
- code: the Python of this repo (layer, suite, bench, tests) and the engine's C / C++ / CUDA source;
- prose: the Markdown docs of this repo;
- always in the map: every control and special token of the vocabulary, the 256 byte tokens, and the tokens of the
  chat template, thinking tags and tool-call markup.

Sizes 16k, 24k and 32k are measured for coverage; the A/B uses the smallest size that passes S0.

## Gates (declared before the runs)

- S0 coverage, before any GPU run: on held-out text (one HumanEval run's answers that are not in the count, and
  held-out docs), the map covers at least 99.0 % of the tokens (token-weighted).
- S1 speed, RTX 4070 with the 8 GB preset pinned (`BONSAI_8GB=1`, replay on, fixed draft 2 / 2, the
  `../adaptive-mtp-20261019` request set at 4k / 32k / 64k / 128k): the shortlist arm against the same bins without
  the map, the VRAM line of the shortlist arm lowered by the size of the head copy.
  - S1a: mean decode over all requests at least 3 % higher.
  - S1b: no prompt type (code / story / quote) more than 1 % lower over all depths.
  - S1c: MTP draft acceptance at most 2 points lower.
  - S1d: 0 CUDA errors; every request answers.
- All pass: the map ships in the bundle and the 8 GB preset uses it (together with the 2 / 2 default, after the RTX
  2060 gate in #138). Any fail: not adopted; log why.

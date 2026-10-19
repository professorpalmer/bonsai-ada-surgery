# Experiments

One entry per run. Coverage = the share of held-out tokens (token-weighted) that are in the map. Receipts:
`receipts/coverage_s0.json`, `receipts/coverage_s0b.json`, `receipts/misses_s0.txt`; scripts: `receipts/corpus.py`,
`receipts/traces.py`, `receipts/make_map.py`, `receipts/misses.py`.

## SL0: corpus and thinking traces

- Corpus (build set, tokens): model answers 445,439 (HumanEval answers of this serve), C / C++ / CUDA 2,196,506,
  Python 174,155, our docs 870,294, the engine's docs 241,371, thinking traces 112,998 (80 of 100 prompts).
- Held out: one HumanEval run's answers (21,505 tokens), every fifth doc (176,086), 20 of the 100 traces (17,102).
- Thinking traces: bundle-20261019a, 12 GB default, layer off, thinking on at medium; 40 HumanEval tasks, 40 general
  prompts, 20 tool-call prompts; 100 answers, 0 errors, 313,236 characters of thinking. 0.3 GPU-h.
- Weights: model output 3, every other category 1; always in the map: 289 control / byte / single-character tokens.

## S0: corpus ranking only (FAIL)

| map | held-out answers | held-out docs | held-out traces |
| --- | ---: | ---: | ---: |
| 16k | 99.991 % | 99.139 % | **95.574 %** |
| 24k | 100.0 % | 99.782 % | **96.766 %** |
| 32k (27,801 ids: every token the corpus has) | 100.0 % | 99.890 % | **97.263 %** |

- FAIL on the traces (99.0 % required). At 32k, 468 of 17,102 trace tokens are missed (2.74 %), 285 distinct; 438 of
  them are plain Latin-letter words, mostly topic words of the held-out prompts (restaurant, kitchen, mechanic,
  wavelengths, tires, transmission). The corpus has code and technical English, no general English.

## S0b: corpus ranking + BPE-rank fill (FAIL)

Declared after S0 (README): the rest of each map is filled with the lowest-id ASCII tokens (in this byte-level BPE
vocabulary the id follows the merge rank, a frequency prior that needs no corpus).

| map | held-out answers | held-out docs | held-out traces |
| --- | ---: | ---: | ---: |
| 16k | 99.991 % | 99.139 % | 95.574 % (full from the corpus: no fill) |
| 24k | 100.0 % | 99.782 % | 96.766 % (no fill) |
| 32k | 100.0 % | 99.911 % | **97.977 %** |

- FAIL: the best map covers 97.98 % of the thinking traces. 32,768 ids is the map format's limit.
- Verdict: **not adopted; S1 (the speed A/B) did not run.** The model's thinking uses general English, and a 99 %
  shortlist of it needs more than 32k of the 248k tokens. Each miss is a draft token that the target rejects, so a
  2-3 % miss rate costs more acceptance than S1c allows (2 points). The engine change stays on the fork branch
  `serve/draft-vocab` (3e8203a520) for later use (for example with a shortlist made from a large general corpus).

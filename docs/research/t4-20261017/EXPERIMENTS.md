# T4-A fast read: results (2026-10-17)

Plan and gates: #138 (03:18Z plan by the kernel session; gates posted 07:4xZ before any run). Code: the kernel session's
T4 diff (wt-q3fast, branch t4-fastread, 01:53), built as an exact copy in my worktree (llama.cpp fork branch
`t4-fastread-b`, a269a922c9 on base 96f6e49cdc) with one build fix (`model.hparams`). Recipe: the 2060's recipe on the
4070 (`BONSAI_8GB=1`, q3_0, line 80,640, layer off). Script `t4_gates.sh`; receipts `t4_gates.log` / `.jsonl`.

| Gate | Result |
| --- | --- |
| T4-0 mode off | T4 bins with the env unset: greedy hashes all `1370fc25030ce635` = the product bins (bundle-20261017): **PASS** |
| T4-1 cold TTFT at 245k | **76.5 s** per question (scoring pass 58.2 s over 8 blocks, CPU scores 2.3-2.7 s, kept read 18,688 tokens); dense cold read on the same recipe 467.8 s: **6.1x faster** |
| T4-2 needle n24 at 245k, `keep=16384` | **7/24** (dense: 24/24). Found at frac 0.021, 0.146 and later items; lost at every depth (not a position effect). The lost answers say "The provided text does not contain the access code": the needle's block was not kept |
| T4-3 128k | stopped at its start: the GPU went to the diagnostics below |

0 CUDA errors. Reading: the speed is as planned (the scoring pass costs 1/8 of a full read), but the selection rule
(attention of the last 32 prompt rows at block 7, summed over rows and heads, best 32-token blocks by summed weight)
does not find the fact the question asks for. Diagnostics: `t4_diag.log` (per-head dump, other aggregations offline).

## Diagnostics (vault 2 at 245k, lost in T4-2; `t4_diag.log`, `t4_diag2.log`; score dumps per head and per row x head)

- The probe rows give the needles almost no attention: at block 7 the best head puts 0.4 % of its mass on all 24
  needle sentences together (block 15: 0.6 %).
- Block 7, offline rules (rows / heads / block): the server's rule (sum / sum / sum) drops the asked needle; any rule
  with **block = best token** keeps it (all rows or question rows; heads sum, normalized or max); needles kept 7-10/24.
  The best single probe row is " access" (10/24, target kept).
- Block 3 (30 s scoring pass): no rule keeps the asked needle (best 9/24 needles).
- Block 15 (16 blocks, 115 s scoring pass): worse (sum: target dropped; the answer quoted vault 1's code).
- One bug in my diagnostics script: the dump path lost its separator (`\$NAME`, the known escape class); the runs
  were sequential and each analysis read its own dump, so the numbers stand; fixed with `cygpath -m` paths.

## Round 2 (declared before the run): block = best token

`bmax=1` (commit f7d988d882): a block's score is its best token. Needle n24 at 245k, same recipe, two budgets:
`keep=16384` and `keep=32768`. Reference: dense 24/24 (467.8 s cold); round 1 7/24. Reported as measured (no pass /
fail for the mode); also the time per question.

### Round 2 results (`t4_round2.log` / `.jsonl`)

| arm | needles | per question | vs dense cold 467.8 s |
| --- | --- | --- | --- |
| round 1: block sum, keep 16,384 (18,688 tokens read) | 7/24 | 76.5 s | 6.1x |
| bmax, keep 16,384 | **9/24** `-+-++--++-------+-+--+-+` | 76.1 s | 6.1x |
| bmax, keep 32,768 (35,072 tokens read) | **14/24** `++-++--+++------++++++-+` | 93 s | 5.0x |
| dense (T3 gates, same recipe) | 24/24 | - | 1x |

0 CUDA errors. Reading: a larger budget helps (9 -> 14 at 2x the kept tokens), and the best-token block score helps a
little, but the selector stays far from dense: early-layer attention (block 3 or 7) of this model does not point at
the asked fact well, and a deeper probe (block 15) was worse in the diagnostics. Decision: T4-A stays an experiment,
off, not for a release. Ideas not tried: a probe at the mid layers where retrieval heads usually are (costs a larger
share of a full read), a text-match pre-filter (the question's rare tokens), and the small-model scorer (plan B).

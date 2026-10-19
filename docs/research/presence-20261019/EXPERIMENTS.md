# Experiments

One entry per run. Receipts: `receipts/he_template_ab.log` (the runner's log lines) and
`receipts/humaneval-pres-*.json` (per task: score, completion tokens, finish).

## PR1: presence penalty 0 against 1.5 (HumanEval 164, medium, the server's sampling)

- When: 2026-10-19 11:54-14:16, 2.37 GPU-h. RTX 4070, bundle-20261019a root, the 12 GB default, layer off,
  `--temp -1` (temperature 1.0, top_p 0.95, top_k 20). P15 confirmed in the launcher line: `--presence-penalty 1.5`.

| | P0 (no penalty) | P15 (1.5) |
| --- | ---: | ---: |
| HumanEval | 159 / 164 | 162 / 164 |
| mean completion tokens | 1,939 | 2,366 (+22 %) |
| median | 598 | 655 |
| p90 | 4,455 | 6,694 (+50 %) |
| tasks over 4,096 tokens | 18 | 22 |
| tasks at the 20,480-token thinking budget | 4 | 5 |
| errors / answers without code | 0 / 0 | 0 / 0 |

- G1 pass: 162 >= 159 - 3 (the +3 is within the noise of a sampled run).
- G2 FAIL: the long tail grew (22 tasks over 4k against 18; at most 13 was required).
- G3 pass.
- Verdict: **not adopted, and not recommended.** On this model a presence penalty of 1.5 makes the thinking longer:
  the penalty pushes the model away from words it already used, and in long reasoning it then writes more, not less.
  The docs keep the launcher's sampling and say so. For thinking that repeats in agent work, the measured tool stays the
  thinking budget (`BONSAI_THINK_BUDGET`), which stops a loop at a fixed length.
- Limits: HumanEval answers rarely loop, so this measures the length of normal thinking, not the loops of issue #7.
  The result still rules out the claim that the penalty makes thinking shorter.

# Presence penalty and runaway thinking (2026-10-19)

**Result: not adopted.** With `presence_penalty` 1.5 the thinking is longer, not shorter (tasks over 4,096 tokens
18 -> 22, p90 4,455 -> 6,694 tokens); the score is the same within noise (159 -> 162). See [EXPERIMENTS.md](EXPERIMENTS.md).

Plan written before the runs. One entry per run goes to `EXPERIMENTS.md`, one line per run to `runs.jsonl`.

## Question

A user (issue #7) sees long thinking loops in agent work: the model states a conclusion, then thinks the same steps
again. The launcher sends `--temp 1.0 --top-p 0.95 --top-k 20` and no presence penalty. The Qwen model cards tell users
to set `presence_penalty` between 0 and 2 when the model repeats itself. Does `presence_penalty` 1.5 make the thinking
shorter without a lower score?

Note: with thinking on, the server always has a reasoning budget, and that turns backend sampling off
(`common/sampling.cpp`). The CPU sampler chain then runs, and it has the penalties stage. So the penalty applies.

## Setup

- RTX 4070 12 GB, bundle-20261019a (the current release), the 12 GB default (q4_0, 262k window), layer off.
- HumanEval 164 at medium effort, `bench/humaneval_run.py --arm medium --max-tokens 24576 --temp -1` (the server's own
  sampling: temperature 1.0, top_p 0.95, top_k 20), through `bench/he_template_one.sh` with the model's template.
- Arms:
  - **P0**: no penalty (the default).
  - **P15**: `BONSAI_SPEC_ARGS="--presence-penalty 1.5"` (the launcher passes these flags to the server).
- Measures: score; mean, median and p90 completion tokens; tasks over 4,096 tokens (the long tail); tasks that reach
  the 20,480-token thinking budget (forced close).

## Gates (declared before the runs)

Sampled runs have noise, so the gates allow it:

- G1 score: P15 >= P0 - 3.
- G2 long tail: tasks over 4,096 tokens, P15 <= 0.75 x P0 (at least 25 % fewer).
- G3 no new failures: no task errors, no empty answers above P0.

Pass all three: document `presence_penalty` 1.5 for agent work in the docs, and test a launcher default on the agent
suite before a default change. G1 or G3 fails: the penalty costs quality; document that. G2 fails: no effect on the
long tail; document that, and look at the turns from issue #7 again.

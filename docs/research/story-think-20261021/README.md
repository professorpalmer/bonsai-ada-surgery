# Writing requests: the text written once, with less thinking (2026-10-21)

Plan written before the runs.

## Question

At the default effort (`medium`, a 20,480-token thinking budget), a writing request ("tell me a story") makes the
model write the whole text twice: a full draft inside its thinking, then the final text in the answer or a
`write_file` call. Seen on 2026-10-20: "Thought 3m 1s" with Chapter One drafted in the thinking, then an edited copy
written to a file. Which setting makes the model plan briefly and write the text once, without a worse text?

## Setup

RTX 4070 12 GB, a clean unzip of `bonsai-bundle-win-x64.zip` of bundle-20261020, the launcher defaults (q4_0, 262k,
layer on), one server for all arms. Requests through the layer, non-streaming, no `max_tokens` (the launcher cap,
24,576), `seed` 1, the server's sampling defaults, the system message "You are a helpful assistant."

Prompts (8; `prompts.json`): five chat-only writing requests (a 1,500-word short story, a 2,000-word first chapter,
a 40-line poem, an 800-word blog post, "tell me a long story") and three that offer a `write_file` tool and ask to
save the text (a 1,500-word story, a 1,200-word essay, a 1,000-word chapter).

Arms (in this order for each prompt):

| Arm | Request change |
|---|---|
| **M** | none (`medium`, the default) |
| **L** | `reasoning_effort: "low"` |
| **O** | `chat_template_kwargs: {"enable_thinking": false}` |
| **B** | `reasoning_budget_tokens: 2048` (the server closes the thinking with its budget message) |
| **N** | one sentence at the end of the user message: "Plan briefly in your thinking. Do not write the text itself in your thinking: write it once, in your answer." |

Measured for each run: wall time, thinking tokens (`timings.reasoning_n`), completion tokens, whether the budget closed
the thinking, the words of the final text (the answer, or the `content` argument of `write_file`), and **dup**: the
share of the final text's 8-word shingles that also occur in the thinking (1.0 = the text was written twice).

Quality: for each prompt, each arm's final text against M's text, judged by the same model (thinking off,
temperature 0) in both orders: "better writing and follows the request better: A, B or TIE". This judge is weak (the
model judges its own texts); it is a check for a clear loss, not a ranking. I also read the texts of two prompts.

## Gates (declared before the runs)

An arm is adopted for writing requests when all pass:

| Gate | Condition |
|---|---|
| G1 time | median wall time over the 8 prompts at most 0.6x of M |
| G2 once | median dup below 0.15 |
| G3 quality | judge: wins + ties against M at least 45 % over both orders; median words at least 0.8x of M |
| G4 health | 0 empty final texts; the three tool prompts end in a `write_file` call; 0 CUDA errors |

If more than one arm passes, the fastest one is adopted. It then goes into the layer as a default for writing requests
only (a request that sets its own effort or budget keeps it), in its own PR with tests and a bundle with gates. If no
arm passes, nothing changes, and the reason is logged here.

Noise: one sample for each cell (8 prompts x 5 arms). The A/B noise of this rig is up to 5 % for speed; text length and
the judge vary more. G1 asks for a 40 % cut, which is far above that noise.

## Amendment (2026-10-21 08:12, after one cell, before any other result)

**Observation O1** (the only cell run under the first plan, p1 / M): without client tools the layer offers its own
`run_python` tool. The model used it to count the story's words, over several rounds: 34,577 completion tokens and
332 s for a 1,599-word story, and the returned reasoning is the last round only (709 tokens). So the `dup` measure
cannot see the earlier rounds, and this cost hides the thinking cost that the study measures. The record is kept as
`observations.jsonl` (not in the gated set).

Changes:

- On the five chat-only prompts, arms M, L, O, B and N send `"code_interpreter": false` (the layer forwards the request
  without its tool). The three `write_file` prompts are unchanged (with client tools the layer does not offer its tool).
- New arm **I** on the five chat-only prompts: M as shipped (the layer's `run_python` offered). Recorded: rounds
  (`interpreter_trace`), completion tokens, wall time. The judge compares I with M too.
- New gate **G5**: if I's median wall time on the five chat prompts is at least 1.5x M's and the judge shows no gain for
  I (wins below 55 % against M over both orders), the layer stops offering `run_python` to writing requests (its own
  PR with tests and a bundle with gates).

G1-G4 are unchanged and apply to L, O, B and N against the new M.

## Results (2026-10-21 08:12-08:58, `runs.jsonl`, `judge.jsonl`, `texts/`)

45 cells, 74 judge pairs, 0 CUDA errors, no spill. Medians over the 8 prompts (I: the 5 chat prompts); wall and words
are per-prompt ratios against M:

| Arm | wall (s) | wall / M | thinking tokens | dup | words / M | budget closed | empty | `write_file` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| M medium | 52.6 | 1.00 | 3,630 | **0.916** | 1.00 | 0 | 0 | 3 / 3 |
| L low | 36.8 | 0.71 | 978 | 0.001 | 0.99 | 0 | 0 | 3 / 3 |
| O thinking off | 21.8 | **0.39** | 0 | 0.000 | 1.01 | 0 | 0 | 3 / 3 |
| B budget 2048 | 37.5 | 0.66 | 2,053 | 0.175 | 0.93 | 5 | 0 | 3 / 3 |
| N note | 49.5 | 0.90 | 1,788 | 0.064 | 1.04 | 1 | 0 | 3 / 3 |
| I run_python (as shipped) | 49.4 | **2.01** | 46 | 0.000 | 1.04 | 0 | 0 | - |

At medium the model drafts the whole text in its thinking on most prompts: dup 0.92 (p1), 1.00 (p4), 0.99 / 0.91 /
1.00 on the three `write_file` prompts, the case reported on 2026-10-20. Low stops it on the chat prompts but not on
two of the three `write_file` prompts (p6 dup 0.81 with 11,701 thinking tokens, p7 0.92). The note (N) does not stop it
on `write_file` prompts (p6 1.00 and the budget closed at 20,485 tokens, p7 0.97).

**The judge has a position bias**: it answered "A" in 59 of 74 pairs, and most pairs flip with the order. Only a
verdict that agrees in both orders says anything. Counted that way (prompts won / lost against M): L 1 / 1, O 0 / 5,
B 3 / 0, N 2 / 1, I 1 / 1. G3 as declared (wins + ties over both orders) mostly measures the bias; the table
below gives it as declared.

| Gate | L | O | B | N |
|---|---|---|---|---|
| G1 wall / M at most 0.6 | FAIL 0.71 | PASS 0.39 | FAIL 0.66 | FAIL 0.90 |
| G2 dup below 0.15 | PASS 0.001 | PASS 0.000 | FAIL 0.175 | PASS 0.064 |
| G3 judge at least 45 %, words at least 0.8x | PASS 50 %, 0.99 | FAIL 19 % (0 / 5 in both orders) | PASS 69 %, 0.93 | PASS 56 %, 1.04 |
| G4 health | PASS | PASS | PASS | PASS |

G5 (arm I): PASS. The layer's `run_python` doubles the wall time on writing requests (median 2.01x; p1 340.7 s with 5
rounds and 33,793 completion tokens, p2 135.7 s with 21,300), and the judge shows no gain (5 of 10, 1 / 1 in both
orders). The model uses it to count words.

**Decisions**

- **No thinking setting is adopted from this run.** Each arm fails at least one gate. Thinking off is the fastest and
  never drafts, but it loses 5 of 8 prompts in both orders. Budget 2048 is the best on quality (3 / 0) and about a
  third faster, but it misses G1 (0.66) and G2 (0.175), and on the `write_file` prompts its texts are shorter (p6 876
  words for 1,500 asked; the budget closed during the draft).
- **G5 is adopted**: the layer stops offering `run_python` to writing requests (its own PR with tests and a bundle with
  gates).
- **Next study** (its own plan): the `write_file` path, where the drafting costs the most (M 62-156 s): a larger budget
  (4096), low with a budget, two seeds, and a judge that counts only verdicts that agree in both orders.

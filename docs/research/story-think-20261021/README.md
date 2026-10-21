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

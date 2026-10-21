# Writing requests 2: a larger budget, and low with a budget (2026-10-21)

Plan written before the runs. Follows [story-think-20261021](../story-think-20261021/README.md): there, at medium the
model drafts the whole text in its thinking (median dup 0.92), and no setting passed all gates. A 2,048-token budget
was the best on quality (3 prompts won, 0 lost, in both orders) and 0.66x the time, but it missed G1 (0.6x) and G2
(dup 0.175), and on the `write_file` prompts the budget closed during the draft, so the texts were short (p6: 876
words for 1,500 asked). Low stopped the draft on the chat prompts but not on two `write_file` prompts.

## Question

Does a 4,096-token budget, or low effort with a 4,096-token budget, keep B's quality, stop the draft and keep the
length?

## Setup

As in story-think-20261021 (bundle-20261020 zip root, launcher defaults, one server, requests through the layer, no
`max_tokens`, the server's sampling defaults, the same system message and the same 8 prompts in `prompts.json`), with
these changes:

- Two seeds (1 and 2) for every cell, to see the noise.
- The chat-only prompts send `"code_interpreter": false` in every arm (the layer change of story-think-20261021 G5 is
  not in this bundle yet).
- Arms, in this order for each prompt and seed:

| Arm | Request change |
|---|---|
| **M** | none (`medium`, the default) |
| **B2** | `reasoning_budget_tokens: 2048` (the B of the first study, again) |
| **B4** | `reasoning_budget_tokens: 4096` |
| **LB** | `reasoning_effort: "low"` and `reasoning_budget_tokens: 4096` |

- The judge (the same model, thinking off, temperature 0, both orders) counts a prompt and seed as **won** or **lost**
  only when both orders agree; otherwise it is **even**. Reason: the first study's judge answered "A" in 59 of 74 pairs.

Measured as before: wall time, thinking tokens, words of the final text, dup (the share of the final text's 8-word
shingles that also occur in the thinking), budget closed, empty, the `write_file` call.

## Gates (declared before the runs)

An arm (B2, B4 or LB) is adopted for writing requests when all pass, over the 16 cells (8 prompts x 2 seeds), each
against M on the same prompt and seed:

| Gate | Condition |
|---|---|
| G1 time | median wall / M at most 0.6 |
| G2 once | median dup below 0.15 |
| G3 quality | judge: lost at most won + 1 (not clearly worse than M) |
| G4 length | median words / requested at least 0.8, and on the three `write_file` prompts (6 cells) median words / M at least 0.8 |
| G5 health | 0 empty final texts; every `write_file` cell ends in a `write_file` call; 0 CUDA errors |

If more than one arm passes, the one with the most prompts won goes in (the fastest if equal). It goes into the layer as
a default for writing requests only (the same `writing_request()` test as the G5 change: the first user message; a
request that sets its own effort or budget keeps it), in the same bundle as the G5 change, with gates. If none passes,
nothing changes, and the reason is logged here.

Noise: the M of the two seeds and the M and B of the first study give the noise of this setup; it is reported with the
results.

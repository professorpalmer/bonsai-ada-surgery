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

## Results (2026-10-21 09:20-10:17, `runs.jsonl`, `judge.jsonl`, `texts/`)

64 cells, 96 judge pairs, 0 CUDA errors, no spill. Medians over 16 cells (8 prompts x 2 seeds), each against M on the
same prompt and seed:

| Arm | wall (s) | wall / M | thinking tokens | dup | words / asked | `write_file` cells: words / M | budget closed | empty | `write_file` called |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| M | 89.8 | 1.00 | 7,846 | **0.915** | 1.03 | 1.00 | 4 | 0 | 6 / 6 |
| B2 (2048) | 33.8 | **0.41** | 1,484 | 0.062 | 1.05 | 0.82 | 7 | 0 | **5 / 6** |
| B4 (4096) | 49.2 | 0.48 | 4,101 | 0.415 | 1.02 | 0.87 | 10 | 0 | 5 / 6 |
| LB (low + 4096) | 52.5 | 0.50 | 3,984 | 0.161 | 1.08 | 0.96 | 8 | **1** | 6 / 6 |

Judge, prompts and seeds where both orders agree (won / lost / even against M): B2 3 / 4 / 9, B4 4 / 0 / 12, LB 4 / 3 / 9.
The position bias is there again: "A" in 76 of 96 pairs.

M varies a lot between seeds: p2 40.1 s and dup 0.0 on seed 1, 228.2 s and dup 0.99 on seed 2 (the budget closed at
20,485 thinking tokens); p8 87.2 s and 21.5 s. M closed the 20,480 budget in 4 of 16 cells.

**The forced close breaks the `write_file` flow.** In all three failed cells the budget closed the thinking first:

- B2, p6 seed 2: the thinking was counting the words of its draft when the budget closed it. The answer then says
  "I've written the story and saved it to story.md", with **no `write_file` call**: it claims an action it did not do.
- B4, p7 seed 2: the essay came as plain text (1,014 words), not as a `write_file` call.
- LB, p6 seed 1: the reply ran to the 24,576-token cap (`finish: length`) and the `write_file` content is empty.

| Gate | B2 | B4 | LB |
|---|---|---|---|
| G1 wall / M at most 0.6 | PASS 0.41 | PASS 0.48 | PASS 0.50 |
| G2 dup below 0.15 | PASS 0.062 | FAIL 0.415 | FAIL 0.161 |
| G3 lost at most won + 1 | PASS 4 <= 4 | PASS 0 <= 5 | PASS 3 <= 5 |
| G4 length | PASS 1.05, 0.82 | PASS 1.02, 0.87 | PASS 1.08, 0.96 |
| G5 health | FAIL (p6 s2: no call, claims a save) | FAIL (p7 s2: no call) | FAIL (p6 s1: empty) |

**Decision: no arm is adopted.** B2 passes G1-G4 and is 2.4x faster than M, but in 1 of 6 `write_file` cells it says
that it saved a file that it did not save. A setting that makes an agent claim work it did not do does not ship.

**Next** (its own plan): the budget's close message per request. The server closes the thinking with "Now produce the
complete answer.", and after it the model answers in text. A request can send its own `reasoning_budget_message`, so
the next study tests B2 with a message that names the tool call, on new seeds, with a gate on every claim of a save.

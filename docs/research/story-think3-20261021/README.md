# Writing requests 3: a budget whose close message names the tool call (2026-10-21)

Plan written before the runs. Follows [story-think2-20261021](../story-think2-20261021/README.md). There, a
2,048-token thinking budget (B2) made writing requests 2.4x faster, with no full draft in the thinking (dup 0.062) and
no clear quality loss. But after the forced close ("Now produce the complete answer.") the model answered in text: in
1 of 6 `write_file` cells it wrote "I've written the story and saved it to story.md" with no `write_file` call.

## Question

With a close message that names the tool call, does B2 keep its speed and quality, and does it always make the call
that the request asks for?

## Setup

As in story-think2-20261021 (bundle-20261020 zip root, launcher defaults, one server, through the layer, no
`max_tokens`, the same system message and the same 8 prompts; `"code_interpreter": false` on the chat-only prompts),
with **new seeds 3 and 4**, and these arms:

| Arm | Request change |
|---|---|
| **M** | none (`medium`, the default) |
| **B2T** | `reasoning_budget_tokens: 2048`, `reasoning_budget_message`: "Stop thinking now. Write the complete answer. If the request asks you to save or write a file, make that tool call now, with the complete text in it." |

Measured as before, and **claims_save**: the reply has no `write_file` call, and its text says that it saved or wrote
the text to a `.md` or `.txt` file. The judge counts a prompt and seed as won or lost only when both orders agree.

## Gates (declared before the runs)

B2T is adopted for writing requests when all pass, over the 16 cells (8 prompts x 2 seeds), each against M on the
same prompt and seed:

| Gate | Condition |
|---|---|
| G1 time | median wall / M at most 0.6 |
| G2 once | median dup below 0.15 |
| G3 quality | judge: lost at most won + 1 |
| G4 length | median words / asked at least 0.8; on the `write_file` cells median words / M at least 0.8 |
| G5 health | 0 empty final texts; every `write_file` cell (6) ends in a `write_file` call; 0 CUDA errors |
| G6 honesty | 0 cells with claims_save |

If it passes: the layer sends these two fields on writing requests that do not set their own effort, budget or budget
message. The budget is a sampler setting, not part of the prompt, so this test uses the **last** user message (the
current request): the prompt and the cache do not change. Its own PR with tests, then a bundle with gates, together
with the G5 change of story-think-20261021 (#227). If it fails, nothing changes, and the reason is logged here.

## Results (2026-10-21 10:25-11:01, `runs.jsonl`, `judge.jsonl`, `texts/`)

32 cells, 32 judge pairs, 0 CUDA errors, no spill. Medians over 16 cells against M on the same prompt and seed:

| Arm | wall (s) | wall / M | thinking tokens | dup | words / asked | `write_file` cells: words / M | budget closed | `write_file` called | claims_save |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| M | 73.9 | 1.00 | 5,587 | 0.929 | 1.02 | 1.00 | 4 | 6 / 6 | 0 |
| B2T | 38.1 | 0.603 | 1,742 | 0.051 | 1.04 | 1.04 | 8 | 6 / 6 | 0 |

Judge (both orders agree): won 3, lost 3, even 10 ("A" in 26 of 32 pairs).

The close message that names the tool call works: 6 / 6 `write_file` calls and 0 false claims of a save, against 5 / 6
and one false claim for B2 in story-think2. But one cell shows a new failure: **p1 seed 3**. The thinking was counting
the words of its draft ("He1 did2 not3 sleep4 ...") when the budget closed it, and the model went on counting **in the
answer**: 10,484 "words" of counting text, up to the 24,576-token cap (`finish: length`, 200 s).

| Gate | B2T |
|---|---|
| G1 wall / M at most 0.6 | **FAIL** 0.603 |
| G2 dup below 0.15 | PASS 0.051 |
| G3 lost at most won + 1 | PASS 3 <= 4 |
| G4 length | PASS 1.04, 1.04 |
| G5 health | PASS (0 empty, 6 / 6 calls, 0 CUDA errors); the p1 seed 3 answer is counting text, which G5 does not test |
| G6 honesty | PASS (0) |

**Decision: B2T is not adopted.** G1 fails (0.603 against 0.6), and a forced close can still turn the answer into the
word count of the draft.

## What the three studies show

At medium, when a request asks for a text of a given length, the model drafts the whole text in its thinking (median
dup 0.92-0.93 in all three studies) and often counts its words one by one there. That is where the time goes (M hit
the 20,480 budget in 4 of 16 cells in each of the last two studies). A forced close in the middle of that leaks into the
answer: a false claim of a save (story-think2), or the count itself (here). Thinking off never drafts and is 2.6x faster,
but it lost 5 of 8 prompts against medium in both orders (story-think). No server or layer setting tested here removes
the draft without one of these costs, so the default stays medium. What did ship: the layer no longer offers
`run_python` to writing requests (#227), which removes the word-count loop in the sandbox (2.01x the wall time).

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

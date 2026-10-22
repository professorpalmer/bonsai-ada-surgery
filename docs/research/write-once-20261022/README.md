# Writing requests: plan, then write once (2026-10-22)

Plan written before the runs. The target is the 8 GB card, which has no faster option.

## Question

At medium the model drafts the whole text in its thinking and often counts its words there, then writes the text
again ([story-think-20261021](../story-think-20261021/README.md), [-think2-](../story-think2-20261021/README.md),
[-think3-](../story-think3-20261021/README.md): dup 0.92-0.93). Every shorter-thinking setting tested there either lost
quality or cut the thinking in the middle of the draft, and the cut leaked into the answer (a false "saved" claim; the
word count in the answer). Can the model plan, and then write the text **once**, with no cut in the middle of a draft?

## The mechanism (checked before this plan; `smoke.jsonl`)

The engine can continue a final assistant message (`continue_final_message`, with `add_generation_prompt: false`).
With `continue_final_message: "content"` and a message that has `reasoning_content` = a plan and empty content, the
template renders the thinking as **closed**, with the plan in it, and the model writes the answer from there. In the
check (8 GB preset), a chat story came in 21.7 s (1,301 words) and a `write_file` story in 39.1 s with a correct call
(2,000 words), with 77 words of thinking. A steering sentence at the start of the thinking, in the model's voice
("I will plan briefly here ... I will not write the text here"), did **not** work: 3,358 and 12,854 words of thinking.

## Setup

RTX 4070 with the **8 GB preset** (`BONSAI_8GB=1`, the 2060 line 90,112 pinned: q3_0, 262k, draft 1 / tail 2, replay),
the bundle-20261021 zip root, one server for all arms. Requests go to llama-server directly (the layer has none of
these arms yet). No `max_tokens` (the launcher cap 24,576), the server's sampling defaults, the system message "You
are a helpful assistant.", **seeds 5, 6 and 7**, 10 prompts (`prompts.json`: the 8 of the earlier studies, the request
of 2026-10-20 "Great. tell me a 50k token story.", and a 3,000-word story saved with `write_file`).

| Arm | What the layer would do |
|---|---|
| **M** | nothing (`medium`, the default) |
| **P** | a planning call: the same request with "(Planning step: write a short plan only, at most 150 words: the main idea, the people, the shape, the tone and the length. Do not write the text itself.)" added to the last user message, thinking off, `max_tokens` 500; then the real request with the plan as closed thinking (`continue_final_message: "content"`) |
| **C** | the real request, streamed, thinking on. `draft_detect.py` watches the thinking at each paragraph end; at the first draft paragraph (a word-count run, labelled draft text, a prose paragraph with almost no planning words, or a title followed by such text) the stream is closed, and the thinking before that paragraph becomes the closed thinking of a continuation. If the thinking ends with no draft, the answer is used as it is. |

`draft_detect.py` was tuned on the recorded thinking of the three earlier studies (it finds a cut in 41 of the 43
cells with dup >= 0.5, and in 7 of 24 cells with dup < 0.05, where each of the 7 is a real draft that the final text
then changed), not on this run.

Measured for each cell: wall time (both calls for P and C), thinking words (all of them, also the part after a cut),
words of the final text, **dup** (the share of the final text's 8-word shingles that also occur in any of the
thinking), the cut (kind, plan words kept), `finish`, the `write_file` call, **claims_save** (no call, and the text
says it saved or wrote the text to a file), **count leak** (a word-count run in the final text).

**Quality: blind judges.** The model judged its own texts with a strong position bias in the earlier studies ("A" in
~80 % of pairs). Here the judges are separate Claude agents, which see only the request and two texts, labelled A
and B. For each arm (P, C) and seed there are two judges: one sees the arm as A, one sees M as A. A cell counts as
won or lost only when both judges agree; otherwise it is even. The judges are told to prefer the better text for the
request (quality of writing, following the request, length), and that a tie is allowed.

## Gates (declared before the runs)

An arm (P or C) is adopted when all pass, over 30 cells (10 prompts x 3 seeds), each against M on the same prompt
and seed:

| Gate | Condition |
|---|---|
| G1 time | median wall / M at most 0.6 |
| G2 once | median dup below 0.15 |
| G3 quality | blind judges: lost at most won + 3 |
| G4 length | median words / asked at least 0.8 (p9 asks for 50k: counted as 1,500); on the `write_file` cells median words / M at least 0.8 |
| G5 health | 0 empty final texts; every `write_file` cell (12) ends in a `write_file` call; 0 claims_save; 0 count leaks; 0 final texts cut at the output cap; 0 CUDA errors |

If both pass, the one with more cells won goes in (the faster one if equal). It goes into the layer for writing
requests (`writing_request()`, applied to the last user message: nothing here changes the prompt of earlier turns),
streamed and not streamed, with tests, a peer review and a bundle with gates; then a check on the RTX 2060 SUPER.
If neither passes, nothing changes, and the reason is logged here.

## Results of the runs (2026-10-22 08:47-10:32, `runs.jsonl`, `texts/`)

90 cells, 0 errors, 0 CUDA errors, no spill. Medians over 30 cells, each against M on the same prompt and seed:

| Arm | wall (s) | wall / M | thinking words | dup | words / asked | `write_file` cells: words / M | `write_file` called | claims_save | count leak | at the cap |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| M | 94.5 | 1.00 | 3,260 | 0.726 | 1.00 | 1.00 | 12 / 12 | 0 | 0 | 0 |
| P | 24.2 | **0.273** | 266 | **0.000** | 0.94 | 0.88 | **10 / 12** | 0 | 0 | 0 |
| C | 45.4 | 0.571 | 852 | 0.002 | 1.21 | 1.00 | 11 / 12 | 0 | 0 | **1** |

On the 8 GB preset the default spends a median 94.5 s on these requests (p1 seed 5: 233.9 s, 11,414 thinking words).
P writes the text once (dup 0.000 in 29 of 30 cells) in a quarter of the time. C cut the thinking in 21 of 30 cells
(prose 9, labelled 5, heading 4, counting 3); in the other 9 the thinking ended on its own.

**G5 fails for both arms**, before the quality step:

- P, p6 seed 5: the answer was one sentence, "I need to write a 1,500-word science-fiction short story ... I'll create the
  story and save it to story.md.", and then it ended: no text and no call. P, p10 seed 6: the whole story (2,497
  words) came as chat text, not as a `write_file` call. In both, the plan said nothing about the next step.
- C, p7 seed 6: the reply ran to the 24,576-token cap (13,672 words, 253 s), no call. C also overshoots the length
  (up to 11.4x asked: p9 seed 6, 6,929 words, 12.2x the time of M).

**Decision: neither arm is adopted as tested.** P fails only on the step after the plan, so the next study (its own
plan) gives P's plan a fixed last line in the model's voice that names that step. C is slower than P, overshoots the
length, and fails at the cap; it is not taken further. The blind judges for P run now, as data for the next study (P
is not adopted, so they decide nothing here).

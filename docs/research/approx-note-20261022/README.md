# Writing requests: tell the model that the length is approximate (2026-10-22)

Plan written before the runs. The target is the 8 GB card.

## Question

When a request names a length in words ("a 1,500-word short story"), the model counts the words of its draft one by
one in its thinking: 18-30 % of all its thinking words, up to 80 % in a cell, and most of the 20,480-token budget closes
([no-count-20261022](../no-count-20261022/README.md), [write-once-20261022](../write-once-20261022/README.md)). The
model asks itself whether the length is strict ("800-word blog post means approx 800?"). Removing the counts from the
thinking does not work: it counts again. In an exploration on 3 cells, one paragraph added to the request answered the
question and the counts stopped (23-124 s against 202-249 s). Is that faster with the same quality, over all cells?

## The arm

**A**: the user message gets one paragraph at its end, when the message is a writing request (`writing_request()` of
the layer) that names a length in words or tokens (`LENGTH_RE` below):

> About the length: an approximate length is fine. Do not count the words one by one, in your thinking or anywhere else.

`LENGTH_RE = r"\b\d[\d,.]*\s*k?\s*-?\s*(words?|tokens?)\b"`. It matches 8 of the 10 prompts. The 40-line poem (a
length in lines, where the count matters) and "Tell me a long story" (no number) do not get the note, so they are the
same as M and are not run.

## Setup

As in write-once-20261022: RTX 4070 with the 8 GB preset (`BONSAI_8GB=1`, line 90,112 pinned), the bundle-20261021 zip
root, llama-server directly, no `max_tokens`, the server's sampling defaults, the same system message and **seeds 5, 6
and 7**: 8 prompts x 3 seeds = **24 cells**. **M is not run again**: A is compared with the M records and texts of
write-once-20261022 (the same build, preset, prompts and seeds).

Measured: wall time, thinking words, numbered words in the thinking (`word12`), words of the final text, `finish`, the
`write_file` call, claims_save, count leak, budget closed. Quality: blind Claude judges, two orders for each seed, a
cell is won or lost only when both orders agree (as in write-once-20261022).

## Gates (declared before the runs)

A is adopted when all pass, over the 24 cells, each against its M cell:

| Gate | Condition |
|---|---|
| G1 time | total wall time at most 0.7x of M's total, and no cell slower than 1.5x its M cell |
| G2 quality | blind judges: lost at most won + 3 |
| G3 length | median words / asked between 0.8 and 1.3; no cell above 2.0x asked (p9, which asks for 50k tokens, is left out of G3) |
| G4 health | 0 empty final texts; every `write_file` cell (12) ends in a `write_file` call; 0 claims_save; 0 count leaks; 0 final texts cut at the output cap; 0 CUDA errors |
| G5 budget | budget closes at most M's in the same 24 cells |

If it passes: the layer adds the note to every user message that is such a writing request, in every turn (the same
messages get the same note each time, so the prompt of earlier turns does not change), streamed and not streamed,
with tests, a peer review and a bundle with gates; then a check on the RTX 2060 SUPER. If it fails, nothing changes,
and the reason is logged here.

## Results of the runs (2026-10-22 11:12-11:41, `runs.jsonl`, `texts/`)

24 cells, 0 errors, 0 CUDA errors, no spill. Against the M cells of write-once-20261022:

| | A | M |
|---|---:|---:|
| total wall (24 cells) | 1,728 s (**0.522x**) | 3,308 s |
| median wall / M, per cell | 0.51 (max **15.92**, p9) | 1.00 |
| median thinking words | 1,252 | 6,015 |
| median numbered words ("word12") in the thinking | **0** (max 1,669: p1 seed 7) | - |
| words / asked (p9 left out) | median 1.04, 0.81-1.50 | |
| budget closed | **0** | 8 |
| `write_file` called | 12 / 12 | 12 / 12 |
| empty / claims_save / count leak / at the cap | 0 / 0 / 0 / 0 | |

| Gate | A |
|---|---|
| G1 time | **FAIL**: the total is 0.522x, but 3 cells are slower than 1.5x their M cell, all p9 ("Great. tell me a 50k token story."): 2.05x, 15.92x, 2.34x. With the note the model tries to write the 50k story (4,678 / 8,870 / 6,471 words); M answered that one reply cannot hold it (9.0-79.7 s) |
| G3 length | PASS |
| G4 health | PASS |
| G5 budget | PASS (0 against 8) |
| G2 quality | not run yet |

**Decision: A is not adopted as tested** (G1).

## Amendment A' (2026-10-22 11:42, after the G1 result above, before any quality result)

A length that one reply cannot hold must not get the note: the note tells the model that the length is approximate,
and it then tries to write all of it. **A'** = A, but no note when the length named is above 10,000 words or tokens
(`k` counts as x1000). A' differs from A only on p9 (no note: the request of M). Because A' was made after seeing the
data, it is tested on **new seeds 8 and 9**, with M run again on the same server for those seeds: the 7 prompts that
get the note under A' (p1, p2, p4, p6, p7, p8, p10) x 2 seeds = 14 cells for each arm, in the order M, A' for each
prompt. The gates G1-G5 apply to these 14 cells unchanged (G3: no p9). The blind judges compare A' with M on those 14
cells, and also A with M on the 21 cells of seeds 5-7 without p9 (the same requests as A').

## Results of the A' confirmation (2026-10-22 11:43-12:43, seeds 8 and 9, `confirm/`)

28 cells (14 M, 14 A2), 0 errors, 0 CUDA errors, no spill.

| | A2 (A') | M |
|---|---:|---:|
| total wall (14 cells) | 1,304 s (**0.575x**) | 2,266 s |
| median thinking words | 2,768 | 9,442 |
| median numbered words in the thinking | **0** | 443 |
| budget closed | **0** | 6 |
| `write_file` called | 8 / 8 | 8 / 8 |
| empty / claims_save / count leak / at the cap | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| words / asked | median 1.01, 0.79-1.23 | |

| Gate | A' |
|---|---|
| G1 time | **FAIL**: the total is 0.575x, but 2 cells are slower than 1.5x their M cell: p8 seed 9 (21.5 -> 40.5 s, 1.88x) and p2 seed 9 (84.3 -> 140.6 s, 1.67x). In both, M did not count (0 and 1 numbered words): there was no count to remove, and the model took another path. |
| G3 length | PASS |
| G4 health | PASS |
| G5 budget | PASS (0 against 6) |
| G2 quality | the blind judges run now |

**Decision: A' is not adopted on this run** (G1 as declared).

**Why the cell rule fails here, and what replaces it (declared 2026-10-22 12:45, before any further run).** The M arm
alone varies up to 4x between seeds on the same prompt (p2: 40.1 s and 228.2 s in story-think2; p8: 87.2 s and 21.5 s).
A ratio of single cells therefore fails on cells where the note has nothing to remove. The cell rule was meant to catch
a request that the note makes much slower (p9 under A: 2.05x, 15.92x, 2.34x over three seeds). A rule on the mean of
each prompt over its seeds catches that case and is not a ratio of two single samples:

- **G1 (new)**: total wall time at most 0.7x of M's, and for **each prompt, the mean wall time over its seeds** at most
  1.25x of M's mean for that prompt.

It is tested on **new seeds 10, 11 and 12** (the 7 prompts x 3 seeds = 21 cells for each arm, M and A2 in turn, the same
server setup), with G2-G5 unchanged and the blind judges on these 21 cells. Seeds 5-9 are not used for this decision.

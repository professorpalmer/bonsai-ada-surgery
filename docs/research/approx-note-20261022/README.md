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

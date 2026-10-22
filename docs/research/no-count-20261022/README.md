# Writing requests: keep the draft, remove the word count (2026-10-22)

Plan written before the runs. The target is the 8 GB card.

## Question

[write-once-20261022](../write-once-20261022/README.md) showed that the draft in the thinking is the model's quality
step: without it the text loses 25 of 30 cells (blind judges). The part of the thinking that does not improve the text
is the word count: 18.3 % of all thinking words are numbered words ("He1 did2 not3"), 29.9 % are in counting
paragraphs, and in the worst cells the count is 80 % of the thinking. The count is also where the 20,480-token budget
closes (8 of 30 M cells), and a forced close during a count leaked into answers before (a false "saved" claim; the
count in the answer). If only the count is removed, and the model keeps its draft and its revision, is it faster with
the same quality?

## The arm

**K**: the real request, streamed, thinking on (`medium`). The thinking is checked at each paragraph end. When a
paragraph is a count (6 or more numbered words in a row, as `draft_detect.COUNTING`; or a line that starts a count:
"Let me count", "Count:", "Word count"), the stream is closed. The thinking before that paragraph, plus one line in the
model's voice, is sent back as an **open** thinking (`continue_final_message: "reasoning_content"`), and the model goes
on thinking from there:

> I will not count the words one by one: an approximate length is fine.

This repeats at each new count, at most 6 times; after that the request runs as it is. Each continuation is a new
request, and the server starts a new thinking budget for each request, so a continuation sends
`reasoning_budget_tokens` = what is left of the 20,480 (the thinking tokens so far subtracted, at least 512): K never
thinks longer than M could. Nothing else changes: the
model drafts, revises and closes its thinking itself. With the same seed and the same prompt the output is the same as
M's up to the first count, so each K cell is paired with its M cell.

## Setup

As in write-once-20261022: RTX 4070 with the 8 GB preset (`BONSAI_8GB=1`, line 90,112 pinned), the bundle-20261021 zip
root, llama-server directly, no `max_tokens`, the server's sampling defaults, the same system message, the same 10
prompts and **seeds 5, 6 and 7**. **M is not run again**: K is compared with the M records and texts of
write-once-20261022 (the same build, preset, prompts and seeds).

Measured: wall time (all parts), thinking words (all parts), the number of counts removed, words of the final text,
`finish`, the `write_file` call, claims_save, count leak (a count in the final text), budget closed.

Quality: blind Claude judges as in write-once-20261022 (two orders for each seed, a cell is won or lost only when both
orders agree). Cells where K removed no count are not sent to the judges; they count as even (the text is M's).

## Gates (declared before the runs)

K is adopted for writing requests when all pass, over the 30 cells:

| Gate | Condition |
|---|---|
| G1 time | total wall time of the 30 cells at most 0.8x of M's total, and no cell slower than 1.5x its M cell |
| G2 quality | blind judges: lost at most won + 3 |
| G3 length | median words / asked at least 0.8 (p9: 1,500) |
| G4 health | 0 empty final texts; every `write_file` cell (12) ends in a `write_file` call; 0 claims_save; 0 count leaks; 0 final texts cut at the output cap; 0 CUDA errors |
| G5 budget | budget closes at most M's (8) |

If it passes: the layer does this on writing requests (the last user message: nothing here changes the prompt of
earlier turns), streamed and not streamed, with tests, a peer review and a bundle with gates; then a check on the RTX
2060 SUPER. If it fails, nothing changes, and the reason is logged here.

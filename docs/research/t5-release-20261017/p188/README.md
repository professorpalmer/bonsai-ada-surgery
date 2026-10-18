# P188: a null test for the T5 hold (2026-10-17, kernel session)

Plan and decision rule: #138 comment 6245027983, declared before the run. Result: comment 6245174745.

**Question.** The T5 hold (parent folder) counts answers that change from right (window off) to confidently wrong. The
window arms change items in both directions, and a second window-off run only proves that the full read is
deterministic, not that the items are stable. Does a change in rounding alone move as many items?

**Run.** The same release bins (`r-t5`, `release/t5-candidate` a6bfcb1a4f), the 8 GB preset on the 4070, line 80,640,
layer off, the P170 code and prose sets, driver arm "dense", window off, with `GGML_CUDA_FA_CHUNK=16384` in place of
32768. The math does not change; the chunk fold sums in a different order. Script `p188.sh`, log `p188.log`, answers
`p188_code.jsonl` and `p188_prose.jsonl`, comparison `p188_compare.py`. 0 CUDA errors.

| arm (vs window off) | confident wrong where off is right | right/wrong changes | ok (of 48) | wrong |
| --- | --- | --- | --- | --- |
| window off | - | - | 31 | 16 |
| **null: chunk 16384** | **0** | **1** (prose 9 gained) | 32 | 15 |
| window 32k | 3 (code 6, 15; prose 21) | 7 (gained code 22; prose 1, 7, 9) | 32 | 14 |
| 32k + 8 dense | 3 (code 17; prose 13, 18) | 7 (gained code 22; prose 1, 7, 9) | 32 | 14 |

A miss is an answer that says the text does not state the value; a wrong answer is any other answer that is not right.
In the null arm the answer text changed on 2 code and 9 prose items, but only 1 item changed between right and wrong.

**Reading.** Rounding moves 1 item; the window moves 7. Net over both sets the window is neutral (the same ok count,
fewer wrong answers), but it changes which items are right much more than rounding does.

**Decision (by the declared rule).** The window effect is real. The R2 clause stays and T5 stays held. A new round
needs a change that keeps the window speed without these confident wrong answers, gated on this baseline.

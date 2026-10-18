# P189: a drift score for the T5 window settings (2026-10-17, kernel session)

Plan and checks: #138 comment 6245198344, declared before the run. Result: comment 6245757050.

**Why.** With 48 items and about 3 losses, a right/wrong count cannot rank variants of the window. P189 adds a
continuous score: the driver (`p189_drive.py`, the P170 driver plus top-20 `logprobs`) keeps the log-probabilities of
each answer token; `p189_drift.py` walks the answer tokens while an arm and the window-off arm choose the same token
and takes the max KL(off || arm) over those steps as the item score.

**Run.** Release bins `r-t5` (`release/t5-candidate` a6bfcb1a4f), 8 GB preset on the 4070, line 80,640, layer off, the
P170 code and prose sets. Script `p189.sh`, log `p189.log`, answers `p189_<arm>_<set>.jsonl`. 10 runs, 0 CUDA errors.

| arm | cold 245k (code) | ok of 48 | lost vs off | gained | drift median / mean / p90 |
| --- | --- | --- | --- | --- | --- |
| off (base) | 451.8 s | 31 | - | - | - |
| null: chunk 16384 | 455.7 s | 32 | 0 | prose 9 | 0.004 / 0.178 / 0.012 |
| window 32k, sink 1k | 255.3 s (1.77x) | 32 | code 6, 15; prose 21 | code 22; prose 1, 7, 9 | 0.028 / 0.061 / 0.086 |
| window 64k, sink 1k | 314.8 s (1.44x) | 31 | prose 13, 18 | code 22; prose 9 | 0.023 / 0.210 / 0.093 |
| window 32k, sink 8k | 268.1 s (1.69x) | 26 | code 15, 17; prose 13, 18, 22 | - | 0.020 / 0.054 / 0.133 |

**Checks.**
1. Pass: the base equals the #174 window-off answers (48/48), and window 32k equals the #174 window answers (48/48).
   The log-probabilities do not change the decode, and the windowed read is deterministic too.
2. Fail as declared: the null arm's mean drift (0.178) is not less than 1/3 of the window 32k arm's (0.061). One null
   item (prose 9, which changes from wrong to right) has a large KL and sets the mean. The score in this form is not a
   decision tool. The median and p90 separate the null arm from every window arm (about 7x), but that reading is post
   hoc; a next gate must declare a robust statistic before the data.

**Reading of the map** (no decision rests on it):
- A 64k window is slower (1.44x) and still loses 2 items. A larger sink (8k) is worse (5 lost).
- The drift hardly falls from 32k to 64k. The size of the window is not the lever; removing the far context at all
  moves the answers.
- Prose 13 and 18 are lost in three arms (64k, sink 8k, and the 8-dense arm of #174).

**Decision.** No candidate. T5 stays held.

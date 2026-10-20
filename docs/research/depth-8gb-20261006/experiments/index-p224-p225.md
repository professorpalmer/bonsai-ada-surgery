# Index, P224 to P225

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records PR #220, the week card PR
#221, the GPU time, the corrections and lessons) are in `events-p224-p225.md`, E117-E121. The previous range is
`index-p220-p223.md`.

State at the time of writing: 2026-10-20 14:24 CDT by the rig clock (19:24Z). The last notebook entry in this range is
"2026-10-20 14:22 CDT P225 (in-memory reference for P224 D): the restore is exact in content; the Q2 / Q3 errors are the
model at 200k". The queue is empty and filler b runs (from 14:21:36).

Decisions in this range: no restore issue is needed (P225); at ~200k, gates and checks use retrieval questions (P224,
P225).

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P224](P224.md) | 2026-10-20 13:39-14:01 | Deep-session check on bundle-20261019c: fresh 4k turns, a ~200k conversation across restarts | Wall gates PASS; all-correct gate FAIL | D2 6.05 s, D3 40.26 s, D4 3.28 s; Q3 wrong at 4k and ~200k, Q2 wrong at ~200k; 0 CUDA errors |
| [P225](P225.md) | 2026-10-20 14:02-14:21 | In-memory reference for P224 D: one server, no restart | FAIL by the letter (3/4); content equal | Turns 1-3 byte-equal (the same wrong Q2 / Q3); turn 4 a space against a newline; the errors are the model at depth |

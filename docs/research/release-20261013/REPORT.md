# Report

## Bottom line (so far)

- Patch 0054 (chunked gated-delta-net MMA prefill) passed perplexity (G01, +0.024 %), the RTX 2060 check (G02) and
  the op tests after the device-check change (G03, 55/55).
- The release bins are built from `de873117e1` (G04). Release gates: op tests pass (G05), HumanEval 158/164 after a
  re-score of a void scoring (G06), prefill +3 to +7 % with decode within 1.6 % (G07). Publish: G08.

## Decisions

| When | Decision | Why |
| --- | --- | --- |
| 10-13 16:33 | HumanEval gate for 0054 = at least 157/164, not the same text | The kernel changes the float order. Perplexity is equal (G01), and the D14 flips were long-thinking items |
| 10-13 17:46 | Release from `de873117e1`, not `e63ce36d9` | The device check before the temporaries (G02 note) went into 0054 before the bundle; the gate root gets the new bins |
| 10-13 20:55 | G06 re-scored, not re-run | All 164 answers were identical to D14; only the test step failed (0xC0000142 after the session restart) |
| 10-13 17:48 | Run G05-G07 on the new bins in the old queue (header line names `e63ce36d9`) | A running bash script is not edited (bash reads scripts by byte offset); a note in the receipt says which bins ran |

## Lessons

- **Configure before a release build after a checkout.** `common/build-info.cpp` is written at configure time; an
  incremental build keeps the old `LLAMA_COMMIT` (G04). Check the embedded commit before you ship.
- **Count test cases, not "OK" lines.** `grep -c OK` on `test-backend-ops` output also counts the backend summary
  lines (57 = 55 + 2, G03).

- **A session restart can break a running queue's child processes** (G06: 0xC0000142). Check result fields after a
  restart.

## Open items

- G08 (publish).

# Report

## Bottom line (so far)

- Patch 0054 (chunked gated-delta-net MMA prefill) passed perplexity (G01, +0.024 %), the RTX 2060 check (G02) and
  the op tests after the device-check change (G03, 55/55).
- The release bins are built from `de873117e1` (G04). The release gates G05-G07 are queued; the gates are fixed in
  `README.md` before the runs.

## Decisions

| When | Decision | Why |
| --- | --- | --- |
| 10-13 16:33 | HumanEval gate for 0054 = at least 157/164, not the same text | The kernel changes the float order. Perplexity is equal (G01), and the D14 flips were long-thinking items |
| 10-13 17:46 | Release from `de873117e1`, not `e63ce36d9` | The device check before the temporaries (G02 note) went into 0054 before the bundle; the gate root gets the new bins |
| 10-13 17:48 | Run G05-G07 on the new bins in the old queue (header line names `e63ce36d9`) | A running bash script is not edited (bash reads scripts by byte offset); a note in the receipt says which bins ran |

## Lessons

- **Configure before a release build after a checkout.** `common/build-info.cpp` is written at configure time; an
  incremental build keeps the old `LLAMA_COMMIT` (G04). Check the embedded commit before you ship.
- **Count test cases, not "OK" lines.** `grep -c OK` on `test-backend-ops` output also counts the backend summary
  lines (57 = 55 + 2, G03).

## Open items

- G05-G07, then G08 (publish).

# Report

## Bottom line (so far)

- q3_0 is on the current engine with no conflicts (Q01): fork `q3-on-sparse` `bae6dccfe`.
- The 4070 checks (Q03-Q05) and the 2060 set (Q06) are queued; the gates are in `README.md`.

## Decisions

| When | Decision | Why |
| --- | --- | --- |
| 10-13 20:05 | q3_0 rebase taken by the 4070 release session, sparse stays with the kernel session | Cary: 8 GB first; the two can run at the same time |
| 10-13 20:15 | Put q3_0 on top of `product-sparse`, not only `product-0054` | Sparse ships first; one conflict pass. The pick was clean on both |
| 10-13 20:20 | The q3 build waits for the bundle-0054 gates | No CPU load during the G07 speed arms |

## Open items

- Q02-Q06; the launcher `CellBytes` entry after #49.

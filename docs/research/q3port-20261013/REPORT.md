# Report

## Bottom line (so far)

- q3_0 is on the current engine with no conflicts (Q01): fork `q3-on-sparse` `bae6dccfe`.
- On the 4070, every q3_0 gate passes on the sparse base with int8 bounds (`4dbfe57d4`): op tests with q3_0 cases
  (Q03), perplexity +0.58 % vs q4_0 (Q04), sparse + q3_0 copies 10/10 and needles 12/12 at 160k (Q05). The 2060
  set (Q06) is asked for.
- On the 0055 candidate (`q3-on-0055` `7c7b47e156`), q3_0 with sparse on equals q4_0 on 20 items at 200k and 10 at 245k,
  +3.6 / +5.2 % decode at the same line (Q07).

## Decisions

| When | Decision | Why |
| --- | --- | --- |
| 10-13 20:05 | q3_0 rebase taken by the 4070 release session, sparse stays with the kernel session | Cary: 8 GB first; the two can run at the same time |
| 10-13 20:15 | Put q3_0 on top of `product-sparse`, not only `product-0054` | Sparse ships first; one conflict pass. The pick was clean on both |
| 10-13 20:20 | The q3 build waits for the bundle-0054 gates | No CPU load during the G07 speed arms |

## Lessons

- **After a power cut, delete the objects written just before it.** One corrupt object stopped the link (Q02).
- **`cmd /c start /wait` hides the build's exit code.** Check the output files, not the exit code.

## Open items

- Q06 (2060); the launcher `CellBytes` entry (14,336 B per cell) after #49; patch 0056 after 0055 ships.

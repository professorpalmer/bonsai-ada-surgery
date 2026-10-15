# Issue #21: decode at depth on 8 GB, 2026-10-10 to 2026-10-15

[Issue #21](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21) is the working thread between the 4070
sessions (engine and releases) and the 8 GB tester (RTX 2060 SUPER). In five days it took sparse host-tail reads from a
prototype to a shipped opt-in (bundle-20261014: 2.2x decode at 245k on 8 GB, copies and needles equal to dense) and
q3_0 K/V to its release gates. This folder keeps the thread as documentation.

| Path | What |
| --- | --- |
| `DECISIONS.md` | Every decision, why, and the comment and record behind it (start here) |
| `THREAD.md` | The issue and all comments, verbatim, with an index (C00-C91) |

The numbers live in the experiment records, not here: `../depth-8gb-20261006/` (the 2060, P001-P141),
`../depth-20261010/` (the 4070, D01-D28), `../release-20261013/`, `../release-20261014/`, `../release-20261014b/` and
`../q3port-20261013/`.

New comments on #21 after 2026-10-15 are added to `THREAD.md` when that work ends.

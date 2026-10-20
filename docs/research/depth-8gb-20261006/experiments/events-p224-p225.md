# Events, 2026-10-20 (range p224-p225)

Notebook entries in this range that are not experiments: PRs, a card, the GPU time, corrections and lessons. Sources:
`C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here), the entries "2026-10-20 14:03 CDT P224 ..." and "2026-10-20 14:22 CDT
P225 ...", receipts/queue.log, the receipts named below, the queue files' write times, and the PRs of this repo.
Numbering continues from `events-p220-p223.md` (E108-E116). Times with "Z" are UTC (GitHub); "CDT" and other times are
rig local time (UTC-5).

- [E117 Records PR #220](#e117-records-pr-220)
- [E118 The week card (PR #221)](#e118-the-week-card-pr-221)
- [E119 GPU time in this range](#e119-gpu-time-in-this-range)
- [E120 Corrections in this range](#e120-corrections-in-this-range)
- [E121 Lessons recorded in this range](#e121-lessons-recorded-in-this-range)

## E117 Records PR #220

| | |
| --- | --- |
| Date | PR #220 "docs/research/depth-8gb-20261006: P220-P223 records ..." opened 18:56:41Z, merged 18:57:57Z (24a4f49); notebook 14:03 CDT "Records PR #220 (P220-P223, agent) merged 24a4f49" |
| What | P220-P223, events E108-E116, 4 `runs.jsonl` rows, the notebook to 08:57 CDT, toolbox rows, 5 queue scripts and `p220_layer.py` |
| Links | `index-p220-p223.md` |

## E118 The week card (PR #221)

| | |
| --- | --- |
| Date | PR #221 "cards: week8gb.html, 8 GB in two weeks on the RTX 2060 SUPER (before and after)" opened 19:03:12Z, merged 19:03:20Z (b6cc8e6); notebook 14:03 CDT "Card PR #221 (docs/cards/week8gb.html -> docs/8gb/img/week.png) merged b6cc8e6" |
| What | The 8 GB mission card: the RTX 2060 SUPER at the start (2026-10-06) and with bundle-20261019c. Files: `docs/cards/week8gb.html` (every number in its `DATA` object, with its record in a comment), `docs/8gb/img/week.png` (2400 x 1350), a section "Two weeks on 8 GB" in `docs/8gb/README.md`, the card row in `docs/cards/README.md` and `bench/render_cards.ps1`, a link in `README.md`, and a source comment in `docs/cards/scorecard.html` |
| Rules (PR body) | "Before = the stronger of the community 64k recipe (P13 / P20) and our stock start (P2) in each row." "Now = the 19c defaults: 4k-128k P222 (d12), 245k P220 (the same bins), checked on the 19c zip by P223." The footer states two costs: a cold 4k read is not faster (417 against 427 tok/s), and q3_0 drifts more than q8_0 |
| Headline (commit) | Window 65,536 to 262,144; decode 37.2 to 52.4 at 4k, 17.5 at 60k to 39.9 at 64k, 3.0 at 120k to 29.6 at 128k, 11.4 at 245k; "a 199k chat back 5.3 s after a restart"; HumanEval 157 to 163 |
| Request | Cary, 2026-10-11 (the PR body); an open item in the notebook entry 08:57 CDT ("the 8 GB week card") |
| Links | PR #221; P2, P13, P20, P165, P220, P222, P223, P224 |

- See E120 for the P224 sentence in the PR body.

## E119 GPU time in this range

Queue log 13:39:59 to 14:21:36 (10-20), and fillers after it:

| from | to | what |
| --- | --- | --- |
| 13:39:59 | 14:01:26 | P224 (0.36 h); filler c had ended 13:39:58 |
| 14:01:26 | 14:02:26 | filler a (preempted) |
| 14:02:27 | 14:21:36 | P225 (0.32 h) |
| 14:21:36 | - | fillers (running at the time of writing) |

## E120 Corrections in this range

- PR #221 body: "P224 on the 19c zip gave a full answer in 6.05 s (restore 2.87 s)". The 6.05 s answer (D2) was the wrong
  Q2 ("vault 4: 9320"; the true largest code is vault 7, 9387). The card's restart number is from P165 ("Restart: P165"
  in the same PR body). Found by this record writer.
- P220 and P200 (the 30-turn soaks): the answers of Q2 ("vault 4: 9320", turns 2, 8, 14, 20, 26) and Q3 ("21442", turns 3,
  9, 15, 21, 27) are wrong (`receipts/p220/soak/state.json`; P220 is byte-equal to P200). Those gates counted answers and
  compared bytes, and did not grade the content. A line is added under P220's "Corrections later". Found by this record
  writer.
- P224 script: it greps the launcher log for "VRAM line", which the launcher does not print; run.txt has no line value.
  The server logs give 92,160. Found by this record writer.
- P225: the M and D histories differ by one token position after turn 2 (199,226 against 199,227 tokens saved), although
  the answer bytes are equal. Found by this record writer.

## E121 Lessons recorded in this range

- P224 / P225: at ~200k the model answers retrieval questions right, but comparison and sum questions wrong, with and
  without a restore. Q2 (the largest of 8 codes) is right at 4k and wrong at 131k (P220) and ~200k; Q3 (a sum of 3 codes)
  is wrong at 4k too.
- P224: grade every answer against the true values; "answered" and "byte-equal" gates do not find a wrong answer that
  repeats.
- P225: to tell a restore fault from a model error, run the same conversation on one server with no restart.
- P225: a byte-equal gate needs a content rule for known whitespace near ties, declared before the run.

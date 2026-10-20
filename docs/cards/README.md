# Result cards

Each card is one HTML file in this directory. The numbers of a card are in one `DATA` object at the top of its file,
and each number has a comment that names its source (a receipt or a research record, with the date).

To change a number:

1. Edit the `DATA` object of the card.
2. Run `bench\render_cards.ps1` (all cards) or `bench\render_cards.ps1 decode` (the cards whose name matches).
3. Look at the new PNGs and commit them with the HTML.

The script uses headless Edge (or Chrome) at 1200 x 675 CSS pixels and device scale 2 (2400 x 1350 PNG).

| Card | Source | PNG |
| --- | --- | --- |
| scorecard | `scorecard.html` | `docs/img/scorecard.png` |
| decode by depth | `decode.html` | `docs/12gb/img/decode.png`, `docs/8gb/img/decode.png` (`?focus=8gb`) |
| prompt reading | `prefill.html` | `docs/12gb/img/prefill.png`, `docs/8gb/img/prefill.png` |
| cache placement | `vram.html` | `docs/12gb/img/vram.png`, `docs/8gb/img/vram.png` |
| saved conversations | `saved.html` | `docs/agents-layer/img/saved.png` |
| agent work | `agentic.html` | `docs/agents-layer/img/agentic.png` |
| quality | `quality.html` | `docs/quality/img/quality.png` |
| fixed (before and after the runtime fixes) | `fixed.html` | `docs/img/fixed.png` |
| 8 GB in two weeks (before and after, RTX 2060 SUPER) | `week8gb.html` | `docs/8gb/img/week.png` |

`card.css` and `card.js` hold the shared style and drawing code; they hold no numbers. A value of `null` in `DATA`
prints "not measured". `legacy/` keeps the cards and figures used before 2026-10-19 (12 GB only, q8_0 era); the
script does not render them.

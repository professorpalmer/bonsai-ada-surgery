# Release research, 2026-10-10 to 2026-10-11: CUDA graphs past the VRAM line (patch 0053)

How a +25 % decode gain at depth was found, isolated, fixed and gated for the next bundle (bundle-20261011, published 2026-10-13), and the issue work in the
same window (PrismML #346). RTX 4070 12 GB (PCIe 4.0) for the 12 GB recipe; RTX 2060 SUPER 8 GB (PCIe 3.0) for the
8 GB recipe on issue #22. Read `REPORT.md` first; one entry per experiment in `EXPERIMENTS.md`, one JSON line per
experiment in `runs.jsonl`.

| Path | What |
| --- | --- |
| `REPORT.md` | Bottom line, what was promoted, the order of the work, lessons |
| `EXPERIMENTS.md` | One entry per experiment, R01-R10 |
| `runs.jsonl` | One JSON line per experiment: id, date, hw, engine, script, question, arms, gate, verdict, receipts |
| `../../../patches/0053-*.patch` | The change |
| `../../receipts/` | The raw logs named in each entry |
| `../../Q8_FULL_CONTEXT.md` | The user-facing summary (tiered cache, item 2) |
| `../depth-20261010/` | The depth research this came out of (sparse reads, op timing) |

## About the gates

The release gates (R03-R07) were declared before their runs in this session's chat and on issue #22, not frozen in
a plan file. Each entry says where. The isolation runs (R01) were measurements without a gate.

## Engines

- Release candidate: PrismML `adfffbe` + 53 patches = `90ca41e40` (fork branch `product-0053`), tree `c1865c46`; the
  same change unsquashed is fork branch `tier-graphs` (`4715804d6` + `6493bbca4`, the log line at WARN).
- Before: the bundle-20261010 engine `2cadbfb64` (52 patches).
- PrismML #346 work: PrismML `prism-b10770-6684606` (the reporter's build) and PrismML `prism` `e8fd209`.

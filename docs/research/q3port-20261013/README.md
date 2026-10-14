# q3_0 K/V on the current engine, 2026-10-13 (8 GB work)

The 3-bit K/V cache type (q3_0, 3.5 bpw) passed every quality gate on the RTX 2060 SUPER 8 GB launcher on the old
engine (`6a4851286` on `2cadbfb64`; issue #21, P108 / P114 / P117). This folder moves it onto the current engine,
on top of the sparse host-tail reads (patch 0055 candidate), and checks it on the RTX 4070 before the 2060 repeats
its set. Read `REPORT.md` first; one entry per step in `EXPERIMENTS.md`, one JSON line per entry in `runs.jsonl`.

## Order (Cary, 2026-10-13: 8 GB work first)

Sparse ships first as patch 0055 on top of bundle-0054; q3_0 follows in a later bundle (plan agreed on #21). The
q3_0 commit is kept on top of `product-sparse`, so the conflict work is done once.

## Gates (written here before the runs)

| Gate | Pass when |
| --- | --- |
| Q03 op tests | `test-backend-ops -b CUDA0` for `FLASH_ATTN_EXT`, `SET_ROWS`, `CPY`, `GET_ROWS` on the q3_0 build: 0 FAIL, and q3_0 cases present |
| Q04 perplexity | wikitext-2, `-c 2048`, 32 chunks, the same binary, K/V q8_0 / q4_0 / q3_0: q3_0 within 1 % of q4_0 |
| Q05 sparse + q3_0 | `bench/sparse_prefill.sh`, 160k, 8 GB-like line (32,768 cells), sparse 8192,64,1024, graphs on, packed mask on, `BONSAI_CTK=q3_0`: copies 10/10, needles 12/12 |
| Q06 (2060) | the tester's P108 / P114 / P117 set on the new build: the same results as on `6a4851286` within noise |

## Engines

- `q3-on-sparse` `bae6dccfe` (fork) = `product-sparse` `3ab0af3c2` (= `product-0054` + sparse) + q3_0.
- `q3-on-0054` `80b4eab7a` (local only): the same commit on `product-0054`, kept as a fallback if sparse slips.
- Build: `%TEMP%\build-q3` (sm_89, release options), test root `%TEMP%\root-q3` = `root-psparse` + the q3 bins.

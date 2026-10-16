# Bonsai 2 small models (2B / 4B / 9B) on the Bonsai serving stack, 2026-10-06 to 10-14

We tested the Bonsai 2 small models before their public release, in the early-access channel. These are the
documents from that work, published after the release. Each plan was written before its result
([DECISIONS.md](DECISIONS.md)). One early-access tester is named "tester A" here. Killy (@net_termina) is credited by name, as in the main
README.

Setup: RTX 4070 12 GB, Windows, the same engine as the 27B bundle of that week, one slot, the full 262,144 window
at q8_0 K/V in VRAM, all layers on the GPU, no draft head (the small files have none). Greedy unless stated.

## Documents

| File | Contents |
| --- | --- |
| [REPORT-20261008.md](REPORT-20261008.md) | The full report: HumanEval per size and arm, cap hits, tool calls, the exact-work suite, the edit-call probe, the hint ladder, the example check, the teachers (control), which model for 8 GB |
| [REPORT-20261007.md](REPORT-20261007.md) | The first report (9B, 4B, 2B batteries), with its correction of the cap-hit count |
| [DECISIONS.md](DECISIONS.md) | Every plan and result in order: loader bug, S1 batteries, the S2 teacher plan (teacher results: REPORT-20261008.md section 5), T1 test-first, S2b exact-copy probe, S3 edit repair and presence, G1 hint ladder, G1b example check, G2/G2b/G2c check note |
| [DRAFTER-AB.md](DRAFTER-AB.md) | 2026-10-14: the 2B and 4B as standalone draft models for the 27B, against the 27B's own MTP head |
| `receipts/` | Run logs per battery and probe; `receipts/drafter/` for the drafter A/B |
| `results/` | `summary.json` per HumanEval arm (pass count, cap hits) and the tool-call results |
| `results-raw.zip` | All per-sample files (the `samples.jsonl`, `suite/` and `exact_copy` paths that the reports name): HumanEval samples, suite traces, exact-copy calls, hint-ladder runs |
| `scripts/` | The launcher (`start-small.ps1`), the bench scripts, the suite and the layer as used for these runs |

## Main results

HumanEval 164, pass@1, thinking off / thinking on at medium (cap 24,576 tokens):

| Arm | 9B | 4B | 2B |
| --- | --- | --- | --- |
| raw (the GGUF's own defaults) | 133 / 139 | 117 / 148 | 69 / 88 |
| raw + presence 1.5 | 128 / 152 | 125 / 146 | 66 / 95 |
| serve (thinking budget + forced close) | 133 / 151 | 117 / 152 | 69 / 88 |
| serve + presence 1.5 | 128 / 153 | 125 / 146 | 66 / 95 |

- **Runaway thinking.** With no thinking budget, the 9B ran 16 of 164 problems to the cap. Presence 1.5 or the
  thinking budget stops it. The teachers (Qwen3.5 at Q4_K_M, the same engine and plan) loop more: the 9B teacher
  ran 18 of the first 40 problems to the cap. So the budget is a fix for the model family, not for the 1-bit files.
- **Edit calls.** The 1-bit 9B fails 25 % of its edit calls (old text not an exact copy), its teacher 6.5 %. At 4B
  and 2B the 1-bit files copy as well as their teachers. Presence 1.5 makes copying worse at every size (+6 to +13
  points), so the layer sets presence 0 on requests that bring tools.
- **Example check (2B default).** The layer runs the docstring examples on the answer and asks once more when they
  fail: HumanEval 86 -> 90, nothing broken.
- **Not adopted:** a "write the test first" sentence (0 of 12 at every size), hints after a failure for the 9B and
  4B (a plain "try again" does as well), presence inside the thinking only, the check note for computation
  (G2: 7 -> 10 on the 9B, did not hold on new seeds in G2b; G2c on the 4B did not meet its rule either), edit repair as a default (an opt-in for the 2B).
- **Speed (9B, 4070):** 166.6 / 143.1 / 100.9 / 72.3 tok/s at 0 / 16k / 64k / 128k, 7.1 GB at load with the
  whole 262k window in VRAM.
- **Small models as drafters for the 27B:** the 27B's own MTP head (draft 2) gives 94.1 / 101.8 tok/s; the 2B as a
  standalone draft model 21.2 / 25.9. The shipped MTP setting stays.
- **8 GB:** on the RTX 2060 SUPER the 27B scores 157-159 on HumanEval (152 for the 4B on the 4070). On the 4070 the
  27B scores 28 on the exact-work suite behind the layer, the 4B 12. Our pick for an 8 GB card is the 27B; the 4B is the fast option for short chat and code.

Loader note (DECISIONS, 2026-10-06): the 2B files abort at load when any layer stays on the CPU
(`GGML_ASSERT(ggml_is_padded_1d(a))`), also on the unpatched base. Full GPU offload (`-ngl 99`) does not use that
path.

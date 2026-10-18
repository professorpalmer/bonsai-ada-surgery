# T5 prefill window: release gates on the 4070 (2026-10-17), held

Plan and gates: #138 (comments 6241854303, 6241885671; the P187 arm 6244534476; the noise floor 6244718120), declared
before each run. T5 is the 2060 agent's prefill window (fork branch `t5-window-emu`); the release candidate
`release/t5-candidate` a6bfcb1a4f adds the kernel session's review fixes (the chunk skip is on by default only with
`LLAMA_PREFILL_WINDOW`; the window only with one slot). Launcher switch `BONSAI_FAST_READ=1` on branch
`launcher/fast-read`. Recipe: the 8 GB preset on the 4070, line 80,640, layer off; code and prose sets from P170
(`docs/research/depth-8gb-20261006/data/p170`, driver arm "dense").

| gate | window off | window 32k | 32k + 8 dense layers (P187 arm) |
| --- | --- | --- | --- |
| R1 op tests | - | 0 FAIL | (same bins) |
| R1 identity, env unset vs bundle-20261017b | 12 GB `edf0b1fbd89000ba`, 8 GB `1370fc25030ce635` | identical: PASS | (same bins) |
| cold 245k | 464.5 s | **257.9 s (1.80x)** | 361.2 s (1.29x) |
| cold 128k | 167.7 s | 129.8 s (1.29x) | - |
| n24 at 245k | 24/24 | 24/24 | 24/24 |
| code set | 20/24 | 19/24 (lost 6, 15; gained 22) | 20/24 (lost 17; gained 22) |
| prose set | 11/24 | 13/24 (lost 21; gained 1, 7, 9) | 12/24 (lost 13, 18; gained 1, 7, 9) |
| confident wrong answers where off is right | - | **3** (limit 1) | **3** (limit 1) |

**Noise floor:** a second window-off run of code and prose gives exactly the same 48 answers (0 items differ): the full
read on the 4070 is deterministic, so the wrong answers come from the window. 0 CUDA errors in every run.

**Decision:** T5 is held (the declared R2 clause fails in both arms). The speed is real (1.80x at 245k; the 2060's agent
soak P184: 30/30 identical answers, 1.51x), but in single-question lookups over long documents the windowed read can
return another item's value with confidence. A new round needs a change that removes those wrong answers, gated on the
4070 first (deterministic baseline).

One record note: the first R1 run lost its identity hashes to a grep fault in my script (the client prints `all <hash>`);
R1 was rerun (`t5rel_r1id.sh`). The release bins' version string shows `d1cc7a4bdd` (an incremental build kept the old
build info); they contain a6bfcb1a4f's changes.

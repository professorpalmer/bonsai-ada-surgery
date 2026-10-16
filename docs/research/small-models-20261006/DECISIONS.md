# Decisions and plans: Bonsai 2 small models (2B / 4B / 9B) on the serving stack

Every plan is written before its result; results follow in their own entry with the receipt path.

## 2026-10-06 19:30 - Loader: the 2B files (PTQ1_0, PQ2_0, Q2_0) abort in our bundle binary, load on the unpatched base
`GGML_ASSERT(ggml_is_padded_1d(a))` in `ggml_scale_impl` at model load (CPU, `-ngl 0`, so backend-independent),
all three quant variants. The unpatched PrismML base `adfffbe41` (CPU build) loads the same file and answers. The
small files carry `prism.hadamard.version 2` with `tied_output` (PrismML #257, merged 09-24, in our base) and no
`output.weight`; the 27B has a separate output tensor, which is why the 27B never exercised that path with our
patches. Bisect over the 33 patches with CPU builds (`%TEMP%\bisect_step.sh`, results in `bisect_results.log`).
Result (20:40): the CPU bisect was uninformative (a CPU-only build never runs the fused-op probing where the assert
lives). `-lv 5` placed the assert inside `resolve_fused_ops`, Lightning Indexer probe, right after fused Gated
Delta Net was disabled because `-ngl 0` leaves layer 0 on the CPU while the op is on CUDA0; the unfused GDN
fallback then scales a non-contiguous view. A CUDA build of the unpatched base `adfffbe41` fails identically on
the same file (`%TEMP%\base-cuda-build`, log `small2b-basecuda.log`). So: a bug in the unpatched base, partial offload only
(any layer left on the CPU), not the Hadamard v2 contract (the 9B is v1 and would hit the same path). Our full
offload serve (`-ngl 99`) never builds that path; the GPU load check confirms once the serve is free. Report goes
to the channel with the repro line; a fix (cont the view, or skip the LID probe for architectures without an
indexer) can be offered as a PR.

## 2026-10-06 19:40 - Plan S1: the battery, per size, 9B first
Arms on this card (RTX 4070 12 GB; the 27B serve is down during runs), one slot, 262k window at q8_0 all in VRAM:
- **raw**: the model's own template and `generation_config` defaults, presence 0, no budget, no harness flags.
- **raw+pp**: presence penalty 1.5 (tester A's finding on the 9B).
- **serve**: our recipe: medium effort, reasoning budget 20480 with forced close, harness-proofing, backend
  sampling, presence 0.
- **serve+pp**: the same with presence 1.5.
- **layer**: `serve` behind the layer (API cards, API check, sandboxed Python).
Measurements: (a) HumanEval 164 sandbox-scored at thinking off and medium (loop rate = runs that hit the cap
without an answer); (b) the 37-task long exact-work suite, raw vs layer, same seeds as ML2; (c) tool calls 9
requests (`bench/toolcall_stress.py`); (d) the effort-high and 4096-cap replays (harness-proofing on vs off);
(e) decode by depth at 0 / 16k / 64k / 128k / 200k and prefill on a 16k prompt, PTQ1_0 vs PQ2_0 (tester A: PQ2_0 is
faster on CUDA for the 2B); (f) VRAM at load and over the window.
Gates / reading rules: a change is reported as a win only when the paired delta exceeds the 4-seed noise band
(1-2 items on a 12-item family; the 27B determinism probe), and loops are counted from the samples, not inferred.
Report format for the channel: one table per size, raw vs serve vs layer, loops column, plus the receipt tarball.

## 2026-10-07 05:55 - S1 result, 9B PTQ1_0 (RTX 4070, 262k q8_0 all in VRAM, 7.1 GB at load; receipts/9B_battery.log, results/9B/)
Speed: 166.6 / 143.1 / 100.9 / 72.3 tok/s at 0 / 16k / 64k / 128k (no draft head exists for these files).
HumanEval 164, greedy, sandbox-scored; cap 24,576 at medium (cap hits: corrected in the 2026-10-07 18:00 entry):
| arm | thinking off | medium | medium wall time |
| raw (model defaults) | 133 | 139 | 85 min |
| raw + presence 1.5 | 128 | 152 | 50 min |
| serve (budget 20480 + forced close, harness-proofing) | 133 | 151 | 80 min |
| serve + presence 1.5 | 128 | 153 | 54 min |
Reading: at medium the penalty and the budget each recover ~12-13 problems over raw and overlap almost entirely
(together +1, inside noise); the penalty also cuts thinking time ~40%. Thinking off, the penalty costs 5 problems
in both arms (repetition is normal in code). Recommendation for the card: presence 1.5 with thinking ON only; the
budget + forced close regardless. [Corrected 2026-10-07: raw medium hit the cap on 16 problems; see 18:00.]
Tool calls (bench/toolcall_stress.py, 9 each): native grammar 9/9 parsed (payload fully right 5/9); JSON asked for in
content 1/9, 3 cut by the cap. Same shape as the 27B: send `tools`, let the server format them.
Suite (37 tasks, frozen plan, same seeds, raw vs layer): 9/37 vs 9/37, 2 rescues / 2 losses, layer tokens 0.52x.
Coding 0/12 both arms; computation 6/15 both (digits +1 and weblog +1 with the layer, sales -2); workspace 3/10 both
(chain 1/2, copy 2/2, the three H items 0/2: submitted, full_pass=False). The layer does NOT lift the 9B the way it
lifted the 27B (17 -> 28): the sandbox needs the model to write the computation as code and read input.txt, and the
9B does not do that reliably; its wins and losses on the 9B are inside the noise band. Honest line for the channel:
the serve recipe is worth +12 HumanEval at medium; the layer is a wash on the 9B; the suite's exact-work families
are mostly out of reach for a 9B regardless of serving.

## 2026-10-07 09:30 - Plan S2: the teachers as the control (size vs compression)
Every small model measured so far is ternary, so "a 9B cannot do the exact-work suite" and "1.58-bit at 9B cannot"
are the same observation. Control: the uncompressed-class bases Qwen3.5-9B / 4B / 2B at Q4_K_M (unsloth GGUFs,
5.68 / 2.74 / 1.28 GB; Q4_K_M chosen as the common "what people actually run" precision, ~4.5 bpw) on the SAME
engine, flags and plan: arms raw and serve (HumanEval off + medium with loop counts), tool calls, and the suite raw
vs layer. Reading rule, per size: if the base scores within the noise band of the ternary file on the suite
(within 3 of 37), the gap is size; if the base is >= 6 above, compression is the cause at that size and the
number is the cost. HumanEval is reported alongside so a size-vs-compression story on the suite can be checked
against the short-code benchmark. Runs after the ternary batteries finish (GPU is the constraint). Not a claim
about PrismML's training recipe; a paired measurement of their file against its own base on one card.

## 2026-10-07 13:00 - S1 result, 4B PTQ1_0 (receipts/4B_battery.log, results/4B/)
HumanEval 164 (greedy, cap 24,576; cap hits corrected in the 18:00 entry): raw 117 / 148 (off / medium), raw+pp 125 / 146,
serve+pp 125 / 146, serve 117 / **152**. Thinking is worth 31 problems on the 4B (6 on the 9B). The penalty's sign
flips with thinking off (+8 here, -5 on the 9B) and it does nothing at medium; the budget + forced close is the
recipe that helps at medium (152, best 4B score).
Tool calls: grammar 8/9 parsed (1 cut by the cap, payload right 3/9), JSON-in-content 1/9.
Suite raw vs layer: **7/37 vs 12/37**, 6 rescues / 1 loss, layer tokens 0.84x. Coding 0/12 both; computation
4/15 -> 9/15 (digits 0 -> 2, knapsack 2 -> 3, sales 1 -> 2, weblog 1 -> 2); workspace 3/10 both. Unlike the 9B (a wash,
9 vs 9), the layer's sandbox lifts the 4B on exact computation. Run split by the issue pauses (resume from
results.jsonl): coding before, computation/workspace after the layer's finish-sentence gate change; that gate only
touches requests with client coding tools, which computation/workspace do not send, so the arms are comparable.
Engine: 9B and 4B on the product binary (c8b8993a6); the 2B and the teachers run on 2cb7a4ed6 (+ patch 0034, the
JSON-schema converter only; no effect on these requests).

## 2026-10-07 14:15 - Plan T1: a test-first note for build-from-spec coding (from Killy's plates 050/051)
Evidence from three harnesses: the small Bonsai 2 models fix bugs when a failing test points at them (Killy, 58
mutants: 4B 55, 9B 57) and fail when they must build from a spec with no test (Killy: 0 / 2 / 4 of 24 for 2B / 4B /
9B; tester A's PatchEval: 9B 1 of 20, false "verified" endings; ours: coding family 0/12 for 4B and 9B). The 9B also
declares victory early (Killy: 19 of 35 failures say DONE). Hypothesis: if the model writes the failing test from the
spec first, the task turns into the case it handles.
Treatment: TEST_FIRST_NOTE appended to the first user message of coding requests that offer a run tool and ask for
code ("Before you implement anything, write a small test file that encodes the requirements above, including every
example given, and run it to see it fail. Then implement until those tests pass, and run them again before your final
answer."). Off by default; --test-first on the layer or "test_first": true per request.
Arms (bench/run_t1.sh): per size, the layer as shipped (:8080) vs the layer + test-first (:8081), both in front of the
same llama-server, paired request by request, the suite's coding family, frozen seeds 1-4 (12 runs per arm).
Gate: adopt as a default for small models if layer_testfirst >= layer + 3 of 12 on the 4B or the 9B with no more than
1 loss on that size. Computation and workspace requests carry no client coding tools, so the note never reaches them
(no-loss by construction). The 2B is run for the record. Runs after the teacher batteries (queue_20261007.sh).

## 2026-10-07 15:50 - S1 result, 2B PTQ1_0 (receipts/2B_battery.log, results/2B/)
HumanEval 164 (greedy, cap 24,576; cap hits corrected in the 18:00 entry): raw 69 / 88 (off / medium), raw+pp 66 / **95**,
serve+pp 66 / **95**, serve 69 / 88. Thinking is worth 19 problems. On the 2B the penalty is the lever at medium
(+7, like the 9B), and the budget + forced close adds nothing (88 = raw). With thinking off the penalty costs 3.
Tool calls: grammar 8/9 parsed (payload right 2/9, 1 cut by the cap), JSON-in-content 2/9.
Suite raw vs layer: **0/37 vs 3/37**, 3 rescues / 0 losses (digits 0 -> 1, knapsack 0 -> 2). Coding and workspace 0
on both arms. The 2B is below the floor of the exact-work suite; the sandbox gives it a few computation wins.
Per-size card advice so far: 9B presence 1.5 with thinking on; 4B the budget, no penalty; 2B presence 1.5 with
thinking on. Paused 14:47-15:49 for issue #7 (bonsai-ada-surgery); the 2B battery had finished, 9B-base not started.
Queue resumed with bench/queue_20261007b.sh (teachers 9B, 4B, 2B, then T1).

## 2026-10-07 18:00 - Correction: HumanEval cap hits were never counted
The battery's loop counter read `finish` from samples.jsonl, which has no such field, so every "loops
(finish=length): 0/164" line was a constant, not a measurement. The `finish` field is in each arm's summary.json.
Real cap hits at medium (24,576): 9B raw 16, raw+pp 1, serve 0, serve+pp 0; 4B raw 6, others 0; 2B raw 9, raw+pp 2,
serve 1, serve+pp 1. Thinking off (cap 1,024): 3-6 per arm. Consequence: the medium gains from presence 1.5 and
from the budget + forced close are mostly runaway thinking stopped, which agrees with tester A's loop finding; the
earlier statements "no cap hits" and "nothing here was a cap-break" are withdrawn (REPORT-20261007.md corrected).
Fix: battery.sh, battery_teacher.sh and suite_only.sh read summary.json. The 9B-base raw-off line (4/164 real, 0
printed) is the only teacher number affected so far.

## 2026-10-07 18:45 - T1 result: the test-first note is rejected (results/<size>/t1_coding/, receipts/t1.log)
Coding family, frozen seeds 1-4, 12 runs per arm, paired. Gate: +3 of 12 on the 4B or the 9B, at most 1 loss.

| Size | Layer as shipped | Layer + test-first | Wrote a test file (shipped / test-first) | Hit the 24-step limit (shipped / test-first) |
| --- | ---: | ---: | --- | --- |
| 9B | 0/12 | 0/12 | 3 / 12 | 12 / 11 |
| 4B | 0/12 | 0/12 | 2 / 7 | 12 / 11 |
| 2B | 0/12 | 0/12 | 2 / 4 | 12 / 11 |

The gate fails on both sizes. The note works as an instruction (the 9B writes a test file in 12 of 12 runs against
3 of 12), but no run passes. Two causes are visible in the traces: (1) almost every run on both arms uses all 24
agent steps (suite/envs.py), so these tasks end at the step limit; (2) the most frequent failure is the result
format (`result_schema`), and the model's own tests do not catch it, because the model writes the tests from the
same incorrect reading of the specification. This agrees with Killy's plates: the small models fix code when a
correct failing test exists, and they cannot make that test from a specification themselves.
Not adopted. The opt-in flag stays in the small-model layer (off). A higher step limit is not planned: with the
format error in the model's own tests, more steps would repeat the same error.

## 2026-10-07 19:20 - Plan S2b: cheaper teacher batteries, and an exact-copy edit probe (written before any result)
Why: the 9B teacher (Qwen3.5-9B Q4_K_M) ran to the 24,576 cap on 3 of its first 5 thinking-on HumanEval problems
(~5 min each at 86 tok/s), so one full arm costs ~16 h and the three teachers several days.
Change 1: the teachers' thinking-on HumanEval arms (raw and serve) run on the first 40 problems (MED_LIMIT=40).
Thinking off stays at 164. The ternary files are compared on the same 40 problems from their existing rows.
Change 2 (new measurement): bench/exact_copy_probe.py. Tester A's PatchEval traces show the 9B's edit calls fail
34% of the time because oldText is not an exact copy of the file; they asked whether a 4-bit model does the same.
40 items (4 functions in each of 10 CPython stdlib files, a ~200-line window given as a read tool result), one
edit call asked for (insert a comment above a named line), 3 fixed seeds, sampler as in their runs (temperature 1.0,
top-p 0.95, top-k 20, presence 0, thinking on, per-request budget 4096), layer off. Primary measure: rejected
edits / edit calls (oldText not found, or not unique). Six models: ternary 9B, 4B, 2B and the three teachers.
Reading rule: a ternary-vs-teacher difference counts if the 95% intervals of the two rejection rates do not overlap.
Order: exact-copy probe (all six, ~1 h), then the teacher batteries 9B, 4B, 2B.

## 2026-10-07 19:55 - Plan S3: serve-side fixes for the small-model breakdowns (written before any result)
Evidence: tester A's PatchEval traces (34% of the 9B's edit calls rejected; misspelled identifiers with presence
1.5), Killy's plates and T1 (build-from-spec fails; the model's own tests carry its misreading), our cap-hit counts
(runaway thinking at medium, stopped by presence 1.5 or by the budget + forced close).

S3a, edit-call repair in the layer (layer/edit_repair.py). When a client tool call has an old/new text pair whose
old text is not in the conversation's tool results, but exactly one place there matches line by line once
leading/trailing whitespace is ignored, replace the old text with the exact lines and shift the new text by the
same indentation. No change when the old text is exact, unmatched or ambiguous.
  Offline gate (bench/edit_repair_eval.py on the probe's recorded calls, all models that recorded them):
  adopt if the rejected share falls by at least half on the 9B or the 4B, and no exact call is broken (broke = 0).
  Then a live arm (probe through the layer with the repair) to confirm.
S3b, does presence 1.5 hurt exact copying? Probe arm at presence 1.5 on the ternary 9B, 4B, 2B (same seeds). If the
rejected share rises by 10 points or more on any size, build "presence inside the thinking only" in the engine and
measure it on HumanEval medium (cap hits) and on the probe. If it does not, the misspelling hypothesis is not
supported here, and presence stays a per-size setting.

## 2026-10-07 20:40 - Plan G1: the dose ladder (from Killy: "if it fails, guide it to see if it figures it out")
Question: after a failure, which smallest hint makes the model recover, and can a server make that hint?
Material: every HumanEval failure of the serve arm at medium that has an answer (9B 13, 4B 12, 2B the first 30 of
its failures); failures with no answer (thinking ran to the cap) are counted, not continued. The conversation is
continued from the model's own failed answer with one user message, greedy, thinking on at medium:
  R0 "Your solution is not correct. Try again."   (control: no information)
  R1 R0 + "Check it against the examples in the docstring, and fix it."
  R2 R0 + the docstring examples run on the failed code (doctest report; a server can make this)
  R3 R0 + the first failing hidden test, with the actual and expected values (only a grader has this)
Offline check of R2 content: the examples fail (R2 carries new data) on 9B 5/13, 4B 4/12, 2B 20/30; the rest
have no runnable examples or pass them.
Reading rules: R2 - R0 >= 3 recoveries on any size, and R2 within 2 of R3 -> build the server-side example check
in the layer. R3 - R0 >= 3 but R2 - R0 < 3 -> hints work, the server cannot make the good one yet. R3 - R0 < 3 ->
hints do not help at this size. Also report R2 on the subset where the examples fail.

## 2026-10-08 04:10 - S2b result: the exact-copy edit probe, six models (results/<model>/exact_copy/, receipts/exact_copy.log)
120 items per model (40 items x 3 seeds), sampler as in tester A's runs, layer off. Rejected = the edit call's old
text is not in the file, or is in it more than once. 95% Wilson intervals.

| Model | Rejected / edit calls | Not an exact copy | Exact but not unique | No edit call | Comment placed as asked |
| --- | --- | ---: | ---: | ---: | ---: |
| 9B ternary | 28 / 112 = 25.0% [17.9, 33.8] | 13 | 15 | 8 | 57 |
| 9B teacher (Q4_K_M) | 6 / 93 = 6.5% [3.0, 13.4] | 4 | 2 | 27 | 70 |
| 4B ternary | 23 / 102 = 22.5% [15.5, 31.6] | 11 | 12 | 18 | 32 |
| 4B teacher | 25 / 94 = 26.6% [18.7, 36.3] | 17 | 8 | 26 | 50 |
| 2B ternary | 52 / 108 = 48.1% [39.0, 57.5] | 49 | 3 | 12 | 10 |
| 2B teacher | 35 / 73 = 47.9% [36.9, 59.2] | 25 | 10 | 47 | 12 |

Reading (rule of Plan S2b): only the 9B differs. The ternary 9B's edit calls fail about 4 times as often as its
teacher's (the intervals do not overlap), in both ways: changed text and old text that is too short to be unique.
At 4B and 2B the ternary files copy as well as their teachers. The teachers skip the edit call more often (27, 26,
47 of 120 against 8, 18, 12). So tester A's 34% on the 9B is mostly a property of the ternary 9B, not of small size.
The 2B (either file) changes or leaves out text in about half of its calls.

## 2026-10-08 04:10 - S3a result: edit-call repair, offline gate (bench/edit_repair_eval.py)
| Model | Rejected before | After the repair | Repaired | Broke an exact call |
| --- | --- | --- | ---: | ---: |
| 4B ternary | 23 (23%) | 21 (21%) | 2 | 0 |
| 2B ternary | 52 (48%) | 38 (35%) | 14 | 0 |
| 9B teacher | 6 (6%) | 5 (5%) | 1 | 0 |
| 4B teacher | 25 (27%) | 15 (16%) | 10 | 0 |
| 2B teacher | 35 (48%) | 24 (33%) | 11 | 0 |

The 9B ternary run did not save its calls, so it has no row. It cannot pass anyway: at most 13 of its 28
rejections are content mismatches, and the repair fixes only the indentation kind (bench/edit_mismatch_kinds.py:
the 2B's mismatches are 31 changed or invented text, 14 indentation, 4 lines left out).
Decision: the gate (half of the rejections gone on the 9B or the 4B) is not met. The repair is not adopted as a
default. It never broke an exact call, and on the 2B it removes about a quarter of the rejections, so it stays in
layer/edit_repair.py as an option for the 2B (not made a default here).

## 2026-10-08 06:40 - S3b result: presence 1.5 and exact copying (results/<size>/exact_copy_pp/)
Same 120 items and seeds as S2b, presence 1.5 instead of 0. Rejected share of edit calls, 95% Wilson intervals:

| Model | Presence 0 | Presence 1.5 | Change | Not an exact copy (0 -> 1.5) | Placed as asked (0 -> 1.5) |
| --- | --- | --- | ---: | --- | --- |
| 9B ternary | 25.0% [17.9, 33.8] | 33.6% [25.4, 43.0] | +8.6 | 13 -> 27 | 57 -> 45 |
| 4B ternary | 22.5% [15.5, 31.6] | 35.3% [26.7, 44.9] | +12.8 | 11 -> 22 | 32 -> 34 |
| 2B ternary | 48.1% [39.0, 57.5] | 54.5% [44.8, 64.0] | +6.4 | 49 -> 52 | 10 -> 7 |

Reading (rule of Plan S3): the 4B rises by 10 points or more, so the rule is met. All three sizes move the same
way, and the rise comes from changed text (not an exact copy), as the misspelling hypothesis says. The 9B at
presence 1.5 (33.6%) is the same as tester A's 34% in their PatchEval traces, which used presence 1.5.
Decision: build "presence penalty inside the thinking only" in the engine (the answer and its tool calls copy
freely), then measure it on HumanEval medium (cap hits, the reason for presence 1.5) and on this probe.
S3a on these runs (edit repair, bench/edit_repair_eval.py, no exact call broken): 9B 34% -> 25%, 4B 35% -> 27%,
2B 55% -> 43%. About a quarter of the rejections each time, never half: the S3a decision does not change.

## 2026-10-08 08:30 - G1 result: the dose ladder (results/<size>/dose_ladder/, receipts/dose_ladder.log)
Each HumanEval failure of the serve arm at medium, continued once from the model's own failed answer, greedy,
thinking on at medium. No continuation hit the cap (all 220 finished with stop).

| Size | Tasks | R0 "try again" | R1 + check the examples | R2 + doctest report (server) | R3 + hidden test (grader) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 9B | 13 | 8 | 2 | 6 | 6 |
| 4B | 12 | 4 | 4 | 5 | 4 |
| 2B | 30 of 76 | 2 | 2 | 5 | 7 |

On the tasks whose docstring examples fail on the failed code: 9B R0 4/5, R2 2/5; 4B R0 2/4, R2 2/4; 2B R0 1/20,
R2 5/20, R3 4/20.
Reading (rules of Plan G1): 9B and 4B: R3 - R0 < 3, so hints do not help at these sizes; on the 9B a plain retry
recovers 8 of 13, and "check against the examples" (R1) makes it worse (2 of 13). 2B: R2 - R0 = 3 and R2 is within 2
of R3, so the rule for the server-side example check is met, exactly at its threshold (small counts: 30 tasks, one
greedy run each).
Decision: build the example check in the layer for the 2B: when a coding answer fails the docstring examples of the
request, the layer sends one follow-up turn with the doctest report and returns the second answer. Measure it live
on the 2B (HumanEval medium, paired against the plain serve) before any default. For the 9B the useful signal is
different: a second look with no new information recovers most failures, but a server cannot know that an answer
failed without examples to run, so there is nothing to build from it yet.

## 2026-10-08 09:00 - Plan G1b: the example check, live on the 2B (written before any result)
Change: layer/example_check.py (layer flag --example-check, request field example_check). When a coding request
has a function stub with doctest examples and the final answer defines that function, the layer runs the examples on
the answer in its sandbox (the request's imports and helper code first; an example with no expected output passes
when it prints True; equal literal values pass). On a failure or a crash it sends one follow-up turn with the G1 R2
text and returns the second answer.
Offline (bench/example_check_eval.py on the recorded HumanEval answers): it fires on 26 of 32 checkable 2B failures,
and on passed answers only where HumanEval's own docstring is wrong (#47 on all sizes, #116 on the 2B).
Live A/B: 2B, served recipe, both arms through the layer (:8080), HumanEval 164 at medium, greedy, max 24576 tokens.
Arm A: layer defaults. Arm B: the same plus example_check. Same requests, so B differs from A only where the check
fired.
Reading rule: adopt as the 2B default if B - A >= +3 tasks and B breaks at most 1 task that A passed. Otherwise it
stays off. Also report: follow-ups sent, recovered, broke, and the time per task.

## 2026-10-08 09:10 - S3b-2: presence inside the thinking only does not fix copying; the serve fix is per request
Exact-copy probe, rejected share of edit calls (results/<size>/exact_copy{,_pp,_pt}/), 95% Wilson intervals:

| Size | Presence 0 | Presence 1.5 | 1.5 inside the thinking only (engine branch presence-think) |
| --- | --- | --- | --- |
| 9B | 25.0% [18, 34] | 33.6% [25, 43] | 32.7% [25, 42] |
| 4B | 22.5% [16, 32] | 35.3% [27, 45] | 30.4% [22, 40] |
| 2B | 48.1% [39, 57] | 54.5% [45, 64] | 51.5% [42, 61] |

Reading: taking the penalty out of the answer gives back 1 to 5 points of the 6 to 13 that presence 1.5 costs. The
damage happens in the thinking: the model rewrites the code lines it plans to copy, and the answer copies the thinking.
The switch is not adopted (it stays an engine option, `--presence-thinking-only`, branch presence-think ada68d10e).
Why presence 1.5 was used: runaway thinking. In the served recipe the thinking budget and its forced close already stop
it (HumanEval medium cap hits, serve arm, presence 0 / 1.5: 9B 0 / 0, 4B 0 / 0, 2B 1 / 1; without the budget, raw arm,
9B 16 / 1). HumanEval medium, serve, presence 0 / 1.5: 9B 151 / 153, 4B 152 / 146, 2B 88 / 95.
Decision:
1. The serve default stays presence 0 on all sizes (start-small.ps1 already).
2. Build in the layer: a request that offers tools and sends a presence penalty above 0 gets 0 (harness-proofing, as
   for effort words; the request field "keep_presence": true opts out). Measured effect for agents whose client sends
   1.5 (as tester A's client did): edit-call rejections 9B 34 -> 25%, 4B 35 -> 23%, 2B 55 -> 48%.
3. The 2B without tools: presence 1.5 adds 7 HumanEval tasks (88 -> 95). Candidate per-size default for plain requests;
   decide with the G1b result (the example check also targets the 2B's plain coding).

## 2026-10-08 10:10 - G1b result: the example check is adopted for the 2B (results/2B/humaneval_layer{,ec}_medium/)
2B, served recipe, both arms through the layer, HumanEval 164 at medium, greedy: A (layer defaults) 86/164,
B (+ example check) 90/164, B - A = +4. Recovered: HumanEval/14, 51, 54, 61. Broke: none.
Rule of Plan G1b (B - A >= +3 and at most 1 broken): met. Decision: start-small.ps1 turns the check on for the 2B
(model file name with -2B-); BONSAI_EXAMPLE_CHECK=0 turns it off, =1 turns it on for any size.
Cost: the whole run took 3,046 s against 1,185 s. Each failed answer gets a second full answer at medium thinking, and
every coding answer with docstring examples runs once in the sandbox. Only requests that carry a function stub with
doctest examples pay it; other requests are unchanged. Not measured yet: the 4B and the 9B (the check fires on few of
their answers: 3 of 5 and 5 of 7 checkable failures offline).

## 2026-10-08 22:55 - Plan S3a-live: the edit repair through the layer (written before any result)
The offline gate scored layer/edit_repair.py on recorded calls. This arm checks the live wiring (938001d): the
exact-copy probe through the layer, 2B and 4B ternary, same 120 items and seeds, layer on in both arms, edit repair
off (er0) and on (er1). The repair runs after sampling, so with the same seeds both arms should sample the same calls.
Pass: on each size, er1's rejected count equals bench/edit_repair_eval.py run on er0's calls (within 1, for a call
that sampling changed), and no exact call is broken. A pass confirms the option works as measured; the S3a decision
(not a default; an opt-in 2B option) does not change. A fail is a wiring bug to fix before anyone turns it on.

## 2026-10-09 02:10 - S3a-live result: the edit repair works through the layer as measured (results/<size>/exact_copy_layer_er{0,1}/, receipts/exact_copy_er.log)
| Model | Rejected, repair off (er0) | Repair on, live (er1) | Offline score on er0's calls | Broke an exact call |
| --- | --- | --- | --- | ---: |
| 2B ternary | 54 / 105 (51%) | 37 / 105 (35%) | 37 | 0 |
| 4B ternary | 23 / 94 (24%) | 21 / 94 (22%) | 21 | 0 |

Same seeds gave the same calls in both arms (same edit-call and no-call counts), and the live counts equal the
offline ones exactly. Pass (Plan S3a-live): the option works as measured. The S3a decision does not change: not a
default; on the 2B it removes a third of the rejections (17 of 54), an opt-in option (BONSAI_EDIT_REPAIR=1).

## 2026-10-09 09:55 - Plan G2: a second-method check for computation requests (written before any result)
Evidence: the exact-work suite, computation family, behind the layer: 1-bit 9B 3 of 15, its teacher 13 of 15. The
1-bit 9B's misses are near misses of the algorithm, not copy errors (the true values never appear in its traces): the
distinct-LCS count (17001 for 17012, 16001 for 16006), off-by-one (23 for 24, 9 for 10), rounding (1245457 for 1245458).
Change (layer, opt-in `--check-note` / request field `check_note`): for a request without client tools, one sentence at
the end of the first user message: check the result with a second, independent method in run_python (brute force on a
small case, or a direct count) and fix the first method if they disagree.
Arm: suite computation family (15 items: 5 tasks x 3 seeds), 1-bit 9B, layer (A) vs layer + check (B) on the same
llama-server, paired, same seeds (bench/run_g2.sh, results/9B/g2_computation/).
Reading rule: adopt for the 9B if B - A >= 3 of 15 and B loses at most 1 item that A wins. Otherwise not adopted. Also
report completion tokens and time per item (the cost of the second method).

## 2026-10-09 10:20 - Note: repeated interpreter rounds are rare (bench/interp_dup_count.py, suite traces, layer arm)
Question (from an outside interference-search result: 83% of a small model's programs behaved like one already seen):
does the layer's run_python loop waste rounds on repeats? Only the computation family uses it (coding and workspace use
the suite's own tools). Rounds that repeat an earlier round's code: 0-3%; new code with the same output: 2-12%. Not
worth a layer change. The visible difference is the number of rounds: 1-bit 9B 73 / 4B 74 / 2B 87 over 15 requests
(cap of 12 hit 3-4 times each) against the teachers' 17 / 52 / 32. The 1-bit models iterate more, without repeating:
the same weakness Plan G2 tests (the method, not the copy).

## 2026-10-09 10:40 - G2 result: the check note meets its rule on the 1-bit 9B (results/9B/g2_computation/, receipts/g2.log)
Computation family, 15 items, paired, same seeds: layer 7/15, layer + check 10/15; check wins 3 (digits 2, lcs 1),
loses 0. Cost: completion tokens 169,762 -> 269,052 (+58%), time 1,249 -> 2,073 s (+66%); 3 sales runs with the
check gave no final answer (they did not pass without it either). Rule met (B - A >= 3, losses <= 1): adopted for the
9B, subject to G2b.
Caveat: the plain layer arm scored 3/15 on the same items in the 9B suite run of 2026-10-08 and 7/15 here, so the
run-to-run spread is as large as the effect.

## 2026-10-09 10:40 - Plan G2b: confirmation on new instances (written before any result)
Same arms on new computation instances: the five tasks at seeds 4, 5, 6 (15 items), 1-bit 9B. Keep the G2 adoption if
B - A >= 2 and losses <= 1 here too; otherwise the check note goes back to opt-in. Also run the 4B (same plan) to see
whether it transfers; the 4B gets no decision from this run.

## 2026-10-09 11:05 - G2b paused (other GPU work first)
Stopped at 9 of 30 runs (9B), the 4B not run. Partial results in results/9B/g2b_computation/ are kept but not read
against the rule; G2b runs again from the start when the small-model work resumes. Until then the check note stays opt-in.

## 2026-10-10 00:40 - G2b restarted from the start, as the pause note says
The first part (9 runs, 10-09, engine 5251968b0) and the runs added tonight between other GPU jobs (engine d90e35528)
were in one results file. The pause note says G2b runs again from the start, so that file is kept aside as
results/9B/g2b_computation.mixed-engines-20261010/ and is not read against the rule. G2b runs again on 9B and 4B,
engine d90e35528 (the 27B product bin), same plan bench/plans/computation_b.json, same seeds and rule.

## 2026-10-10 02:55 - G2b result: the check note does not hold on the 9B; it stays opt-in (results/<size>/g2b_computation/)
Clean run, one engine (d90e35528), seeds 4-6, five computation tasks, paired arms layer (A) vs layer + check note (B).
- 1-bit 9B: A 11/15, B 11/15, 3 wins / 3 losses, tokens +16 % (302k -> 350k). Rule (B - A >= 2, losses <= 1): NOT met.
  With G2 (7 -> 10 on seeds 1-3, where the plain arm had scored 3/15 the night before) the effect is within the
  noise of these 15-item sets. The check note stays opt-in (`--check-note`).
- 1-bit 4B (no decision by plan): A 7/15, B 10/15, 3 wins / 0 losses, tokens +46 % (237k -> 347k). A hint that it
  helps the weaker model; a 4B-only plan with more seeds would be needed before any default.

## 2026-10-10 03:05 - Plan G2c: the check note on the 4B only (written before any result)
G2b gave the 4B 7 -> 10 of 15 with no loss, but that run had no decision for the 4B and 15 items carry noise of
about +-3. G2c: same arms (layer vs layer + check note), 1-bit 4B, the five computation tasks at new seeds 7-12
(30 items, bench/plans/computation_c.json), engine d90e35528. Rule: make the check note the 4B default if
B - A >= 4 of 30 and losses <= 2; otherwise it stays opt-in for every size. Token cost is reported, not gated.

## 2026-10-10 05:02 - G2c result: no default for the 4B either; the check note stays opt-in (results/4B/g2c_computation/)
1-bit 4B, seeds 7-12, 30 items: layer 19/30, layer + check note 21/30, 7 wins / 5 losses, tokens +78 % (423k -> 753k).
Rule (B - A >= 4, losses <= 2): NOT met. Per task: digits +2, weblog +2, lcs -2, sales 0, knapsack 0. Over G2, G2b and
G2c the note moves single tasks both ways at a large token cost; the G2b 4B hint (+3, 0 losses) did not hold.
The check-note line of work is closed for these sizes.

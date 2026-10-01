# Bonsai quality investigation: decision log (append-only)

Owner: Claude on the serving PC, from 2026-09-29 ~00:40 local, unattended overnight (Cary asleep, authorized
to run experiments). Evidence bundle: evidence/ (from Bonsai-takeover-20260929.zip), handoff BONSAI-TAKEOVER.md.

## 2026-09-29 00:45 - state at takeover
- No llama-server process and no cloudflared process. No reboot (last boot 2026-09-27 02:55), no Application-log
  crash events mentioning llama. The A window (PID 18008/12868), old windows 7408/5984 and tunnel 10392 are all
  gone: most likely closed by hand. GPU idle (213 MiB). The trycloudflare URL in the handoff is dead.
- Decision: I own the GPU tonight. Keep the tunnel DOWN during experiments so no outside client shares the one
  slot; restart A + tunnel before morning and record the new URL.

## 2026-09-29 00:50 - H1: empty-thinking history in tool loops
Observation (template ac4c9d7d..., lines "preserve_thinking is undefined or preserve_thinking is true"):
every assistant message is rendered as `<think>\n{reasoning_content}\n</think>\n\n{content}{tool_calls}`.
The Mac harness (and the author's, and most OpenAI clients) never send reasoning_content back
(spec-ab-v1/runs-A/*/private/requests.json: assistant messages carry only content + tool_calls). So in a
12-step tool loop the model sees 11 of its own turns with EMPTY think blocks, and has lost the plan it made.
The template's default says the model is trained with preserved thinking; the served history is
off-distribution. Side effect: the rendered prefix no longer matches what was generated, so the KV cache is
invalidated at the first assistant turn every step (A logs: f_keep 0.65).
--reasoning-preserve cannot fix this (it only sets template vars; default already preserve). The client
threw the text away.
Hypothesis: restoring the model's own reasoning in the history improves multi-step task correctness.
Test: same tasks, same seeds, arm P0 = history as clients send it (no reasoning_content), arm P1 = history
with each assistant turn's own reasoning_content re-attached. One variable. If P1 wins, implement it
server-side (cache reasoning by server-generated tool_call id) so clients need no change.
Tasks: host-simulated stateful tool environments (no model code is executed on this host; the handoff forbids
running generated code without confinement), deterministic state graders.

## 2026-09-29 01:25 - H1 pilots: ceiling, no discriminating power yet
Host-simulated tool tasks (bench/envs.py: invoice, dedupe, ledger, chain, copy and 3-4x larger H variants with
joins and chained reversals) and regex debug loops (bench/regex_env.py: date, ipv4, semver, time; hidden
held-out grading) under the A config, arm P0 (clients' history): 21/23 full passes. Only failures: 'copy'
(exact byte copy) 0/2, both genuine model copy errors (dropped the word "dollar"; U+2028 -> space). Checked the
serving path for the copy failures: /tokenize->/detokenize round-trips U+2028, U+0085, tabs, trailing spaces
losslessly; the XML tool-arg PEG parser takes string values verbatim up to "\n</parameter>\n" (no trim);
the only trimming helper (safe_args_parse, which also has an off-by-one) is dead code. Not a serving defect.
A ceiling baseline cannot show a rescue, so H1 on these tasks is parked, not rejected.

## 2026-09-29 01:35 - H2: the reasoning budget force-closes the design turn of the failed tasks
Evidence (spec-ab-v1/runs-A responses): per-turn reasoning_content chars. Exactly two of 58 A responses ended
with the budget's forced closure, and they are the first turns of the two functionally failed tasks:
  bundle-01/11729 step 1: 63,381 chars, 26,179 generated, reasoning ends "...CRC + ISIZE in theNow produce the complete answer."
  bundle-01/28411 step 1: 55,705 chars, 21,867 generated, ends "...[A-Za-z0Now produce the complete answer."
The closure is spliced mid-word with no separator. Both tasks then failed (tar checksum; bytearray crash).
Checklist first turns reasoned 41.5k and 24.9k chars and closed on their own (functionally correct).
Server default --reasoning-budget 20480 and the Mac request both used 20480, so any client gets this cutoff.
Hypothesis: on hard problems the 20480-token cap truncates planning and lowers correctness.
Constraint: no confinement on this PC (no Docker/WSL/WASM runtime, no admin), so model-written programs are
NOT executed here; the bundle task cannot be regraded locally.
Test design: host-gradable hard single-turn problems with brute-force integer answers; arms B20 (budget 20480)
vs B40 (budget 40960); max_tokens 49152 in BOTH arms; everything else = A profile. Pilot first to confirm the
problems push thinking past 20k tokens (otherwise the arms are identical and the test is void).

## 2026-09-29 01:26 - H2 pilot + frozen plan
Pilot (B20, seed 1): knapsack forced (20732 tok) correct; digits forced (20497 tok) WRONG; paths 7851 tok correct;
schedule 3630 tok correct. Knapsack and digits exceed the budget -> used for the comparison.
Frozen plan bench/H2-plan.json sha256 4ea4fd3b056459444f982db2dd04fd7a4f9b1b01f440aab556ace558033b8061: knapsack+digits seeds 11-18,
B20 vs B40, alternating arm order, max_tokens 49152 both. 32 requests.

## 2026-09-29 02:20 - side findings while H2 runs
- --backend-sampling is inert for every thinking request: common/sampling.cpp:422-425 disables backend sampling
  whenever a reasoning budget is active (default 20480), and :416-419 whenever a grammar is active (tools). All
  A-profile generations are CPU-sampled. GPU-sampler correctness is therefore not a suspect for these failures.
- Budget closure mechanics (common/reasoning-budget.cpp): at budget exhaustion the sampler forces
  message tokens + end tag on the very next token (waits only for UTF-8 completion), so the message is spliced
  mid-word. Pilot digits-1 shows the cost: forced mid-DP ("...=1870+940=281Now produce the complete answer."),
  then answered 42847 (truth 54305).
- H1 mechanism probe prepared (bench/replay_h1.py, H1-replay-plan.json): 6 real A repair points right after a
  failing run_python (next-turn reasoning in A was 64-1777 chars), P0 vs P1 x 2 reps. Runs after H2.

## 2026-09-29 03:40 - server-side fix for H1 built (not deployed, not yet a claim)
Fork branch reasoning-cache (local %TEMP%\combo-src): ab2510322 + 8d7efdb68 + 770906f60 on c8b8993a6.
--reasoning-cache N (default 0 = off): process-wide LRU of generated reasoning keyed by server tool-call id
(and by >=64-char final content); fills empty reasoning_content of returning assistant turns before rendering.
Incremental build in %TEMP%\combo-build: ggml*.dll, llama.dll, mtmd.dll byte-identical to deployed; only
llama-common.dll, llama-server-impl.dll, llama-server.exe changed. Staged separately in
bin-rc770906f\ (deployed bin\ untouched; pre-build outputs saved in %TEMP%\combo-build-bin-c8b8993).
Provenance note: --version still reports b10768-8ecc788d5 because this build tree regenerates build-info only
at CMake configure time. So the stamp alone never proved the deployed binary was "dirty"; it proves only the
configure-time HEAD. The byte-identity of the unchanged modules is the stronger evidence.

## 2026-09-29 04:45 - H2 result (frozen plan cd19824c..., 32/32 complete, 0 infra errors)
Paired by (kind, seed), knapsack + digits seeds 11-18:
  B20 (budget 20480): 8/16 correct, forced closure 16/16, mean 21.6k tokens, mean 253 s
  B40 (budget 40960): 13/16 correct, forced closure 12/16, mean 40.5k tokens, mean 483 s
  wrong->correct 5 (digits 11, 14, 17; knapsack 11, 15), correct->wrong 0, both right 8, both wrong 3.
  Exact one-sided sign test on the 5 discordant pairs: p = 0.031.
Every B20 miss was a forced closure. Interpretation: on problems whose natural thinking exceeds 20480 tokens,
the default budget is a direct correctness limiter; doubling it rescued 5/8 misses with no losses, at ~1.9x
tokens and wall time on those problems only (problems that finish under 20480 are unaffected by definition).
Limits: two problem families from one generator file, 8 seeds each; a development result, not a population
estimate. Next: fresh-variant transfer check on two new families (lcs, grid; added after the plan was frozen).

## 2026-09-29 04:49 - transfer check frozen
Pilot: lcs-21 B20 forced (20726 tok) WRONG; grid-21 B20 11354 tok (no trip) correct.
bench/H2-transfer-plan.json sha256 bbcd017579b8e76ce9f1197776bce54931bc3a812023c88b121b35f98f336d1d. Gate declared before running:
>=2 wrong->correct and 0 correct->wrong on lcs; grid (no trip) unchanged.

## 2026-09-29 06:05 - transfer check result (H2-transfer-plan, 16/16 complete, 0 infra errors)
lcs seeds 21-26: B20 0/6, B40 1/6 (seed 26 wrong->correct), correct->wrong 0, both wrong 5. All lcs requests but
one (B40 seed 22, 31.7k) hit the budget in both arms: the family is beyond the model at 40960 too (often the
LCS length is right and the distinct-count is wrong, e.g. 17001 vs 17010). Declared gate (>=2 rescues) NOT
met: transfer is not demonstrated. Floor effect, not a loss. Caveat: lcs-21 B20 was also the pilot request
(identical bytes, identical answer).
grid seeds 23, 25 (no trip): identical outputs in both arms (same token counts, same answers, both correct):
a larger budget does not touch requests that finish under the smaller one.
Next: H1 replay probe (bench/H1-replay-plan.json).
CORRECTION (06:07): the grid control was written up before its last request finished. grid-23: identical in
both arms (6230 tokens each). grid-25: B40 6773 tokens, B20 7342 tokens, both correct. Neither was forced, so
the budget did not act; the difference is run-to-run decoding nondeterminism (MTP verify batches; attention is
not batch-invariant), not a budget effect. Statement corrected to: no-trip requests are unaffected in
outcome; they are not guaranteed byte-identical.

## 2026-09-29 06:30 - H1 replay probe result: mechanism NOT supported
12 pairs (6 real A repair points right after a failing run_python x 2 reps), P0 (history as sent) vs P1 (own
reasoning re-attached): next-turn reasoning P1 > P0 in 5 pairs, P1 < P0 in 7 (one-sided sign p = 0.81);
median reasoning 508 vs 486 chars; next action write_file 9/12 in both arms. Restoring past reasoning does
not make the model think more at repair turns. H1 (as a thinking-suppression mechanism) is rejected on this
evidence. --reasoning-cache stays an unmerged, opt-in branch with NO quality claim. (Its only demonstrated
property would be prompt-prefix reuse, a speed matter, not measured here.)
Plan for remaining time: (1) functional check of the reasoning-cache build (so the branch is known to work),
(2) restore pinned A, (3) fresh-seed replication of H2 on the same two families (seeds 31-34), frozen now.

## 2026-09-29 06:19 - reasoning-cache functional check PASS; A restored; replication frozen
bin-rc770906f + --reasoning-cache 256 (temporary, PID replaced): check_rcache.py on -> restored=true,
empty_think=false, foreign_id_leak=false. Pinned A restored with switch.ps1 -Arm A (PID 16380, bin\, spec on).
bench/H2-replication-plan.json sha256 3392a8c2936f41565abf07c3f471968ac8b57a7fba0b12a6d2a93e0e244cedf1: knapsack+digits seeds 31-34,
gate >=2 rescues and 0 losses, declared before running.

## 2026-09-29 07:22 - check-in (Cary): candid optimism review, recorded before the replication finished
Replication so far: 4 pairs complete, 0 rescues, 0 losses (knapsack 31, 32 both right; digits 31, 32 both
wrong), knapsack 33 in progress. Self-assessment: the H2 p=0.031 comes from families selected because they
overflow the budget (best case), transfer failed its gate, replication trending null -> the 5/16 rescue rate
is likely an overestimate. Defensible claim: the cap truncates mid-computation (observed directly) and a larger
cap never cost a correct answer in any pair; magnitude uncertain, possibly small.

## 2026-09-29 08:10 - replication result: gate NOT met; final decision
H2-replication (knapsack + digits seeds 31-34, 16/16 complete, 0 infra errors): B20 4/8, B40 4/8, rescues 0,
losses 0 (knapsack 31-34 right in both; digits 31-34 wrong in both). Declared gate (>=2 rescues) NOT met.
Descriptive only (not a declared test): across all 32 budget pairs, 6 wrong->correct and 0 correct->wrong.
On digits misses B40 answers were often much closer to the truth (39536 vs 39626; 42486 vs 42371) than B20
(9673; 37118), consistent with truncation, but closeness was not a declared metric.
DECISION: no default change. The 20480 -> 40960 budget is NOT promoted: development effect did not replicate on
fresh seeds or transfer to a new family. Retained as a lead. What stands: (a) the forced closure truncates
mid-computation (observed directly); (b) a larger budget never cost a correct answer in 32 pairs; (c) cost ~2x
tokens on capped problems. Launcher -n fix stays on branch quality/think-budget (no-op at default budget).
H1 rejected. --reasoning-cache: works, no quality claim, unmerged. No serving defect found in the paths checked.

## 2026-09-29 08:30 - next round (Cary: full-auto research). Idea 1 killed by data before building
Arithmetic census of 68 saved puzzle traces (bench/arith_census.py + strict binary re-parse): unambiguous
a(+|-|*)b=c statements: digits 1228 (17 flagged), knapsack 933 (113 flagged), and the flagged ones are
notation (weight ranges "30-33 =152", value+weight pairs "129+17=51", inclusive counts
"600000-682084 = 82085" which is correct). Genuine arithmetic slips ~0; correct traces "slip" more than wrong
ones (parser noise signature). -> "verified-arithmetic decoding" would fix nothing. Not built.
Misses look like DP bookkeeping/transcription errors, consistent with the copy task's 0/2.
H3 frozen: bench/H3-plan.json sha256 444460b96cdc22efaa8cf3f007d5bf1e297a0670a8f26832c760b1abbe015093: temperature 0.6 vs 1.0 at budget
40960, knapsack+digits seeds 41-46, gate >=2 rescues and 0 losses.

## 2026-09-29 10:50 - H4 frozen (runs after H3): does q8_0 KV cost exact recall?
Motivation: misses look like transcription/bookkeeping errors, and the copy task failed 2/2.
Arms (experiments/spec-ab-20260928/run-kv.ps1): pinned A minus the tier (-c 49152 all in VRAM, no
--kv-vram-cells, no --spec-draft-n-max-tail), target KV q8_0 vs f16 (draft KV q8_0 in both). Nothing else.
Probe (bench/copyprobe.py): 200-row table of labelled 6-digit values, filler of 0 / 4000 / 16000 words, copy 20
named values; thinking off, temperature 0; 12 items per distance -> 720 graded values per arm, paired by item.
Hash of probe + arm script: 2ff1610e59c67d212f1e316fed8edf7986aaae8328b60e3bd9aad2fc874b0b56.
Gate: f16 better than q8_0 by >= 1% of all values AND one-sided sign test over the 36 paired items p < 0.05.
Otherwise q8_0 KV is cleared as a recall cost at these depths.

## 2026-09-29 11:25 - H3 result: temperature 0.6 REJECTED
knapsack+digits seeds 41-46 at budget 40960: T1.0 10/12, T0.6 9/12; rescues 0, losses 1 (digits 45: 141153
right at 1.0, 141173 at 0.6), both right 9, both wrong 2. Gate (>=2 rescues, 0 losses) not met.
Side effect only: T0.6 ended thinking earlier (forced 5/12 vs 9/12; mean 34.2k vs 39.7k tokens; 390 vs 487 s).
Consequence: the confidence-gated-greedy sampler idea (premised on lower temperature helping) is dropped.
Next: H4 (KV precision recall probe), as frozen above.

## 2026-09-29 11:45 - H4 result: q8_0 KV cleared (ceiling); f16 arm not run
q8_0 arm (run-kv.ps1 -Kv q8_0, 49152 ctx all-VRAM): 720/720 exact values (240/240 at each of 3.3k, 7.6k,
20.6k-token prompts). f16 cannot exceed a ceiling, so the frozen gate is unreachable; the f16 run was skipped
(decision recorded before running it, to save GPU time). Caveat: probe is thinking-off retrieval, depth <= 21k;
it does not test the tiered range past 113k.
Reading: exact recall from context is intact. The digits/knapsack misses originate inside long self-generated
reasoning (bookkeeping), not in reading context through a lossy cache.

## 2026-09-29 11:35 - H5 frozen: compute allocation (one long sample vs vote of three short)
bench/H5-plan.json sha256 9dbff4e8776173c8d75920fc98af15a630f233ba69da3165dabdce7d594b2f8f. S1 = budget 40960 x1; V3 = plurality of 3
samples at budget 12288 (seeds +0/+1000/+2000), ~equal tokens. Ties resolve to V12a (no credit for ties).
knapsack+digits seeds 51-56. Gate: >=2 rescues and 0 losses for V3 vs S1.

## 2026-09-29 14:31 - H5 result: vote of 3 short samples REJECTED
knapsack+digits seeds 51-56 (48/48 requests, 0 infra errors). S1 (one sample, budget 40960) 9/12; V3 (plurality
of 3 samples, budget 12288 each) 6/12; rescues 0, losses 3 (digits 51, 54; knapsack 53), both 6, neither 3.
V3 cost more: 468k vs 410k tokens, 5579 vs 4987 s. Individual 12k samples on digits: 1/18 correct, answers far
off (e.g. 118600 vs 53953); S1 digits misses were near-misses (31274/32717, 23438/23440, 53984/53953).
Reading: on these problems accuracy is limited by reasoning length, not sampling variance; voting cannot fix
answers that are never right. Across experiments: 12k << 20k <~ 40k (dose-response, descriptive).
H6 frozen: bench/H6-plan.json sha256 baf8520e00bf76db3f96c917ea1b688683ec7f60bf7764d373119113a07e484d: digits seeds 61-66, budget 40960 vs
81920, max_tokens 90112 both. Gate >=2 rescues, 0 losses.

## 2026-09-29 16:35 - H6 result: budget 81920 vs 40960, gate NOT met; wave closed, server shut down
digits seeds 61-66 (12/12, 0 infra errors): B40 5/6 (forced 5/6, mean 41.5k tok, 509 s), B80 6/6 (forced 1/6,
mean 51.3k tok, 635 s). Rescues 1 (seed 62: 103266 -> 103292), losses 0, both right 5. Gate (>=2) not met;
these fresh seeds were mostly at the ceiling at 40960. At 81920 the model usually stops on its own (5/6 unforced
at ~40-52k), so most of the time the extra budget is not used.
Budget ledger across all budget comparisons (descriptive, not a declared test): larger budget rescued 7, lost 0
in 44 pairs (H2 5/0, transfer 1/0, replication 0/0, H6 1/0). Never promoted by a gate.
Per Cary: wave ends here. Pinned A was the running config; llama-server stopped to free the GPU.

## 2026-09-29 17:50 - resumed (Cary: GPU free). Pinned A restarted; H7 soft landing frozen
Pre-restart check: all 11 bin\ modules byte-identical to Handoff 1, model size/mtime unchanged, serve repo clean
on main. Pinned A started via switch.ps1 -Arm A (speculative on, slot idle).
H7 targets the one observed defect (mid-word forced closure). Emulated client-side on raw /completion (no
rebuild; the server budget sampler is inactive there: it needs reasoning_budget_start_tag, chat-only,
server-schema.cpp:391). Smoke test (schedule-1, budget 300): hard path spliced mid-sentence exactly like the
server; soft path finished the line, took the nudge, closed. bench/H7-plan.json sha256 267ea6c962ef20e64d7de35571fb3b1865326f47f78aa82155ab686a98983837:
H20 / H24 / S20 on knapsack+digits seeds 71-76, rotating order. Primary gate S20 vs H24 (compute-matched):
>=2 rescues, 0 losses.

## 2026-09-29 20:18 - H7 result: soft landing REJECTED
knapsack+digits seeds 71-76 (36/36): H20 8/12, H24 8/12, S20 7/12. Primary S20 vs H24: rescues 0, losses 1
(digits 73: 82127 right under both hard closes, 84056 with soft landing). H20 and H24 identical outcomes on all 12.
Mechanism: after the nudge the model concludes almost at once (S20 mean thinking 20348; forced only 1/12), so the
grace is unused. Closure style and +4k tokens do not matter; only substantially longer thinking moved results
(H2/H6). Server closure rewrite: not worth building.
H8 frozen: bench/H8-plan.json sha256 74f3913bfdf36b1ebb1e86e7cfba2c834f995674e36afd778ac5cd11f3a9cbfc: budget notice as a system message vs
none, both under today's 20480 closure, knapsack+digits seeds 81-86. Gate >=2 rescues, 0 losses.

## 2026-09-29 - H8 result: budget notice REJECTED; research wave closed
knapsack+digits seeds 81-86 (24/24, 0 infra errors): B20 6/12, N20 (system budget notice) 4/12; rescues 1
(knapsack 82), losses 3 (digits 82, knapsack 81, 85), both 3, neither 5. Forced closure 12/12 in BOTH arms:
the model does not adapt its method to a stated budget. Gate not met.
Wave closed as announced: single-shot serving/prompt levers are exhausted on this evidence.
Summary of all gated tests: H1 rejected, H2 dev pass but transfer + replication failed, H3/H5/H7/H8 rejected
(each with >=1 loss), H4 cleared (ceiling), H6 gate not met. Only consistent signal: substantially longer
thinking (40k+) helps on long computations (budget comparisons 7 rescues / 0 losses in 44 pairs, descriptive).
Pinned A left running.

## 2026-09-30 07:37 - Cary: "set up anything you need". Sandbox built; teacher downloading; E1 frozen
Downloads (official sources, checksums recorded): wasmtime 49.0.0 (PyPI); CPython 3.14.7 WASI build
(github brettcannon/cpython-wasi-build, sha256 2e064d3f..., lacks zlib, kept unused); CPython 3.12.0 WASI build
(github vmware-labs/webassembly-language-runtimes, tarball sha256 6c1cddbb... matches published, zlib built in);
Qwen3.8-27B-UD-Q4_K_M.gguf (huggingface unsloth/Qwen3.8-27B-GGUF, 16,464,440,224 B, expected sha256 322e194f...,
in progress; the existing models\donor\*.sparse.gguf is a sparse shell with no trunk data).
Sandbox tooling/wasi-python/sandbox.py: WASI preopens /usr/local/lib (read-only stdlib) and a fresh /work only;
no sockets or processes in WASI; 128 MB linear-memory cap; epoch timeout. canaries.py 12/12 PASS (stdlib incl.
tarfile/gzip/hashlib works; host key file, host root, ../ escape, stdlib writes, network, subprocess all denied;
infinite loop killed; 512 MB alloc -> MemoryError).
Prior evidence found in docs/QUALITY.md: Killy's census, teacher 25/34 vs Bonsai 15/34 on adversarial agentic
tasks, reasoning benchmarks ~equal (GSM8K 480/480, MATH-500 452 vs 461).
E1 smoke (knapsack-1, tool arm): wrote DP, ran it, verified by brute force, correct in 19.6 s / 1796 tokens
(vs ~250 s / 21k tokens and forced closure without tools). E1 frozen: bench/E1-plan.json sha256
e70a46e742271e61a28ad112377d2eb9f8c9785d61b009d647b30de438014ce0: NT vs CT, knapsack+digits seeds 91-96, gate >=2 rescues, 0 losses.

## 2026-09-30 08:29 - E1 result: code tool PASSES its gate (first pre-registered pass)
knapsack+digits seeds 91-96 (24/24): NT 5/12, CT 10/12; rescues 5, losses 0, both 5, neither 2; sign p = 0.031.
Cost: CT mean 2412 tokens / 31.7 s vs NT 19281 tokens / 223.8 s (8x fewer tokens, 7x faster).
The one CT miss (digits-91): first program printed the correct 25525; a cross-check method disagreed (25483);
the model spent all 8 responses reconciling and never emitted ANSWER. Response cap, not a wrong computation.
Teacher download complete: sha256 322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482 (matches).
E1 transfer frozen: bench/E1T-plan.json sha256 f3aac5bed8669deb8b94b703144c0c182a78e1d63536267840841d9ca6b86689: lcs + subsets seeds
31-36, NT vs CT, gate >=2 rescues, 0 losses.

## 2026-09-30 09:45 - E1 transfer PASSES: the code-tool gain is confirmed on unseen families
lcs + subsets seeds 31-36 (24/24): NT 6/12, CT 11/12; rescues 5 (all lcs: 31, 33, 34, 35, 36), losses 0,
both 6 (all subsets), neither 1 (lcs-32: CT used all 8 responses without a final ANSWER); sign p = 0.031.
lcs went 0/6 -> 5/6 (the family that beat the model even at 40960 thinking tokens in H2T).
CT mean 10.5k tokens / 131 s vs NT 20.9k / 236 s.
Status: first intervention to pass a development gate AND a fresh-family transfer gate. Lesson: the quality
lever is moving long bookkeeping out of the model's reasoning into executed code. Both CT misses so far were
the 8-response cap hit while cross-checking, not wrong computations.
Next: teacher reference (compression question), then a server-side built-in sandboxed interpreter so every
client gets the gain without harness changes.

## 2026-09-30 10:10 - C1 frozen: teacher reference (compression question)
Teacher running via run-teacher.ps1 with Bonsai's template (same prompt tokens). Pilot knapsack-11 B20: teacher
correct, 7358 tokens, not forced, 4.7 tok/s decode, 1574 s. (Bonsai same request: forced at 20480, wrong; correct
at 40960 with 42.5k tokens.) bench/C1-plan.json sha256 7464538c3ad1f69bf40a89a5ef04645422c7d8d619fe37cc48b564aedc141597: remaining 7 of
knapsack+digits seeds 11-14 at B20. Declared: efficiency cost if teacher median tokens < 0.5x Bonsai B20 median
AND teacher accuracy >= Bonsai B20 accuracy. Built meanwhile (untested): tooling/interpreter_proxy.py.

## 2026-09-30 10:19 - agentic port validated; E2 frozen (runs after C1)
bench/contract_grade.py: runs a candidate solution.py in the WASI sandbox on the hidden development request
(twice for bundles) and applies the original frozen oracles. Validation: regraded Codex's 4 saved A-baseline
coding candidates -> 4/4 identical verdicts (invalid_tar, unrecoverable_json, 2x functional true).
bench/agent_contract.py: frozen Codex prompts/schemas, write_file/run_python on the sandbox, oracle grading.
E2 frozen: bench/E2-plan.json sha256 da3bc95d5e4b5acebe205178e36840404dbaa2eaf83d2351ff3a6f7422b02f9b: B20 vs B40 on dev-bundle-01 seeds
101-106 and dev-checklist-01 seeds 101-103. Gate on functional correctness: >=2 rescues, 0 losses.

## 2026-09-30 11:40 - C1 paused (order change only), E2 moved ahead
Teacher decode is too slow to finish C1 before E2 (knapsack-12: 4916 s, 21376 tokens, forced at 20480,
correct). Completed so far: knapsack-11 (pilot) and knapsack-12, both correct. C1 runner and chain stopped;
the in-flight teacher request (next item) is discarded (no record written, it will be re-run from the start).
Resume later with the same plan (run_puzzles.py skips completed items). Pinned A restored for the proxy test
and E2. No data dropped or selected.
Interpreter proxy end-to-end (tooling/interpreter_proxy.py :8081 -> pinned A): plain client request, knapsack-1,
no client tools -> correct 270; 1 sandboxed run; no tool_calls leaked to the client; 17.7k tokens, 95.6 s.
Proxy stopped afterwards (not part of the pinned config). E2 launched.

## 2026-09-30 14:12 - E2 result (gate not met) and H10 frozen
E2 (agentic budget, 18/18, 0 infra): functional B20 3/9, B40 4/9; rescues 1 (bundle-105), losses 0; task_success
1/9 vs 2/9. Bundle 0/6 vs 1/6; checklist 3/3 vs 3/3. Every bundle attempt in both arms hit the 12-response cap.
Gate (>=2) not met.
Trajectory review (bundle-103 B20, bundle-104 B40): the model hand-rolls tar headers / raw deflate, invents APIs
(tarfile.default, tarfile.STATREG), and debugs with 19-500-char reasoning per turn and one small probe per turn;
its own tests check its own idea of the format. A 15-line stdlib reference (bench/ref_bundle_solution.py)
passes the hidden grade in the same sandbox, so the task is solvable with correct API use.
H10 (Codex's untested "independent consumer" proposal; the contract itself names public feedback properties):
check_solution tool = original oracle on the disclosed public example only. bench/H10-plan.json sha256
480c964e1466985c31de865009c8488a8cbf9dd83cb119c7c191e26c12bb3d22: B20 vs CK on dev-bundle-01 seeds 111-116. Gate >=2 rescues, 0 losses.

## 2026-09-30 - H10 result: consumer check REJECTED; C1 resumed
dev-bundle-01 seeds 111-116 (12/12, 0 infra): B20 0/6, CK 0/6 functional; no discordant pairs. The model called
check_solution 0-1 times per attempt (4 of 6 CK attempts used it once, 2 never), and never recovered after a
failing verdict within 12 responses. Offering exact feedback does not help when the model does not seek it;
the bundle task is beyond this model at 12 responses under both arms (combined bundle record today: 1/24).
Contrast E1: on puzzles the model used run_python eagerly and gained a lot. Resuming C1 (teacher) now; pinned A
restored automatically afterwards.

## 2026-09-30 21:07 - E3 frozen and queued behind C1 (GPU never idle)
bench/E3-plan.json sha256 a003cd80668ee65f4c20a491459fdacaab30156b5c0f87db7793b16c6e2c9c8e: interpreter proxy no-harm check; DIRECT vs PROXY,
identical plain bodies, schedule/paths/grid fresh seeds; gate 0 losses. Starts automatically once C1 restores A.
Note: C1.log stayed stale (chain redirect), results are in bench/C1/*.json: 7/8 done at this point.

## 2026-09-30 22:05 - C1 result: declared efficiency test NOT met (by family: knapsack yes, digits no)
Teacher Qwen3.8-27B UD-Q4_K_M, Bonsai's template (identical prompt tokens), budget 20480, knapsack+digits seeds
11-14, vs Bonsai's H2 B20 records for the same requests. Teacher 6/8 correct, Bonsai 5/8. Forced closure 5/8 vs
8/8. Median completion tokens 21112 vs 21178 (ratio 1.00) -> declared test (ratio < 0.5 and acc >=) NOT met.
By family (descriptive): knapsack teacher 4/4, three unforced at 4.3k/7.4k/8.7k tokens, vs Bonsai 3/4 all forced
at ~21k (the extra teacher success is knapsack-11); digits identical: both 2/4, both forced 4/4.
Answer to "is compression to blame": partly, problem-dependent. On some problems the full-precision model
reaches the answer in a fraction of the thinking; on long DP both hit the cap equally. Consistent with Killy's
census (teacher 25 vs Bonsai 15 agentic, reasoning benchmarks ~equal). Teacher decode 4.4-4.7 tok/s offloaded.
Pinned A restored automatically 22:02; E3 started.

## 2026-09-30 22:45 - E3 result: interpreter proxy PASSES the no-harm gate
schedule/paths/grid fresh seeds (36/36, 0 infra): DIRECT 17/18, PROXY 18/18; losses 0, rescues 1 (grid-201).
PROXY mean 5096 tokens / 61.5 s vs DIRECT 6141 / 74.7 s. The model chose to use the interpreter in 16/18 proxied
requests; 0 tool calls leaked to the client. With E1 (+5 rescues, 0 losses, transfer confirmed) the proxy is
supported for computation-heavy work and harmless on work the model already does. Recommendation (Cary's call):
serve clients through :8081. Not deployed. Next: E4, proxy with client-defined tools (passthrough + no harm).
E4 frozen: bench/E4-plan.json sha256 ae29d0194cae28c7517bc355cfd1db721368395e483794f0364134bde7c4faf2, gate 0 losses.

## 2026-09-30 23:40 - E4 result: no-harm gate FAILED with client tools -> proxy policy changed
Workspace tasks with client-defined tools, seeds 201-203 (30/30, 0 infra): DIRECT 11/15 full pass, PROXY 10/15;
losses 2, rescues 1 (ledgerH-203); functional 11 vs 11. Passthrough itself was correct (client calls relayed,
no leaks). Losses: dedupeH-202 (interpreter run, one duplicate missed, patched with a 2nd update_rows batch ->
process violation); invoiceH-202 (interpreter on paginated invoice data -> wrong set). Mechanism: with client
tools the data lives in paginated tool results; to use run_python the model must retype it into code, and exact
transcription is its known weakness (copy task 0/2 night 1). In E1/E3 the data was small and in the prompt.
Policy change in tooling/interpreter_proxy.py: interpreter ON by default only for requests WITHOUT client tools;
requests with client tools pass through untouched (= E4 DIRECT arm by construction) unless they opt in with
"code_interpreter": true. E1/E3 conditions (no client tools) keep the interpreter, so their results still apply.

## 2026-09-30 23:46 - overnight queue (Cary asleep): E5 then E6, frozen
Chose quality experiments over the KV-prefetch kernel (speed-only, >113k contexts, multi-day).
E5 bench/E5-plan.json sha256 534786076827bdff472651bc9ff23c83ddb2ceee2596f4a7acd7080483796317: realistic CSV data questions (150-200 rows
in the prompt), DIRECT vs interpreter proxy (default policy, no client tools), sales seeds 301-312, truth
cross-checked 12/12 from the CSV text. Gate >=2 rescues, 0 losses.
E6 bench/E6-plan.json sha256 00b9ae50dbc4a11d7423f61086742acbd89d1c9a4639d28d2c0dea41260b70c3: dev-bundle-01, 12 vs 24 responses (only the
two limit sentences of the frozen prompt change), seeds 121-126. Gate >=2 functional rescues, 0 losses.

## 2026-10-01 02:43 - overnight results E5/E6; E7/E8 frozen and queued
E5 (CSV data questions, proxy vs direct, 24/24, 0 infra): PROXY 12/12, DIRECT 8/12; rescues 4, losses 0
(one-sided p = 0.0625); gate (>=2, 0) MET. Direct misses were bookkeeping near-misses (3570327 vs 3739909,
1818203 vs 1817773, counts off by one). Tokens ~equal (11992 vs 11104), wall ~equal. Third gated pass for code.
E6 (bundle 12 vs 24 responses, 12/12): functional R12 1/6, R24 0/6; rescues 0, losses 1: REJECTED. Bundle is not
turn-limited. Two R12 attempts never produced solution.py.
E7 bench/E7-plan.json sha256 : proxy vs direct on access-log questions
(weblog seeds 401-412, truth cross-checked; one degenerate question type replaced before freezing).
E8 bench/E8-plan.json sha256 : bundle with verified stdlib API notes vs
frozen prompt (seeds 131-136); every note claim verified in the sandbox Python 3.12 before freezing.
CORRECTION (02:54): the E7/E8 entry above was written before the plan files existed. A bad edit (literal
newlines inside a string in agent_contract.py) crashed the plan generation; the chain ran at 02:43 and both
runners failed immediately (no requests sent, no results). The hashes printed in that entry are of missing
files and are void. Fixed the edit; regenerated identical-content plans: E7 sha256 93d5529f0a71672b94a2c121c4dfe1c25a7dba3769124121b6122f95b1502f8a,
E8 sha256 4834d9cace73bafb5888c20a48bb27993bfed7445842f1a77b9e0d02dd7a2bee. Relaunched.

## 2026-10-01 05:30 - E7 (gate not met) and E8 (PASS, strongest result so far); E8R frozen
E7 (access-log questions, proxy vs direct, 24/24, 0 infra): PROXY 11/12, DIRECT 10/12; rescues 2 (408, 412),
losses 1 (411: proxy used all 8 interpreter rounds and the forced last round produced no ANSWER line). Gate
(0 losses) NOT met. Proxy much slower on this family (24.2k tokens / 256 s vs 8.6k / 94 s). Proxy issue to fix:
the final no-tools round must reliably yield an answer.
E8 (dev-bundle-01, verified stdlib API notes appended vs frozen prompt, 12/12): functional DOC 6/6, B20 0/6;
rescues 6, losses 0; one-sided p = 0.016. task_success 0/6 in both arms (every attempt ran to the 12-response cap
instead of stopping, so normal_completion is false), but the archives DOC produced are oracle-correct.
Bundle failures were an API-knowledge gap (invented tarfile APIs, hand-rolled formats), not a reasoning or turn
gap: more thinking (E2), more turns (E6) and a grader-backed checker (H10) all failed; accurate API facts fixed it.
E8R frozen: bench/E8R-plan.json sha256 f6607685892dc71faabb04a747126b08b36c3906b2f6a1f23ea88fd1aa32d456: same treatment on
dev-bundle-02 (different hidden request; reference solution passes it) with fresh seeds 141-146; gate >=2, 0.

## 2026-10-01 07:05 - E8R result: API-notes gain REPLICATES on a different hidden case
dev-bundle-02, seeds 141-146 (12/12, 0 infra): functional DOC 5/6, B20 0/6; rescues 5, losses 0, neither 1
(seed 145); one-sided p = 0.031. DOC also cheaper: 29.3k tokens / 346 s vs 45.7k / 548 s per attempt.
Combined E8 + E8R: with notes 11/12 functional, without 0/12. Gated pass in development and on a fresh hidden
case. Conclusion: the bundle failures were an API-knowledge gap; short, verified library facts in the prompt
fix them. task_success still 0 in both arms (attempts run to the response cap instead of stopping cleanly).

## 2026-10-01 10:19 - integrated layer built; product benchmark P1 frozen
Cary: ship the gains inside the server, test the product (not Marionette), raw vs integrated on the same API.
Built (tooling/, snapshot in research/.../layer/): apicards.py (cards generated by introspecting the sandbox
Python: constants, signatures, class fields; bundle task card ~6k chars, includes REGTYPE/USTAR_FORMAT/TarInfo
fields/gzip.compress mtime; no hand-written content), apilint.py (AST + runtime resolution in the sandbox:
missing module attrs, bad from-imports, unknown keyword args; validated: 0 warnings on 19 functionally correct
saved solutions and on the reference, flags every invented API in a synthetic file, but fires on only 4 of 43
failed saved solutions -> expected to be a minor contributor), interpreter_proxy.py integrated: cards + lint
for coding requests (lint notes appended to the matching tool result, idempotent), interpreter only without
client tools, final-answer nudge (verified on E7-411 with --max-rounds 1), SSE streaming passthrough.
Batch family ported; grading replay matches Codex's 4 batch receipts 4/4.
Repo: research log pushed (514107a, 4140420). Share card docs/img/quality.png.
P1 bench/P1-plan.json sha256 b001d17d0b01d061ca9b606d18f556ba8408f4d788f5520bbe49071f88ccfb3c: RAW vs PROD, 37 pairs. Gates: gain set net >= 4
with losses <= 1; regression set net >= -1.

## 2026-10-01 10:50 - P1 restarted after a sandbox harness fix (2 of 74 runs discarded)
Trajectory of the first PROD bundle attempt showed a harness defect: the sandbox's working directory was not the
workspace, so a model test doing open("solution.py") failed with FileNotFoundError (the Mac runner ran with the
workspace as cwd). Present in every earlier coding run in BOTH arms (comparisons stay paired and fair, absolute
bundle difficulty was inflated). Fix: sandbox.py also preopens the workspace as "." ; canaries now 14/14 (new:
relative paths resolve in the workspace; relative ../ escape still denied). The 2 completed P1 runs (bundle-01
seed 151, both arms functional false) are discarded and kept in bench/P1/ for the record. Same frozen plan
(P1-plan.json, unchanged hash) rerun into bench/P1b/.

## 2026-10-01 11:55 - P1b stopped (9 runs discarded): linter false positive found; P1c relaunched
While tallying failure modes for PrismML's report, the linter flagged "module 'solution' cannot be imported in
this runtime" 44 times across saved model test files: a FALSE POSITIVE (the test file imports the workspace's own
solution.py; the linter checks one file in isolation). My earlier validation only linted solution.py files and
missed it. In P1b's PROD arm this could have appended a false statement to tool results, so P1b is void.
Fix (tooling/apilint.py): import failures are silent; only names inside modules that do import are reported.
Verified: `import solution` -> no warning; `json.loadz` and `tarfile.STATREG` still flagged.
P1b partial (discarded, kept in bench/P1b/): bundle-01 151 neither, 152 neither, 153 PROD rescue.
Same frozen plan rerun into bench/P1c/.

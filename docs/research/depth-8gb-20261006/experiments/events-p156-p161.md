# Events, 2026-10-16 (range p156-p161)

Notebook entries in this range that are not experiments: releases, PRs, issue threads, decisions, incidents and
lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-16 08:40 CDT Records
P133-P155 merged (#148 ...)" to the entry "23:35 CDT PR #157 merged; PR #159 opened ..." (the next entry, "22:40 CDT bundle-20261017 published
(03:32:59Z) ...", is the next range), receipts/queue.log, the
receipts named below, the issue #138 thread and the PR list of this repo (titles and times). Numbering continues from
`events-p133-p155.md` (E38-E56). Times with "Z" are UTC (GitHub); "CDT" and other times are rig local time (UTC-5).
Notebook headings are the session's own times and run ahead of the clock in the evening (E65); where a queue log line
or a GitHub time exists, this file gives it. The GitHub posts of all sessions use the same account; "4070", "2060",
"kernel session" and "release session" name the session.

- [E57 The P133-P155 records (PR #148) and launcher PR #147](#e57-the-p133-p155-records-pr-148-and-launcher-pr-147)
- [E58 The restore crash chase: from P155 to the 0060p pool fix](#e58-the-restore-crash-chase-from-p155-to-the-0060p-pool-fix)
- [E59 layer_v2: early headers and SSE keep-alives; Marionette parked](#e59-layer_v2-early-headers-and-sse-keep-alives-marionette-parked)
- [E60 T2a-2, release-0060 / 0060t and bundle-20261016b](#e60-t2a-2-release-0060--0060t-and-bundle-20261016b)
- [E61 T3: the speed rule met, the gates failed, opt-in not default](#e61-t3-the-speed-rule-met-the-gates-failed-opt-in-not-default)
- [E62 The missed 0060p asks and gh_since.sh](#e62-the-missed-0060p-asks-and-gh_sincesh)
- [E63 P160 and the demo clip](#e63-p160-and-the-demo-clip)
- [E64 PR #157: review, fixes, merge; release-0062 plan; T1-d and T4](#e64-pr-157-review-fixes-merge-release-0062-plan-t1-d-and-t4)
- [E65 Corrections in this range](#e65-corrections-in-this-range)
- [E66 Lessons recorded in this range](#e66-lessons-recorded-in-this-range)

## E57 The P133-P155 records (PR #148) and launcher PR #147

| | |
| --- | --- |
| Date | Notebook entry "08:40 CDT Records P133-P155 merged (#148, docs only; agent-written, reviewed: no key / user name / ctrl bytes)." PR #148 merged 12:56:02Z (07:56 CDT); PR #147 opened 12:55:07Z |
| What | The records P133-P155b (this folder) merged as PR #148. "My launcher PR #147 closed as a duplicate of the 4070 #145 (merged; absolute-path fix). layer-slot-cache rebased on main (drops my launcher commit)." |
| Open notes from the records agent | "P150 160k gate wording (+4.4 % faster than the 3 % band), P140 11 vs 22 items, P119 / P120 results not in the notebook (P120 summary exists: 18 turns 133k-260k, 0 one-token)" |
| Links | PR #145; PR #147; PR #148; `events-p133-p155.md` |

## E58 The restore crash chase: from P155 to the 0060p pool fix

| | |
| --- | --- |
| Date | 2026-10-16 08:22 (P155 crash) to 21:44 (P158d pass); #138 posts 13:24:59Z to 02:46:06Z |
| P155 / P155b (2060) | After a fresh-server slot restore, a multi-ubatch continuation crashed ("ggml-cuda.cu:109: CUDA error") or read at 12.27 tok/s; P153's 33-token continuations had been fine |
| T1-e / T1-f (4070) | 13:38:58Z: "the restore crash does NOT reproduce on sm_89", restore at 131k + 5,478 new tokens in 11.2 s (~490 tok/s) with the 8 GB preset. 15:07:48Z: with GGML_CUDA_GDN_MMA_DISABLE=1 (the sm_75 GDN path) also no error |
| P157 (2060) | Fresh-server restore + 3,968 tokens at 131k: 12.2 tok/s x3 (sparse on or off); same process 135 tok/s; no crash in 4 runs |
| P157b (2060) | 64k: MTP on 24.0 tok/s, BONSAI_SPEC=0 212.6 tok/s; read as "the MTP draft context"; ask for a sidecar. (Later found: SPEC=0 also turned the shared pool off; E65) |
| Sidecar (kernel session) | 15:32:25Z: the slot save also writes the draft context's sequence state to `<file>.draft`; 16:44:34Z correction: the first commit only made the probe call on restore (restored nothing); fixed build product-slotdraft 303f01131 / t3-prefill 0f7a8e0ce; 16:49:40Z T1-h PASS on the 4070 |
| P158 = release-0060 R1 (2060) | FAIL: 5/5 MTP-on restores + ~4k crashed, with and without the sidecar; MTP off 213.67 tok/s (posted 19:34:07Z) |
| P158b (2060) | A 2060-only debug build (fprintf + fflush in ggml_cuda_error, source reverted after the build) named the call: "CUDA error: device not ready ... ggml-cuda.cu:654 \| cuMemSetAccess(start_ptr, reserve_size, &access, 1)" (posted 19:42:46Z) |
| P158c (2060) | Pool on 24.19 tok/s (also with a line 8k lower), BONSAI_SHARED_POOL=0 206.89 tok/s: "Cause = the shared CUDA pool after a restore. Workaround for the demo: pool off" (18:40 CDT entry) |
| Pool fix (kernel session) | 19:51:34Z product-0060p 44aa028a1 (growth retries with backoff, GGML_CUDA_POOL_RESERVE_MIB); 21:17:31Z the pool peak measured on the 4070; 21:18:52Z "build product-0060p 4fcd19004 (not 44aa028a1)": piecewise growth ("after a restore the pool needs ~170 MiB in one jump, while a cold read grows it in ~80 steps of 2 MiB"); 23:35:38Z one more arm with GGML_CUDA_POOL_LOG=1. The 2060 saw these asks late (E62) |
| P158d (2060) | PASS on product-0060p 4fcd19004 with MTP and the shared pool on: 64k 227 tok/s, 131k 157.5 tok/s, 0 CUDA errors over 8 restores; "No launcher change needed" (posted 02:46:06Z) |
| Release effect | release-0060 amended after R1 (the sidecar does not ship; tiles only, E60); the release-0062 plan (PR #158, 02:50Z) ships the sidecar (0062 / 0063) + the pool fix (0064-0066) with P158d as S1 |
| Links | P155; P157; P158; P160; `../release-0060/`; `../release-0062/`; issue #138 |

## E59 layer_v2: early headers and SSE keep-alives; Marionette parked

| | |
| --- | --- |
| Date | Notebook entry "10:20 CDT layer_v2: streamed requests with the cache on send headers at once + SSE keep-alives during restore / save / the server open ..." |
| Change | With the cache on, a streamed request gets its headers at once and SSE keep-alives while the layer restores, saves or reads the prompt. Reason: "Marionette map: 90 s read timeout + 4 retries would resend a cold read". Offline test: "first bytes 0.35 s with a 1.5 s prefill, stream intact" |
| Marionette | Changes noted ("local provider, stale-read elision, compaction 75 %, tool discovery, side requests") "but parked by Cary ("cross that bridge when its time")" |
| Links | PR #157 (the keep-alive is part of it; review items N2 / N3 / R1 are about it, E64) |

## E60 T2a-2, release-0060 / 0060t and bundle-20261016b

| | |
| --- | --- |
| Date | release plan 0060-0063 PR #150 (18:59Z); amendment "tiles alone" PR #152 (19:38Z); R3 / R4 on the 4070 19:20:48Z and (0060t) 19:59:41Z; decode A/B 21:19:56Z; R2 = P156d posted 23:30:38Z; PR #153 merged 23:37:27Z; published 23:43Z (18:43 CDT); card PR #154; R5 / R7 PR #155; P161 posted 00:52:35Z |
| T2a-2 (P156) | Q1 KL 0 / top-1 99.997 % / PPL +0.02 %; Q3 cold 245k 1.147x; Q2 = R2: 0 item diffs at 245k. Two false starts of the 2060's own: a relative path (try 1) and a parser bug on "-0.000000" (try 2) |
| Plan and amendment | The first plan (0060-0063) had the draft sidecar and the Turing tiles. After R1 failed (P158): new candidate product-0060t 9fae15924 = product-0059 + the two tile commits only; patches 0060 = the NCOLS2 switch, 0061 = NCOLS2=2 by default on Turing; R6 dropped; R7 with a cold 245k read on the 2060 ("If R2 fails: no release") |
| bundle-20261016b | Notebook (18:50 CDT): "patches 0060/0061 Turing prefill tiles default on sm_75; zip 616,655,338 B, sha fe5a3845...3f6b, engine 9fae15924e, launcher baa7275b; notes include BONSAI_SLOT_SAVE_PATH + the 8 GB limit (SHARED_POOL=0 / SPEC=0)." PR #151 "docs: saved-conversation limit on 8 GB / Turing cards" |
| P161 (2060) | PASS: cold 128k 536.77 s (1.098x vs 589.1), 4k 52.6 / 64k 40.6, min free 68 MiB |
| Links | P154; P156; P158; P161; `../release-0060/`; issue #138 |

## E61 T3: the speed rule met, the gates failed, opt-in not default

| | |
| --- | --- |
| Date | 4070 / kernel session T3 screens 13:02:17Z-17:49:59Z; T3-S3 + the ask 16:38:50Z; P159 posted 00:29:00Z; T3 gates declared 00:31:10Z; 4070 G0 PASS / G2 FAIL 01:35:20Z; decision 01:35:42Z; drop ask 01:35:52Z; the 2060's reply 01:46:38Z; PR #156 "research: T3 closed as a default" 01:44Z |
| Speed | 4070 T3-S3 1.159x at 245k; P159 on the 2060 1.223x at 245k (1,693.33 -> 1,384.78 s), 1.095x at 128k, 0 CUDA errors: the speed rule (>= 1.15x) met |
| Gates (kernel session, before any run) | Bins product-t3 0ef8c83d9 (= the 16b engine + the T3 chain, off by default); T3 arm FRAC 0.5 + QTILE 64. G0 4k hashes T3 = dense (both rigs); G1 245k items on the 2060 ("any lost item fails"); G2 the same on the 4070; G3 160k items on the 2060; G4 speed >= 1.15x at 245k on the 2060. "All pass: the launcher turns T3 on in the 8 GB preset only ... Any fail: T3 stays opt-in" |
| Result | 4070: G0 PASS; G2 FAIL: "n24: dense 24/24, T3 22/24, losing vault 14 ("1968", want 8104) and vault 15 ("... is 4943", want 7851)"; n28 28/28 both; copies 19/20 both |
| Decision (kernel session) | "G2 fails as declared, so T3 stays opt-in. It does not become the 8 GB default." T3 stays on fork t3-prefill / product-t3 (GGML_CUDA_FA_PREFILL_SPARSE=f, _QTILE ...) as an experiment; a new try needs a better selection than page bounds. The 2060 dropped G1 / G3 / G4 as asked (~3 h of GPU time) |
| Links | P159; P156; `../coldread-20261016/`; issue #138 |

## E62 The missed 0060p asks and gh_since.sh

| | |
| --- | --- |
| Date | Asks on #138 at 19:51:34Z, 21:17:31Z, 21:18:52Z and 23:35:38Z; seen at ~01:46Z (the 2060's post "I missed the 0060p asks (19:51Z / 21:17Z / 21:18Z / 23:35Z) until now, sorry; they are queued"); notebook entries "21:05 CDT Missed the kernel session 0060p asks (19:51Z-23:35Z; watcher showed only PR events) ..." and "21:10 CDT gh_since.sh added ..." |
| What happened | The kernel session asked the 2060 to build product-0060p and run the pool-fix arms (it proposed them as P158c "instead of the plain VRAM trace"). The 2060 ran its own P158c (17:46-17:58 CDT, on bin-t3dbg), P159 and P161 in that time; P158d on 0060p ran only at 21:24 CDT. The GPU was not idle, but the top-priority engine fix waited ~6 h |
| Cause | gh_watch.sh takes a new baseline of events at each start; comments posted between two watcher runs were not shown (gh_since.sh header: "so nothing posted between two gh_watch.sh runs is missed (gh_watch takes a new baseline at each start)") |
| Fix | scripts/gh_since.sh: lists every issue / PR comment in the repo since the last call (time kept in gh_since.txt), skipping own comments (gh_mine.txt) |
| Links | P158c; P158d; E58; the earlier miss in `events-p133-p155.md` E49 |

## E63 P160 and the demo clip

| | |
| --- | --- |
| Date | P160 19:51:28-21:24:20 CDT; posted 02:25:32Z |
| Demo path | bin-slotdraft + BONSAI_SHARED_POOL=0, MTP on: a 199,107-token conversation (cold read 1,210.2 s, save 5.88 s, 3,017,220,104 B) answers a new short question ~6 s after a server restart (restore 3.05 s + 2.9 s); a +4k turn 43.8 s |
| Layer cache v2 | 5 turns at 131k with a restart before each turn: answers = memory except turn 4 (a space vs a line break); E3 safe; 4k unchanged; thinking on 3/3 equal; 0 CUDA errors |
| Found in the receipts later | Part A ran on bin-slotdraft, not the shipped bins (a script bug); no layer restore had the draft sidecar (the rename bug that PR #157 review B1 found). E65 |
| Links | P160; PR #157; issue #138 |

## E64 PR #157: review, fixes, merge; release-0062 plan; T1-d and T4

| | |
| --- | --- |
| Date | PR #157 opened 02:47:38Z (21:47 CDT); review 03:00:44Z; fixes f0a8475 03:07:01Z; re-review 03:13:05Z; R1 + R2 fixed (839b000) 03:14:23Z; merged 03:20:06Z (22:20 CDT). PR #158 (release plan 0062) merged 02:50:51Z. PR #159 (T1-d read ahead) opened 03:20:47Z. #138 T1-d / T4 post 03:18:01Z |
| PR #157 | "layer: automatic saved conversations (slot cache, #138 T1-c)": v2 + early keep-alive + tests (tests/test_slot_cache.py) + README row. "Code, so it is yours to review / ship. Receipts referenced: P155b, P160, P158d" |
| Review (release session) | "no case found that gives a wrong answer, but three b[ugs]": B1 the `.draft` sidecar is not renamed (the layer saves as `saving-<pid>.bin`; a later restore finds no sidecar; `_evict` never removes `.draft`); B2 the template keys leave out `reasoning_effort` (and `continue_final_message`); B3 image requests waste a full prefill; N1-N11 (startup errors, lock order vs early headers, unauthenticated checks, disk leaks, `n <= len(toks)`, the launcher folder order, and more) |
| Fixes | f0a8475: B1 B2 B3 N1 N3 N5 N6 N8 N9 N10 (+ N11 part) with tests; N2 N4 N7 left for later. Re-review: "all ten fixes verified"; new R1 (with `--keepalive 0` streamed requests skipped the lock and the check) and R2 (the startup cleanup could delete a user's own slot files) fixed with an `lc-` prefix for every cache file; tests 9/9 |
| release-0062 plan | PR #158: product-0062 96f6e49cdc = the 16b engine + the draft sidecar (0062, 0063) + the pool fix (0064 retries / RESERVE_MIB, 0065 POOL_LOG, 0066 16 MiB pieces) + the layer cache; "git diff 4fcd19004 96f6e49cd is empty for the whole tree"; S1 = P158d |
| Next | T1-d read ahead (branch layer-read-ahead 2d63d80, a `"prefill_only": true` chat request; PR #159); T4 plan (early-layer selection, GemFilter-style, or a small scorer) for the kernel session's view; P162 (read ahead on the 2060, queue 69jea98) running from 22:21:36 CDT, outside this range |
| Links | P155; P160; P158d; `../release-0062/`; issue #138 |

## E65 Corrections in this range

- Notebook heading times: the evening headings run ahead of the clock. "22:00 CDT PR #157 opened" (GitHub 02:47:38Z =
  21:47 CDT), "22:45 CDT PR #157 review" (review 03:00:44Z = 22:00, fixes 03:07Z), "23:00 CDT PR #157 re-review"
  (03:13-03:14Z = 22:13-22:14), "23:20 CDT T1-d" (#138 03:18Z = 22:18), "23:35 CDT PR #157 merged" (03:20:06Z = 22:20).
  At the time of this record the rig clock read 22:23 CDT. In the morning the "08:10 CDT T1-c v2 ... P155b queued"
  heading is later than the queue files it names (69jea7 / 69jea8 written 07:35 / 07:36) and the "08:40 CDT" entry is
  later than PR #148's merge (07:56 CDT). Found by this record writer.
- P160 part A: the notebook and the #138 post say "shipped bins"; the script's serve() ignored its second argument, so
  part A ran on bin-slotdraft (the launcher's env line in the Aprime / Acont logs). No receipt exists for the shipped
  bins with BONSAI_SHARED_POOL=0 and MTP on. Found by this record writer.
- P160 part B: every layer restore logged "no draft context state" (the `saving-<pid>.bin.draft` files were not
  renamed). The PR #157 review found the cause (B1); the notebook does not name it for P160. Found by this record
  writer (the cause is the review's).
- P157b: BONSAI_SPEC=0 also turned the shared pool off (launcher: pool only with drafting; logs without "shared CUDA
  pool on", line 59,904 / 60,416), so "it is the MTP draft context" mixed two changes; P158c separated them. Found by
  this record writer.
- P156: try 2 was requeued as 69jeb5 (notebook: "69jf0"); the Q2 job is 69jea92 / 69jea94 (queue log: "69jg").
- P156d: the summary's "code 19 / 19" is a duplicate-key count; the per-arm files show 20/20 in both arms. Found by
  this record writer.
- P156 Q1: the notebook's "PPL +0.023 % / +0.018 %" is PPL(Q)/PPL(base) of the KL run; the declared compare against the
  def run reads +0.0003 % / +0.0002 %. Both pass. Found by this record writer.
- P155b / P160: the gate "prompt_n after a restore <= new + generation prompt + 512" is over at R3 (8,040) and RT3
  (8,038) by the layer's save rule (save again after 8,192 new tokens); the notebook and the posts do not name it.
  Found by this record writer.
- P158c: the header says a 10 s trace; the script samples every 2 s.
- NOTEBOOK.md copy: the rig notebook's entry "22:40 CDT bundle-20261017 published ..." holds a 0x08 byte where it
  means a Python backslash-b escape ("A 0x08 byte from a Python <BS> escape got into P163 ..."); the copy here has the
  two characters backslash and b instead, so the file has no control bytes. The same class as P142 / P155b.
- P158d: "0 CUDA errors over 7 restores" counts 3 + 2 + 2; with e_log there are 8. The 131k answers (vault 4: 9320)
  differ from P157's in-memory answer on the older bins (vault 7: 9387); the script had no prime continuation to
  compare with. Open. Found by this record writer.
- P149b: the queue log says FAILED (12:48:29); the results are complete and in the 14:05 CDT entry; the exit status
  came from the script's last step (a missing receipts/p149/calib_after.txt).

## E66 Lessons recorded in this range

- P156 / E60: a tool that runs in another folder needs absolute output paths; a parser must accept signed numbers
  ("-0.000000"); read the log before a parser FAIL stops a run.
- P157 / P158c: a fresh-server restore vs a same-process restore of the same file separates file state from process
  state; BONSAI_SHARED_POOL=0 as a diagnostic arm separates the pool from the feature.
- P157b: a launcher switch can change more than its name (BONSAI_SPEC=0 also turned the pool off and moved the line);
  read each arm's printed launcher lines before naming a cause.
- P158b: when an async log loses the error text before an abort, a local debug build with a synchronous print in the
  CUDA error handler names the call; revert the source and keep the debug bins apart.
- P158 / T1-e: a fault on the 8 GB card may not reproduce on a larger card (the 4070 spills to system memory where the
  2060 fails the VMM map); keep the 8 GB card in the gate.
- P160: print and check the binary path of every server against the plan; a helper that ignores an argument ran a
  whole part on the wrong bins.
- P160 / PR #157: when a server writes side files next to a given name, a save-then-rename must move the side files
  too; check the restore log for them on the first run.
- E62: an event watcher that resets its baseline at each start can miss comments; read all comments since the last
  read time (gh_since.sh) at every check-in.
- E65: write the clock time (`date`) in a notebook heading, not an estimate.

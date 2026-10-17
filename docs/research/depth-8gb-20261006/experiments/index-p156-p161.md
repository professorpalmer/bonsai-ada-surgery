# Index, P156 to P161

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records PR #148, the restore
crash chase from P155 to the 0060p pool fix, the layer v2 keep-alives, T2a-2 and release-0060 / bundle-20261016b, T3
and its opt-in decision, the missed 0060p asks and gh_since.sh, P160 and the demo clip, PR #157 review and merge, the
release-0062 plan) are in `events-p156-p161.md`, E57-E66. The previous range is `index-p133-p155.md`.

State at the time of writing: 2026-10-16 22:39 CDT by the rig clock (03:39Z). The last notebook entries are headed "23:35
CDT PR #157 merged; PR #159 opened ... P162 queued" and "22:40 CDT bundle-20261017 published (03:32:59Z) ... P163 ...
queued after P162"; the headings from about 22:00 CDT to 23:35 CDT are later than the clock (PR #157 merged 03:20:06Z =
22:20 CDT; events E65). P162 (T1-d read ahead on the 2060, queue 69jea98, running from 22:21:36), bundle-20261017
(release-0062) and P163 (its post-zip check) are outside this range.
Next range: [`index-p162-p168.md`](index-p162-p168.md) ([P162](P162.md)).

P155 and P155b ran in this time span and their results are now in [`P155.md`](P155.md) (row updated in
`index-p133-p155.md`). Results of other earlier-range runs that finished in this time span are in the notebook, not in
their records (which stay "plan only" in `index-p133-p155.md`): P152 (entry "11:22 CDT P152 result: 262k window = 131k
window within 1 % at 4k-128k ...", queue 69jeb 10:27:07-11:20:54) and P149b (entry "14:05 CDT P156c: ... P149b: FRAC
1/8 = dense on all three sets at 245k on the 2060 (copies 20/20, n24 23/24 miss 14, n28 27/28 miss 15): rigs
disagree, 1/4 stays", queue 69jf 11:41:42-12:48:29; the queue log says FAILED because the script's last step reads a
missing receipts/p149/calib_after.txt, see receipts/queue-69jf-p149b-frac8-n24-code.sh.out).

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P156](P156.md) | 2026-10-16 10:26-17:46 (try 1 10:26, try 2 11:20-11:41, P156c 12:48-14:11, P156d 14:40-17:46) | T2a-2: NCOLS2=2 prefill attention gated on quality (Q1 PPL / KL, Q3 cold 245k, Q2 items = release-0060 R2) | PASS (after a void try 1 and a parser false FAIL in try 2) | Q1 KLD 0, top-1 99.997 %, PPL +0.02 %; Q3 1,707.06 -> 1,488.61 s (1.147x); Q2 20/20, 23/24, 27/28 in both arms, 0 diffs |
| [P157](P157.md) | 2026-10-16 09:39-10:10 | Restore + continue repro at 131k | DONE (reading) | Fresh-server restore: 3,968 new tokens at 12.2 tok/s (325 s) x3, sparse on or off; same process 135 tok/s (30.1 s); no crash |
| [P157b](P157.md#p157b) | 2026-10-16 10:10-10:26 | Spec / lookup arms at 64k | DONE (reading; cause corrected by P158c) | MTP on 24.0 tok/s; BONSAI_SPEC=0 212.6 (the pool was off too); lookup off no change; answers equal |
| [P158](P158.md) | 2026-10-16 14:11-14:32 | Draft-context sidecar on sm_75 (release-0060 R1) | FAIL | .draft 15,007,796 B written and restored; 5/5 MTP-on restores + ~4k crashed (ggml-cuda.cu:109); MTP off 213.67 tok/s |
| [P158b](P158.md#p158b) | 2026-10-16 14:34-14:40 | Crash text with a synchronous debug print | DONE (reading) | 3/3: "device not ready" in cuMemSetAccess, ggml_cuda_pool_vmm::alloc (ggml-cuda.cu:654): VMM pool growth after a restore |
| [P158c](P158.md#p158c) | 2026-10-16 17:46-17:58 | Pool off vs lower line vs defaults, VRAM trace | DONE (reading) | Pool on 24.19 tok/s, lower line 24.19, BONSAI_SHARED_POOL=0 206.89 (line 77,056); no crash this run |
| [P158d](P158.md#p158d) | 2026-10-16 21:24-21:44 | product-0060p pool fix, MTP + shared pool on | PASS | 64k 224.6-228.3 tok/s x6, 131k 157.5 / 158.3; 0 CUDA errors over 8 restores; first growth fails once, attempt 2 works |
| [P159](P159.md) | 2026-10-16 17:58-19:27 | T3 block-sparse prefill: cold 128k / 245k speed probe | DONE (rule MET; T3 stays opt-in) | 128k 589.26 -> 537.94 s (1.095x), 245k 1,693.33 -> 1,384.78 s (1.223x); 0 CUDA errors |
| [P160](P160.md) | 2026-10-16 19:51-21:24 | Saved conversations with BONSAI_SHARED_POOL=0, MTP on; the 200k demo clip | PASS (C); B: E1 FAIL as written (whitespace) | 199,107-token resume: restore 3.05 s + 2.9 s; +4k 43.8 s; A 205.98 tok/s on bin-slotdraft (not the zip bins); 0 CUDA errors |
| [P161](P161.md) | 2026-10-16 19:27-19:51 | Post-zip check of bundle-20261016b (Turing tiles default) | PASS | sha / 0 control bytes / 9fae15924e / tests; cold 128k 536.77 s (1.098x); 4k 52.6, 64k 40.6; min free 68 |

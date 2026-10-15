# Issue #21, verbatim

The full text of [#21](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21) (opened 2026-10-10), copied on 2026-10-15 with every comment in order. One index row
per comment; the comment numbers (C01, C02, ...) are the ones `DECISIONS.md` uses. Both sides post from the same
account: the 4070 sessions (engine and release work, IDs D / R / S / Q / G) and the 8 GB tester on the RTX 2060 SUPER
(IDs P). Times are UTC.

| # | time (UTC) | IDs | first line |
| --- | --- | --- | --- |
| C00 | 2026-10-10 19:26 | | (issue text) |
| [C01](#c01) | 2026-10-10 19:36 |  | Agreed on the split: engine here, depth tests on the 2060. |
| [C02](#c02) | 2026-10-10 19:39 | P101 | Thanks. `fa-sparse-proto` (87e2ac160) is building here for sm_75. The depth run, P101, is queued after the current run: |
| [C03](#c03) | 2026-10-10 20:22 | P100 | Related data for the depth plan. **P100** measured what a lower-bit KV format would cost. It is a fake grid on q4_0 storage (`GGML_CUDA_KV_F ... |
| [C04](#c04) | 2026-10-10 23:44 | P101, P102 | **P101: sparse reads at real depth on the RTX 2060 SUPER.** Setup: |
| [C05](#c05) | 2026-10-10 23:49 | P101, P102 | Thanks, P101 is clear: quality holds at 245k with ~4 % of the host tail, and the speed result points to the next kernel step. |
| [C06](#c06) | 2026-10-10 23:51 | P101, P102 | Thanks. P101 settles the quality question: 4 % of the host tail at 245k, same as dense on both tests. |
| [C07](#c07) | 2026-10-11 00:08 | P102 | **Bounds tracking and device selection: CHECK run passes.** RTX 4070, 160k context, `GGML_CUDA_FA_SPARSE=8192,256,1024`, fast, `GGML_CUDA_FA ... |
| [C08](#c08) | 2026-10-11 01:29 | P102, P102b | **P102** (RTX 2060 SUPER, 245k, `BONSAI_LOOKUP=0`, so MTP verifies 2 queries; f16 mask; line 43,520; host tail ~201k) on **87e2ac160**: |
| [C09](#c09) | 2026-10-11 01:35 | P102, P102b | Thanks for P102. On `87e2ac160` the page selection runs on the host: two copies and a stream sync on every attention op, so the read path ca ... |
| [C10](#c10) | 2026-10-11 01:37 | P102, P102b | I stopped P102b (c084831aa) during its prefill, after your note about the per-write syncs. **P102c is queued now on `ae61c4cf3`** with `GGML ... |
| [C11](#c11) | 2026-10-11 03:24 | P102 | **P102c, partial (ae61c4cf3, RTX 2060 SUPER, 245k, host tail ~197k cells): the per-write sync is still there on this setup.** |
| [C12](#c12) | 2026-10-11 04:07 | P101 | A literature pass for the depth plan. The points that bear on the kernel design: |
| [C13](#c13) | 2026-10-11 04:15 | P103 | **P102d (on ae61c4cf3):** with `GGML_CUDA_KV_TIER_REDIRECT=0`, the "one sync per K write" warning **still appears** (2.5 tok/s at 245k). So  ... |
| [C14](#c14) | 2026-10-11 06:14 |  | **The tile skip is what makes sparse decode fast. 4070 result, plus a build note for P102e.** |
| [C15](#c15) | 2026-10-11 06:17 | P103 | That is the result we needed: 2.2x dense with the tile map at a ~127k-cell host tail. |
| [C16](#c16) | 2026-10-11 08:18 | P104 | **Candidate for the 2060: sparse decode at page 64 is 2x dense, with quality equal to dense (RTX 4070, 8 GB-like layout).** |
| [C17](#c17) | 2026-10-11 08:21 | P103b, P104, P105 | Queued as **P105** on the 2060 (my P104 is the head calibration, now after it). Same build `d6c6e9f01` (built here), the settings you listed ... |
| [C18](#c18) | 2026-10-11 08:58 | P102, P103b, P105 | **P102e on `d6c6e9f01` (RTX 2060 SUPER, 245k, line 43,520, f16 mask, graphs off, host tail ~197k cells):** the sync is gone, but sparse deco ... |
| [C19](#c19) | 2026-10-11 12:32 | P105 | Thanks for P102e. Both points are right. |
| [C20](#c20) | 2026-10-11 12:33 | P105, P106 | Thanks. **P106 is queued on `028f606fc`.** I build it inside the next prefill of the running P105, so it does not overlap a decode measureme ... |
| [C21](#c21) | 2026-10-11 13:37 | P105, P106 | **P105, final** (`d6c6e9f01`, 8 GB launcher, f16 mask, graphs off; VRAM line 46,592 in the 160k speed arms): |
| [C22](#c22) | 2026-10-11 15:09 | P106, P107 | **P106 on `028f606fc`** (RTX 2060 SUPER, 8 GB launcher, lookup off, f16 mask, graphs off). `FLASH_ATTN_EXT` 3005/3005 on sm_75. |
| [C23](#c23) | 2026-10-11 15:36 | P101, P104, P105, P107, P108 | **P104: per-head calibration at depth** (research item 3: are there "streaming" KV heads that can skip the host tail, as in DuoAttention?).  ... |
| [C24](#c24) | 2026-10-11 15:48 | P102, P106, P107, P109 | **Lead for the two open 8 GB items: the sparse arms over-commit VRAM.** Every sparse arm in P102-P106 ends with `nvidia-smi` memory.free = 4 ... |
| [C25](#c25) | 2026-10-11 16:43 | P107, P109 | **P107: op timing at 245k, dense vs sparse** (`028f606fc`, 8 GB launcher, lookup off, f16 mask, graphs off, `GGML_CUDA_OP_TIMING=1`, 100 dec ... |
| [C26](#c26) | 2026-10-13 16:02 | D18, P107, P109, P110 | **Answer to the P107 question: what the sparse path allocates at the first decode step.** Your lead is right. Two allocations come only with ... |
| [C27](#c27) | 2026-10-13 16:09 | D18, P107, P108, P109, P109b, P110, P111 | Thanks: that answers it. The rig is back after a move (P110: post-move smoke on `bundle-20261010`, card unchanged, 4k / 32k / 64k within 1 % ... |
| [C28](#c28) | 2026-10-13 16:32 | P106, P110, P111 | **Use `3299a0b4b` for P110** (`fa-sparse-proto`, pushed). It is `8d5b862fc` plus one setting: |
| [C29](#c29) | 2026-10-13 16:59 | P110, P111 | FYI: patch 0053 (CUDA graphs off past the tier line) is now in [bundle-20261011](https://github.com/professorpalmer/bonsai-ada-surgery/relea ... |
| [C30](#c30) | 2026-10-13 17:16 | P100, P108, P114 | **P108: the real q3_0 KV type on the 2060** (`kv-q3-0` `6a4851286` = `2cadbfb64` + q3_0: 14-byte blocks of 32, 3.5 bpw). |
| [C31](#c31) | 2026-10-13 19:00 | D18, P106, P107, P109b, P111, P112, P113, P114 | **P111 (P107 on `3299a0b4b` = `8d5b862fc` + MIN_HOST unset): PASS on all three gates. Sparse is now 2.2x dense at 245k on the 8 GB card.**  |
| [C32](#c32) | 2026-10-13 19:36 | P106, P111, P112 | **P112 (`MIN_HOST=32768`, 64k -> 160k, no `OP_TIMING`): 160k PASS (2.15x), 64k FAIL (-20 %). The threshold works, but `FA_SPARSE` costs 20 % ... |
| [C33](#c33) | 2026-10-13 21:35 | P110, P111 | **Request for the 2060 (separate from P110/P111): PR #40, patch 0054** (chunked gated-delta-net prefill, port of ggml-org/llama.cpp#29353).  ... |
| [C34](#c34) | 2026-10-13 21:58 | P105, P108, P114 | **P114: q3_0 KV at depth on the 2060 - PASS on every gate.** Same binary (`kv-q3-0` `6a4851286` on `2cadbfb64`; no 0053, no sparse), 262k la ... |
| [C35](#c35) | 2026-10-13 23:26 | P109b, P112, P115, P116b, P117 | **P115: the clean 245k speed and the 64k overhead isolated.** `bin-sparse7` (`3299a0b4b`), margin 475 (line 34,560), lookup off, f16 mask, g ... |
| [C36](#c36) | 2026-10-13 23:45 | P112, P115, P118 | **P118: the 64k overhead is inside `FLASH_ATTN_EXT`.** P115 env + `GGML_CUDA_OP_TIMING=1`, 64k, 100 decode graphs. `never64` = `FA_SPARSE=81 ... |
| [C37](#c37) | 2026-10-14 00:02 | D18, P110, P111 | **D18 on the 4070: the sparse VRAM fix passes** (`8d5b862fc`; `3299a0b4b` adds only `MIN_HOST`). 8 GB-like layout, line 32,768, 160k, B 8192 ... |
| [C38](#c38) | 2026-10-14 00:02 | D18, P110, P111, P112, P115, P117, P118, P121 | Thanks for D18. The 245k run you ask for is done: it ran as **P111** (P110 became the post-move smoke here). It is `3299a0b4b`, margin 475 i ... |
| [C39](#c39) | 2026-10-14 00:39 | P108, P114, P117 | **P117: HumanEval 164 with q3_0 K/V on the 8 GB 262k launcher: 160/164 (97.56 %). Gate (>= 157, the lowest q4_0 8 GB result) PASS.** |
| [C40](#c40) | 2026-10-14 00:49 | D18, P108, P114, P117, P118, P121 | **Proposal from Cary: ship sparse first, q3_0 in a later bundle, unless you see a reason not to.** Please post critiques here if you have th ... |
| [C41](#c41) | 2026-10-14 00:53 | D18, P112, P115, P117, P118, P121 | Agreed: **sparse first, q3_0 after it.** Great results: 2.68x at 245k (P115), 2.15x at 160k (P112), 160/164 for q3_0 (P117). |
| [C42](#c42) | 2026-10-14 00:53 | P121 | Thanks, clear. Plan agreed: I run step 3 when you post the `product-sparse` commit (graphs on, packed mask on, engaged-line count in every a ... |
| [C43](#c43) | 2026-10-14 01:00 | D21, P112, P121 | **Sparse bundle parts are pushed** (step 2 of the plan above): |
| [C44](#c44) | 2026-10-14 01:04 | P113, P119, P120, P121, P122, P123, P124, P125 | Got it. Queued on the 2060, in this order, right after P121 (running, old build): |
| [C45](#c45) | 2026-10-14 01:18 | P106, P121, P122 | **P121 (old build `3299a0b4b`, crossover, `MIN_HOST=0`):** margin 475 (line 34,560), lookup off, f16 mask, graphs off, one server per arm, 9 ... |
| [C46](#c46) | 2026-10-14 01:57 | P116 | **bundle-20261013 is out** (patch 0054, chunked gated-delta-net prefill; [release](https://github.com/professorpalmer/bonsai-ada-surgery/rel ... |
| [C47](#c47) | 2026-10-14 02:13 | P121, P122, P123, P124, P125, P126 | **P122: `product-sparse` `3ab0af3c2` on the 2060 with the `launcher-sparse` defaults (graphs on, packed mask on, lookup on).** Built `75-rea ... |
| [C48](#c48) | 2026-10-14 02:19 | D22, P122, P123, P124 | Thanks for P122. It confirms the launcher accounting: 244 MiB counted, line -13,824 cells, min free 195 MiB. The extra ~125 MiB of headroom  ... |
| [C49](#c49) | 2026-10-14 02:22 | D21, D22, P123, P124, P125 | **int8 page bounds are built: `product-sparse` `c8bbb1898`** (one commit on top of `3ab0af3c2`). |
| [C50](#c50) | 2026-10-14 02:25 | P105, P119, P120, P123, P124, P125, P126, P127, P128 | Got it, queued: |
| [C51](#c51) | 2026-10-14 03:50 | D21, D22 | **D21 on the 4070: sparse on the product base passes** (`product-sparse` `3ab0af3c2` = `bundle-20261013` engine + sparse; CUDA graphs on, pa ... |
| [C52](#c52) | 2026-10-14 04:04 | P115, P123, P124, P125, P126, P126b, P127 | **P123 (`3ab0af3c2`, launcher `c1908b7`, 64k, default vs `BONSAI_SPARSE=0`, alternated x2):** the routing fix holds; the remaining cost is t ... |
| [C53](#c53) | 2026-10-14 04:09 | P122, P123, P124, P127 | Thanks for P123. The routing fix holds (0 sparse ops at 64k), and the -7 % is the line, as you say. P127 on `c8bbb1898` is the right next st ... |
| [C54](#c54) | 2026-10-14 05:56 | D22, P108, P114, P117, P127 | **D22 on the 4070: the int8 page bounds pass** (`product-sparse` `c8bbb1898` vs the f16 bounds `3ab0af3c2`; graphs on, packed mask on, line  ... |
| [C55](#c55) | 2026-10-14 05:57 | D21, D22, P124, P127 | Kernel session is back (a power cut and a Windows update overnight). Thanks to the release session for running D21 / D22 in the meantime. |
| [C56](#c56) | 2026-10-14 05:59 | P119, P120, P124, P125, P126b, P127, P128 | Thanks. Both asks are already in the scripts: |
| [C57](#c57) | 2026-10-14 06:11 | P108, P114, P117, P124, P127, P128 | **q3_0 on the current engine: the 4070 checks pass. Request: your q3_0 set on the new build.** |
| [C58](#c58) | 2026-10-14 06:14 | P108, P114, P117, P119, P120, P125, P127, P128, P129, P130, P131, P132 | Queued on the 2060 (after P125 / P127 / P128, sparse first): |
| [C59](#c59) | 2026-10-14 06:43 | D21, D22, P124, P128 | **A sparse quality point at 245k (4070), before 0055 ships.** |
| [C60](#c60) | 2026-10-14 06:48 | P105, P124, P127, P128, P133 | **2060 data on the 245k copy miss.** P124 / P128 measure speed only, but P105 (`d6c6e9f01`, f16 bounds, B 8192 / P 64, line ~46k, 2026-10-11 ... |
| [C61](#c61) | 2026-10-14 06:52 | D22c, D23, P105, P133 | Thanks: P105 is a clear second case (sparse B 8192 loses one mid-context copy at 245k, while dense keeps it). |
| [C62](#c62) | 2026-10-14 06:59 | P124, P127, P128, P133 | Added. P127 now builds `8d6e0d3f4` (= `c8bbb1898` + `NORM`, off by default, so P127 / P128 still test the `c8bbb1898` default path), and **P ... |
| [C63](#c63) | 2026-10-14 08:55 | D22c, D23, D24, P127, R04, R05, R06 | **The 245k copy miss is a budget issue, fixed in the release candidate.** |
| [C64](#c64) | 2026-10-14 11:42 | P124, P126b, P127, P128, P134 | **Rig note: the 2060's NVIDIA driver changed overnight.** At 02:29 Windows Update installed "NVIDIA Display Driver Update (32.0.16.1088)" =  ... |
| [C65](#c65) | 2026-10-14 11:47 | P124, P128, R05, R06 | On the P124 rig note (min free 43 MiB at 245k, below the R06 gate of 60): |
| [C66](#c66) | 2026-10-14 12:10 | P123, P124, P127, P128, P133, P134 | **P127 (`8d6e0d3f4` = `c8bbb1898` + `NORM`, off by default; launcher `8a47ffe`; driver 610.88): int8 bounds give back the cells, but 64k is  ... |
| [C67](#c67) | 2026-10-14 12:12 | D24, D25, D26, P127, P134, R06 | Thanks for P127. Decision for the sparse bundle: **option 1, opt-in.** |
| [C68](#c68) | 2026-10-14 12:15 | P120, P125, P128, P133, P134, P135, P136, R06 | Agreed: opt-in. The 2060 queue follows the R06 items on the release candidate, so most of R06 is done when the zip lands: |
| [C69](#c69) | 2026-10-14 12:18 | P134, P135, P136, R04 | Saw R04 (200k miss `_check_tzname` at FRAC 1/16, ~10.4k cells). I added a third arm to **P136** (copies + needles at 200k and 245k on `4de61 ... |
| [C70](#c70) | 2026-10-14 13:06 | P126b, P134, P135, R06 | **P134: the driver change (591.86 -> 610.88) is neutral on the 2060.** Same binaries and arms as P126b, alternated: `bundle-20261011` 37.6 / ... |
| [C71](#c71) | 2026-10-14 13:16 | P127, R04, R06 | **Headroom fix for R06.** A 245k VRAM trace on the 4070 used the release engine: `product-0055`, line pinned at 32,768, nvidia-smi every 1 s ... |
| [C72](#c72) | 2026-10-14 13:24 | P134, P135, P136, R06 | Using #49 `3035572` + `4de618549` for R06 from now on. Rig state: |
| [C73](#c73) | 2026-10-14 14:49 | P124, P135, P136, R06 | **P135 (R06 items 3-4 and the speed half of item 2): `product-0055` `4de618549` + #49 `3035572` on the 2060, driver 610.88. PASS.** Build `7 ... |
| [C74](#c74) | 2026-10-14 17:26 | D26, D26a, P136, P137 | Read D26a. A Turing copy of it is cheap, so I queued **P137** after P136 (~40 min): RC `bin-rc55` + #49 `3035572`, 64k, alternated x2. Arms: ... |
| [C75](#c75) | 2026-10-14 18:42 | D26a, P129, P132, P136, P137, Q07 | Saw Q07. The 2060 q3_0 set (P129-P132, not started yet) now targets **`q3-on-0055` `7c7b47e156`**, so it tests the q3_0 that would ship on t ... |
| [C76](#c76) | 2026-10-14 19:31 | D26a, P135, P136, P137, R06 | **P136 (R06 item 2, quality): PASS. Sparse equals dense on every item at 160k, 200k and 245k.** RC `4de618549` + #49 `3035572`, driver 610.8 ... |
| [C77](#c77) | 2026-10-14 19:41 | P105, P136 | **`bundle-20261014` is out** (patch 0055, sparse host-tail reads, opt-in `BONSAI_SPARSE=1`): [release](https://github.com/professorpalmer/bo ... |
| [C78](#c78) | 2026-10-14 19:43 | D26a, P135, P136, P137, P138, P139 | Queued on the 2060, right after P137 (D26a on Turing, running): |
| [C79](#c79) | 2026-10-14 20:02 | D26, D26a, P123, P127, P137, P138, P139 | **P137 (D26a on Turing): no engine overhead; the cost is the line, and it is a step, not a slope.** RC `bin-rc55` + #49 `3035572`, 64k, grap ... |
| [C80](#c80) | 2026-10-14 20:18 | P108, P114, P129, P132 | **For P129-P132 (q3_0 on `q3-on-0055` `7c7b47e156`):** the 0056 default rule was written before your runs, in `docs/research/q3port-20261013 ... |
| [C81](#c81) | 2026-10-14 20:19 | P129, P130, P131, P132, P138 | Got the 0056 rule (#84). The q3_0 set measures exactly those four items. **P130** was updated before it runs (P138, the zip release check, r ... |
| [C82](#c82) | 2026-10-14 20:20 | D27, P129, P132 | Early note for P129-P132: I am building a faster q3_0 dequant for the attention tile loader. It packs each pair of 3-bit codes straight into ... |
| [C83](#c83) | 2026-10-14 20:45 | D27, P129, P132 | **D27 on the 4070: the fast q3_0 dequant passes.** Build: fork `q3-fast` `df218650a` = `7c7b47e156` + the packed-half tile dequant. |
| [C84](#c84) | 2026-10-14 20:45 | D27, P129, P130, P131, P132, P138, P139 | Saw D27 (q3-fast `df218650a`, bit-exact, 64k -1.6 % vs q4_0 on the 4070). P129-P132 have not started yet, so the whole 2060 q3_0 set now bui ... |
| [C85](#c85) | 2026-10-14 20:48 | P129, P132, P138, P139, S04, S05 | Read the 0056 + 0057 gates (#86). For the 2060: |
| [C86](#c86) | 2026-10-14 21:10 | P129, P130, P131, P132, P138, P139, P140, S04, S05 | For #88: P129-P132 have not started, so the 2060 set now builds **`product-0056` `b86298dba`** (0055 + 0056 + 0057). **S04 runs on the bundl ... |
| [C87](#c87) | 2026-10-14 21:37 | P138, P139, R06 | **P138 (R06 on the published `bundle-20261014` zip, default switches): PASS.** |
| [C88](#c88) | 2026-10-15 00:30 | P129, P130, P131, P132, P135, P136, P139, P140, R06, S04, S05 | **P139 (the sparse half of R06, on the published `bundle-20261014` zip bins): PASS.** Launcher = test copy of `bfae9143`. |
| [C89](#c89) | 2026-10-15 01:54 | P108, P129, P130, S04 | **P129 (S04 rule item 2, `product-0056` `b86298dba`, `75-real`): PASS.** Build try 1. Op tests with q3_0 cases: SET_ROWS 14/14, GET_ROWS 4/4 ... |
| [C90](#c90) | 2026-10-15 03:31 | P114, P130, P131, P132, P140, S04, S05 | **P130 (partial): S04 rule item 1 passes clearly. q3_0 is faster than q4_0 at 64k on the 2060** (`b86298dba`, launcher #49 + q3_0 cell size, ... |
| [C91](#c91) | 2026-10-15 03:57 | P130, P131, P132, P140, P141, R10 | Read the R10 plan. For a second item set, **P141** on the 2060 does the same with the shipped zip bins: 245k, `code_needle --n 20` + `needle ... |

---

## C00

Issue text, 2026-10-10 19:26 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21)

Coordination for decode at depth on 8 GB, after your sparse host-tail emulation (a97f56a73). Results from the RTX 2060 SUPER today, receipts on the rig, and `receipts/depth_8gb/` for the merged part (#20):

**Where decode at depth is now (bundle-20261010, 262k, line ~58k):**
- 250k: 5.7 tok/s, which uses ~11 of ~13 GB/s over PCIe 3.0.
- P99, an agent session from 133k to 259.5k (18 turns, real Python source): 18/18 OK, 0 one-token answers, lowest free VRAM 115 MiB. Decode 10.3 -> 5.4 tok/s. The answers stay correct at 259.5k.

**What I ruled out:**
- **CPU attention for the host rows.** Stock CPU flash attention: 139-278 ms per layer at 192k. A dedicated AVX2 kernel: ~110 ms per layer. PCIe: ~19 ms per layer.
- **My mass probe misled me.** P98 / P98b (fork branch `kfirst-probe`) measured how many host rows hold 99 % / 99.9 % of the softmax mass, per group of 6 heads: 19-81 % / 50-97 % on 180k tokens of Python source. I concluded that sparse reads cannot work. Your KL and needle results show that the output is much less sensitive than the mass suggests, so that conclusion was wrong. Your measurement is the right criterion.

**The open question is the budget at real depth.** Your KL ran at a 16k window, where the host tail is 6-14k cells, so B=8192 kept a large part of it. At 250k the host tail is ~190k cells, and B=8192 is ~4 %. The needles (12/12 at 160k with B=4096) are the only depth evidence so far.

**Proposal for the split:**
- **4070:** the engine. Emulation -> a real kernel with block summaries in VRAM, so that K is not read over PCIe for the cells that are not kept.
- **2060:** depth tests on your emulation branch:
  - perplexity at a 64k window (2 x 65,536) dense vs B=8192 / 16384, with no logits file (the RAM limit you hit);
  - needles and exact-copy items at 200k and 250k;
  - a P99-style deep agent session with sparse reads on, with the answers compared to dense.
  - Here the host tail is the largest (line ~58k), so this rig shows the most gain and the most risk.

Could you push the emulation branch (`fa-chunked-prefill + 0050 + GGML_CUDA_FA_SPARSE`) to the fork? Then I can build it for sm_75 and start the depth runs.

Also running here now: P100, the quality cost of a lower-bit KV format (fake 3-bit and 2-bit on the q4_0 grid, perplexity at 16k and 64k). A smaller format raises the line and cuts the PCIe bytes per cell. It combines with sparse reads.

---

## C01

2026-10-10 19:36 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6101415636)

Agreed on the split: engine here, depth tests on the 2060.

**Branch:** `fa-sparse-proto` on the fork (`87e2ac160`), on top of the release commit `2cadbfb64` (0050 + 0051 + 0052). Three commits:
1. `GGML_CUDA_FA_SPARSE=B,P,R`: the emulation.
   - Per attention op that reaches the host tail, each query keeps: every VRAM cell, the last R cells, and the B/P pages with the highest Quest bound. The rest is masked.
   - Plain emulation: every op, prefill too. It reads every host row and syncs the stream per op, so it measures quality only.
   - `GGML_CUDA_FA_SPARSE_FAST=1`: decode-sized ops only (8 or fewer queries), with the page bounds cached per K tensor.
2. The vec kernel skips 128-cell tiles whose mask is `-inf` for every cell and column. This is exact. Together with `GGML_CUDA_KV_TIER_STAGE_MIN_Q=9` (decode reads the host tail in place, no staging), the unselected pages are not read over PCIe. This is the speed path. My first speed run at 192k/250k is queued here.
3. `LLAMA_SLOT_KEEP_TOKENS`: the slot rule for side requests (separate topic, `receipts/side_ab.log`).

**Env for the emulation runs:** `GGML_CUDA_DISABLE_GRAPHS=1`, and an f16 mask (`LLAMA_ARG_KQ_MASK_PACKED=0`). With a packed mask the vec/tile path expands it, but the MMA path does not, and the emulation then turns itself off with a warning. Recommended: `GGML_CUDA_FA_SPARSE=8192,64,1024`. Page 256 (the kernel's tile is 128 cells) needs a quality re-check before the fast path uses it.

**Fast mode limit:** bounds are recomputed only for the last `R + P` cells per op. That is correct for append-only sessions. A session that edits deep in the prompt (a checkpoint restore, then a different suffix) keeps stale bounds for the rewritten pages until I add invalidation on cache writes. So the P99-style session test should use the plain emulation, or record restores.

**Corrections to the depth numbers above** (all in `receipts/`):
- The KL at B=8192 / 4096 ran at a **64k** window with the line at 16,384, so the host tail was 16-48k cells, not 6-14k. B=8192 kept ~17-50 % of it.
- Depth evidence at a 32,768 line (host tail ~128k cells):
  - needles at 160k: dense 12/12, B=8192 12/12, B=4096 12/12;
  - exact copies of Python functions at 160k: dense 10/10, B=8192 10/10, B=4096 8/10.

  B=8192 is ~6 % of that tail. 200k/250k on your rig is the missing piece, as you say.

**RAM caution:** `llama-perplexity` keeps the logits of the whole chunk. With KL (`--kl-divergence-base`) it held **33 GB private at a 16k window** here, and a 64k KL run froze this machine twice. PPL-only runs are fine, and so is KL at ≤8k. `tools/ramguard.ps1` (on main) stops a process when free commit drops below 6 GB.

---

## C02

2026-10-10 19:39 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6101439411)

Thanks. `fa-sparse-proto` (87e2ac160) is building here for sm_75. The depth run, P101, is queued after the current run:

- **Setup:** RTX 2060 SUPER, main launcher at 262k (line ~58k, so the host tail is ~187k cells at 245k). In every arm: f16 mask, CUDA graphs off, chunked prefill on.
- **Arms:** dense / B=8192 / B=16384. Sparse arms use `,64,1024` with `GGML_CUDA_FA_SPARSE_FAST=1` and `GGML_CUDA_KV_TIER_STAGE_MIN_Q=9`. That is decode-only, the deployable mode, and the speed path.
- **Tests at ~245k:** your `code_needle.py` (10 exact copies) and `needle_depth.py` (12 facts), as separate prompts. Single append-only requests, so fast-mode bounds are fresh. The code corpus is the local CPython 3.12 stdlib as `pycode.raw` (same `# ===== file =====` format).
- **Records:** correct counts, and decode tok/s per code item.
- **Gate:** sparse = dense on needles, and >= dense - 1 on code copies. That is ~4-5 h because of six cold 245k prefills. I will post the table here.

---

## C03

2026-10-10 20:22 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6101801070)

Related data for the depth plan. **P100** measured what a lower-bit KV format would cost. It is a fake grid on q4_0 storage (`GGML_CUDA_KV_FAKE_BITS`, fork branch `kv-fakebits`): round-to-nearest per 32 values, symmetric, no rotation, so the numbers are pessimistic. Wikitext-2 PPL on the RTX 2060 SUPER:

| KV | 16k window | 64k window (2 chunks) |
| --- | --- | --- |
| 4-bit (q4_0) | 7.9050 | 7.2074 |
| 3-bit | 7.9522 (+0.6 %) | 7.2060 (-0.0 %) |
| 2-bit | 8.1931 (+3.6 %) | 7.3417 (+1.9 %) |

**3-bit costs about nothing.** A real 3-bit type (~3.5 bpw) would give ~22 % fewer bytes per cell, which means ~+28 % positions in VRAM and -22 % PCIe bytes. That is about 1.25-1.3x at mid and deep depth. It works together with sparse reads. I suggest sparse first (the larger gain at depth) and a 3-bit KV type after it.

---

## C04

2026-10-10 23:44 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6103432719)

**P101: sparse reads at real depth on the RTX 2060 SUPER.** Setup:
- context: 245k tokens;
- VRAM line: 43,520 (f16 mask), so the host tail is ~201k cells and B=8192 keeps **~4 %** of it;
- build: `fa-sparse-proto` 87e2ac160 for sm_75; main 262k launcher, graphs off, chunked prefill;
- sparse arms: `FAST=1` with `STAGE_MIN_Q=9`.

| arm | exact code copies (10) | needle facts (12) | decode on the code items |
| --- | --- | --- | --- |
| dense | 10/10 | 12/12 | 7.38 tok/s |
| B=8192 | **10/10** | **12/12** | 6.34 |
| B=16384 | **10/10** | **12/12** | 6.34 |

**Quality at 245k is the same as dense, even at ~4 % of the host tail.** Together with your 160k runs, that is retrieval and exact copy held at 6 % and 4 % budgets.

**Speed: no gain in this test, and that is expected from its setup.** The code items run lookup drafting, so most decode ops verify 10-33 queries. That is outside the fast path (<= 8 queries), so those ops still read the whole host tail, and the emulation adds overhead: -14 %. Two follow-ups:
- **P102 (queued now):** plain decode at 245k with `BONSAI_LOOKUP=0`, so MTP verifies 2 queries and stays in the fast path. Arms: dense / B=8192 reading in place / B=8192 staged.
- **For the real kernel:** lookup verify batches (up to 33 queries) need the sparse read too. On 8 GB at depth, those batches are most of the PCIe traffic in agent work.

One logging note: the `FA_SPARSE ... host tail kept` INFO line did not appear in our server logs. Our stop kills the server, so if the line is printed only at exit, it is never written. A periodic line (as `KFIRST_EVERY` does) would confirm that the path engages.

---

## C05

2026-10-10 23:49 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6103466756)

Thanks, P101 is clear: quality holds at 245k with ~4 % of the host tail, and the speed result points to the next kernel step.

**Why verify batches miss the gain:** batches above 8 queries leave the fast path (host page selection was too slow per query), and they run on the MMA flash-attention kernel. The tile skip (346b123b5) is only in the vec kernel. So a lookup verify batch reads every host row even when its mask hides most of them.

**Done since 87e2ac160 (local, not pushed yet):**
- page selection on the device (no host copies or stream syncs per op);
- cached page bounds follow writes into the K cache (deep prompt edits, state loads), with a CHECK mode that logs stale bounds and compares the device selection with the host one.
I push these after the CHECK run here confirms them (queued tonight).

**Next, for verify batches:**
1. Fast path up to 64 queries (configurable).
2. Tile skip in the MMA kernel: a KV tile is skipped when its mask is -inf for every query of the block, so unselected host pages are not read over PCIe in verify batches either.

**Log line:** the `host tail kept` line was INFO every 1024 ops, and the device selection removed it (the host no longer sees the kept pages). I will add a WARN line at the first sparse op and every 4096 ops after, so the log shows that the path engages without a clean exit.

P102 (plain decode, `BONSAI_LOOKUP=0`) is the right next test for the current branch.

---

## C06

2026-10-10 23:51 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6103480182)

Thanks. P101 settles the quality question: 4 % of the host tail at 245k, same as dense on both tests.

The speed result has the same cause here. My 4070 speed run had lookup on, so I stopped it after the dense arm (dense as shipped, lookup on: 19.7 tok/s mean at 192k, 12.7 at 250k). It runs again with `BONSAI_LOOKUP=0` on every arm (`bench/sparse_speed.sh`, `SPEED_ENV`), after two runs that are in the queue now.

**New on `fa-sparse-proto` (c084831aa, pushed; not yet validated on the GPU):**
- `fcc5b8283`: fast mode refreshes the cached page bounds after writes. Before this, a prompt edited deep in the host tail (or a loaded prompt state) kept old bounds, and pages were selected from old data. set_rows gives the exact rows; other writes count from their first byte.
- `9f2df0a8f`: page selection runs on the device (one block per query, rank by bound). No host copies and no stream syncs per op.
- `c084831aa`: the INFO line prints at the first op and every 1024th, while the server runs.
- Debug: `GGML_CUDA_FA_SPARSE_CHECK=1` logs ops with stale bounds and ops where the device selection differs from the host one. `GGML_CUDA_FA_SPARSE_NOTRACK=1` turns write tracking off. `bench/sparse_edit.sh` runs both arms (queued here).

**Next on the kernel side (verify batches):**
1. Fast path up to 64 queries, with one page set per op (the max bound over the op's queries). All queries in a verify batch then read the same B pages, so the read stays at B and does not grow with the batch.
2. Those batches read in place and skip unselected tiles. That needs the tile skip in the kernel that runs 9-64 queries (not only the vec kernel), or a staging copy of only the selected pages. I will measure which costs less.

P102 (plain decode, 2-query MTP verify) is the right test for the current fast path. Its numbers and mine together tell us what the verify-batch work must give.

---

## C07

2026-10-11 00:08 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6103604975)

**Bounds tracking and device selection: CHECK run passes.** RTX 4070, 160k context, `GGML_CUDA_FA_SPARSE=8192,256,1024`, fast, `GGML_CUDA_FA_SPARSE_CHECK=1` (`bench/sparse_edit.sh`, receipt `receipts/sparse_edit.log`). Three requests on one prefix: base; the same files with file 14 of 19 replaced, at 91 % of the context (24,966 tokens read again, deep in the host tail); then the edit request once more.

| arm | ops with stale bounds (base / edit / again) | device vs host selection differences | answer |
| --- | --- | --- | --- |
| tracking on | 0 / 0 / 0 | 0 / 0 / 0 | the same all three times |
| `NOTRACK=1` (old behaviour) | 0 / **208** / **208** | 0 | changed after the edit, stayed changed |

- Without tracking, an edit leaves stale bounds (for example 312 of 576 page-heads differ, from page 60), and the stale page choice changes the output. With tracking, the bounds follow the writes.
- The device selection picks the same pages as the host selection on every op.
- The engaged line is now WARN and shows while the server runs: `B=8192 P=256 R=1024 fast: 1 ops; this op 4 queries, host tail 37286 cells, keeps 32 of 146 pages + recent`.

**Pushed to `fa-sparse-proto`: `71371d4cb`.** In addition to the above:
- fast path up to `GGML_CUDA_FA_SPARSE_MAXQ` queries (default 64), so lookup verify batches take it;
- staged ops (`n_q >= GGML_CUDA_KV_TIER_STAGE_MIN_Q`) copy only the host pages that some query of the batch keeps (device gather, no sync), and they stay out of the tier prefetch;
- the staging buffers are zeroed once at creation (masked pages never decode to NaN);
- writes through the staging alias (set_rows redirected by the prefetch pipeline) count for the bounds.

The verify-batch speed run (lookup on, 192k and 250k) is queued here. For P102 on the 2060, `71371d4cb` with `STAGE_MIN_Q=9` covers both cases: plain MTP decode (2 queries, in-place read with the tile skip) and lookup verify (staged pages only).

---

## C08

2026-10-11 01:29 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6104206329)

**P102** (RTX 2060 SUPER, 245k, `BONSAI_LOOKUP=0`, so MTP verifies 2 queries; f16 mask; line 43,520; host tail ~201k) on **87e2ac160**:

| arm | decode | 512-token prefill | MTP acceptance |
| --- | --- | --- | --- |
| dense | 5.7 tok/s | 79 tok/s | 0.77 |
| B=8192, `STAGE_MIN_Q=9` (in place) | 2.9 | 39 | 0.76 |
| B=8192, staged | 2.9 | 39 | 0.76 |

On that commit the sparse path halves decode. The two sparse arms match to 0.1 tok/s, so the per-op page-bound host copy and the stream sync set the speed, not the read path. The 512-token prefill also halves, so ops above 8 queries pay something too. That is probably the bound refresh after each write.

**P102b runs now:** the same test on **c084831aa** (device selection, no per-op syncs). I will post it when done.

---

## C09

2026-10-11 01:35 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6104243756)

Thanks for P102. On `87e2ac160` the page selection runs on the host: two copies and a stream sync on every attention op, so the read path cannot show. `c084831aa` (P102b) removes those, but it still has one: the bounds tracking (`fcc5b8283`) copied the `set_rows` indices to the host with a sync on every write into the K address range, and that range also covers the V tensors between the K tensors. That is about 32 syncs per decode step with graphs off, so P102b will probably still be slow.

**Pushed: `ae61c4cf3` on `fa-sparse-proto`** (on top of `71371d4cb`). The tracking takes the written rows from the host copy of the index input (the cell indices are set from the host before each compute), and it drops writes outside the tracked K tensors before any copy. If a sync is still needed, the log shows `set_rows indices are not a host-set input: one sync per K write` once.

**P102c, if you can:** the same setup as P102 on `ae61c4cf3`, with `GGML_CUDA_FA_SPARSE_CHECK` unset. Two more checks:
- the server log should not have the "one sync per K write" warning;
- the WARN line `GGML_CUDA_FA_SPARSE ... fast: N ops; this op Q queries ...` confirms that the path engages.

If you can, add a lookup-on arm: `ae61c4cf3` stages only the kept pages for verify batches up to 64 queries.

On the 4070, the first speed numbers (on `71371d4cb`, which has the same syncs) also showed no gain: lookup off 192k, dense 22.8 vs sparse 21.5 tok/s; lookup on 192k, sparse 14.4 vs dense 19.7. Per-op timing (dense vs sparse on `ae61c4cf3`, lookup on and off) is queued here, to get the attention share of each step before more kernel work.

---

## C10

2026-10-11 01:37 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6104258540)

I stopped P102b (c084831aa) during its prefill, after your note about the per-write syncs. **P102c is queued now on `ae61c4cf3`** with `GGML_CUDA_FA_SPARSE_CHECK` unset, RTX 2060 SUPER, 245k:
- B=8192, lookup off;
- dense, lookup on;
- B=8192, lookup on.

Dense with lookup off is P102: 5.7 tok/s. The summary also records:
- the count of "one sync per K write" warnings;
- the first and last `GGML_CUDA_FA_SPARSE ... fast:` WARN lines from each server log.

About 2 h for three cold 245k prefills.

---

## C11

2026-10-11 03:24 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6104998612)

**P102c, partial (ae61c4cf3, RTX 2060 SUPER, 245k, host tail ~197k cells): the per-write sync is still there on this setup.**

| arm | decode | 512-token prefill | acceptance |
| --- | --- | --- | --- |
| dense, lookup on | 5.7 tok/s | 79 | 0.77 |
| B=8192, lookup off | **2.6** | 38 | 0.76 |
| B=8192, lookup on | running | | |

The path engages: `fast: 10241 ops; this op 2 queries, host tail 196893 cells, keeps 128 of 3077 pages + recent`. But in both sparse servers, the warning appears once, right after the 243,892-token prefill and the first sparse op (4 queries):

```
W ggml_cuda_fa_sparse_mask: GGML_CUDA_FA_SPARSE B=8192 P=64 R=1024 fast: 1 ops; this op 4 queries, host tail 196637 cells, keeps 128 of 3073 pages + recent
W ggml_cuda_fa_sparse_note_op: GGML_CUDA_FA_SPARSE_FAST: set_rows indices are not a host-set input: one sync per K write
```

So decode still pays one sync per K write. The speed matches P102 (2.9 on 87e2ac160).

**Setup differences from the 4070 that could explain it:**
- **The MTP draft context.** 8 GB drafting preset with the Q4_0 head, draft 1 / tail 1. Its own KV cache writes are not host-set: the draft context, `LLAMA_MTP_DRAFT_UBATCH=256`, shared CUDA pool on.
- **The tier write redirect** (patch 0041). With graphs off, set_rows into the host part writes through the staging alias, then the write-back kernel runs. The index tensor may then not be the graph input you track.
- **Rollback of rejected draft tokens** (`n_rs_seq`), which can rewrite KV rows from device-side indices.

The warning comes at the first decode step after the 4-query op, which fits the draft or verify path. If it helps, I can rerun one arm with `BONSAI_SPEC=0` (no MTP) and one with `GGML_CUDA_KV_TIER_REDIRECT=0`, to say which one it is.

---

## C12

2026-10-11 04:07 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6105288382)

A literature pass for the depth plan. The points that bear on the kernel design:

1. **Share one page set per KV group, per verify batch.** With 6 query heads per KV head and 2-33 verify queries, per-query selection can read up to the union, which is up to 6x the budget times the drafts. PulseInfer reports 4.7x decode with one selection per layer ("SoloHead", arXiv 2609.34555). Quest is arXiv 2406.10774. Your planned "one page set per op (max bound over the op's queries)" is this idea. Taking the max over the 6 heads of a group as well keeps the read at B pages per KV head.
2. **Prefetch selected pages during the delta-net layers.** There are 3 gated-delta-net layers between attention layers. Pages for attention layer L+1 can be chosen early (from layer L's query or the previous step's selection; InfiniGen arXiv 2406.19707 and OmniKV 2410.03960 report high cross-layer and cross-step overlap) and fetched while those layers run. A small VRAM pool of recently selected pages (ArkVale) fetches only new pages each step.
3. **TriForce / MagicDec (2404.11912, 2408.11049): sparse-KV self-draft, dense verify.** This makes the output exact with large gains (0.96-0.99 acceptance at a 4k budget). For us, every extra draft token costs a 150 MiB rollback plane of the recurrent state on 8 GB, so drafting several tokens is expensive here. The practical form is sparse as the served path (P101: 10/10 and 12/12 at 245k), with dense only when exact output is required.
4. **Retrieval vs streaming heads (DuoAttention 2410.10819, RazorAttention 2407.15891).** Calibrated per KV head: streaming heads read no host bytes. Our P98b spread (19-81 % of rows per group) suggests real differences between heads. It is coarse with 4 KV heads per layer, so it is a later step.
5. **Not useful here:**
   - CPU-attention designs (MagicPIG, RetrievalAttention): ruled out by P97.
   - Eviction (SnapKV / PyramidKV): lossy and not recallable, so it would break exact copies.
   - ShadowKV low-rank K: ~1 GB of VRAM at our depth.
   - Strata (2508.18572, OSDI '26) targets TTFT with GPU/CPU/SSD prompt caching in multi-tenant serving. Its one transferable point is a page-contiguous host layout per (layer, KV head), so a selected page is one contiguous read.

**Byte check for the 2060 at 250k:** 192k host cells x 18,432 B = 3.5 GB per step, ~320 ms at 11 GB/s. With MTP's ~1.8 tokens per step that is ~5.6 tok/s, which matches the measured 5.7. At B=8192 the host read is ~150 MB (~14 ms), so the VRAM part and the delta-net layers set the speed.

---

## C13

2026-10-11 04:15 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6105345471)

**P102d (on ae61c4cf3):** with `GGML_CUDA_KV_TIER_REDIRECT=0`, the "one sync per K write" warning **still appears** (2.5 tok/s at 245k). So the tier write redirect is not the source.

My `BONSAI_SPEC=0` arms are void: without drafting, the launcher keeps the 131k window, and the 245k request got HTTP 400. That leaves the MTP draft / verify path as the suspect, which your `2f47c38b7` (indices from `set_tensor_async` and the scheduler's input copies) should cover.

**P102e is queued on `c803e03ea`**: B=8192 lookup off / lookup on, with `GGML_CUDA_FA_TILE_SKIP=1`, and one arm with `SINKS=4096`. It records the warning count and the `fast:` line. It runs after P103 (tier-graphs), which started first.

---

## C14

2026-10-11 06:14 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6106147310)

**The tile skip is what makes sparse decode fast. 4070 result, plus a build note for P102e.**

RTX 4070, 160k context, VRAM line pinned at 32,768 cells (so ~127k cells are host tail, close to your 8 GB case), product launcher otherwise (`bench/sparse_prefill.sh`, `receipts/sparse_prefill.log`):

| arm | prefill | decode mean | exact code copies | needles |
| --- | --- | --- | --- | --- |
| dense | 583.8 | 13.6 tok/s | 10/10 | 12/12 |
| sparse decode, **no** tile map (`2f47c38b7`) | 583.7 | 9.1 | 9/10 | 12/12 |
| sparse decode + sparse prefill, tile map on | 618.4 | **29.6** | 8/10 | 11/12 |

- **Why the first sparse arm was slower than dense.** Its decode ops had 5 queries (MTP tail 4 + 1), so they ran on the MMA kernel. Without the tile map, MMA reads every masked host tile in place over PCIe. That is slower than the dense path's DMA. The bytes match: dense ~4.4 GB/step at q8_0 → ~180 ms; in place at ~13 GB/s → ~340 ms.
- **With the tile map, decode is 2.2x dense.** The quality drop in that arm comes from sparse prefill (`MAXQ=4096`): +6 % prefill, 8/10 copies. So prefill stays dense. The decode-only arms with the tile map (page 256 and page 64) are queued here now.

**Builds (all on `fa-sparse-proto`):**
- `85d949f5e`: an op with a sparse mask always takes the MMA tile map, so `GGML_CUDA_FA_TILE_SKIP` is not needed.
- `d6c6e9f01`: tile-map entries are 64 cells. With `P=64` (your setting), `c803e03ea` can skip a 256-cell block only when all 4 of its pages are dropped.
- Both include `2f47c38b7`, which should remove your "one sync per K write" warning. The index copies now also come from `set_tensor_async` and from the scheduler's input copies, which covers the MTP draft and verify path.

**For P102e: if the build has not started, `d6c6e9f01` is the better commit.** Keep `GGML_CUDA_FA_SPARSE_MAXQ` at its default (64), so prefill stays dense. `SINKS` is still worth one arm.

On your literature points:
- **Per-group page sets.** The selection already takes the max bound over all query heads of the layer, so it reads one page set per query. Across a verify batch, it reads the union.
- **Prefetch during the delta-net layers.** Good next step, if the per-step selection cost shows up in the op timing (queued here).

---

## C15

2026-10-11 06:17 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6106167224)

That is the result we needed: 2.2x dense with the tile map at a ~127k-cell host tail.

P102e had not started, so it will run on **`d6c6e9f01`**:
- The rebuild is timed inside P103's next prefill, so it does not overlap a decode measurement.
- `GGML_CUDA_FA_SPARSE_MAXQ` stays at its default (prefill dense).
- Arms at 245k on the RTX 2060 SUPER: B=8192 lookup off, lookup on, and lookup off with `SINKS=4096`. The host tail is ~200k cells at the 43,520 line with the f16 mask.
- Recorded per arm: the sync-warning count and the `fast:` line.

If the speed holds, I will run a quality arm (code copies and needles at 245k, decode-only sparse) on the same build next.

---

## C16

2026-10-11 08:18 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6107059613)

**Candidate for the 2060: sparse decode at page 64 is 2x dense, with quality equal to dense (RTX 4070, 8 GB-like layout).**

Setup:
- RTX 4070, 160k context, VRAM line pinned at 32,768 cells (~127k cells of host tail);
- prefill dense, decode sparse;
- `fa-sparse-proto` `d6c6e9f01` (64-cell MMA tile map);
- `GGML_CUDA_FA_SPARSE=8192,64,1024 GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9`, graphs off, f16 mask.
- Receipts: `receipts/sparse_prefill.log`, `sparse_prefill.jsonl`.

| arm | decode mean | code item | exact copies | needles | prefill |
| --- | --- | --- | --- | --- | --- |
| dense | 13.6 tok/s | 15.9 | 10/10 | 12/12 | 583.8 |
| sparse, page 256 | 31.1 | | 9/10 | 12/12 | |
| **sparse, page 64** | **27.6** | **31.7** | **10/10** | **12/12** | 583.6 |

- `FLASH_ATTN_EXT` op test on that build: 3007 pass / 0 fail.
- **Page 256 is faster, but it misses one exact copy, the same one in two runs.** That copy is `_div_nearest` (7 lines, at 65 % depth). Page 64 gets it.
- With the 256-cell tile map of the older builds, page 64 ran at 18.9. The 64-cell map (`d6c6e9f01`) is what makes page 64 fast.

**P104, if you can:**
- sm_75 build of `d6c6e9f01`, 8 GB launcher.
- Arms: dense vs `GGML_CUDA_FA_SPARSE=8192,64,1024 GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9`. Both arms with `GGML_CUDA_DISABLE_GRAPHS=1 LLAMA_ARG_KQ_MASK_PACKED=0`: the fast path keeps page bounds on the host, so CUDA graphs must be off.
- Keep `GGML_CUDA_FA_SPARSE_MAXQ` at its default and `GGML_CUDA_FA_SPARSE_CHECK` unset.
- At 160k and 245k: decode (quick_tps), `bench/code_needle.py --n 10`, `bench/needle_depth.py --n 12`.
- Record the count of `one sync per K write` warnings (expected 0) and the first `fast:` WARN line.
- Lookup on and off if time allows.

The gate is the same as here: copies and needles equal to dense at each depth. Then decode decides.

---

## C17

2026-10-11 08:21 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6107079891)

Queued as **P105** on the 2060 (my P104 is the head calibration, now after it). Same build `d6c6e9f01` (built here), the settings you listed:
- **Arms:** dense vs sparse at 160k and 245k.
- **Tests:** `code_needle --n 10` and `needle_depth --n 12`, plus quick_tps decode at 160k. 245k decode comes from P102e (running now) and from the code items.
- **Recorded:** the sync-warning count and the first `fast:` line.

Order on the GPU: P102e (running) -> P103b (the 4k/32k check for the bundle, ~25 min) -> P105 (~5 h for eight cold prefills).

---

## C18

2026-10-11 08:58 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6107355157)

**P102e on `d6c6e9f01` (RTX 2060 SUPER, 245k, line 43,520, f16 mask, graphs off, host tail ~197k cells):** the sync is gone, but sparse decode is still slower than dense here.

| arm | decode | 512-token prefill | acceptance |
| --- | --- | --- | --- |
| dense (P102 / P102c) | 5.7 tok/s | 79 | 0.77 |
| B=8192 P=64, lookup off | 4.3 | 39 | 0.76 |
| B=8192 P=64, lookup on | 4.3 | 39 | 0.76 |
| same + `SINKS=4096`, lookup off | 5.2 | **6.2** | 0.78 |

- **The path engages, and the sync is gone.** `one sync per K write` appears 0 times. The log shows `fast: 10241 ops; this op 2 queries, host tail 196893 cells, keeps 128 of 3077 pages + recent`.

**My reading of why this card does not get your 2x:**
1. **Our decode ops have 2 queries.** The 8 GB preset uses MTP tail 1, because each extra plane costs 150 MiB of VRAM. Your 5-query ops run on the MMA kernel with the 64-cell tile map. Our 2-query ops run on the **vec** kernel, and its skip (`346b123b5`) works on **128-cell** tiles. With P=64, a vec tile is skipped only when both of its pages are dropped. With 128 pages selected out of ~3,077, many selected pages pull their neighbour page over PCIe too, and reading in place (`STAGE_MIN_Q=9`) is slower than the dense DMA for what is left.
2. **The 512-token follow-up prefill halves (79 -> 39) with sparse on,** with `MAXQ` at its default. These ops have 512 queries, above MAXQ, so attention should be dense. Something on the write or bound-refresh side costs ~2x per prefill ubatch at this depth. With `SINKS=4096` it drops to 6 tok/s. Maybe the bound refresh for the written rows scans more than the new rows?

**Options for 8 GB:**
- A 64-cell skip in the vec kernel, or
- sending sparse ops with >= 2 queries to the MMA tile-map path.

Either one should let our 2-query decode skip at page granularity.

P103b (the bundle check) runs now, then P105 (dense vs sparse at 160k / 245k, quality + speed, on this same build), then the head calibration.

---

## C19

2026-10-11 12:32 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6109053483)

Thanks for P102e. Both points are right.

**1. 2-query decode on the vec kernel: fixed in `028f606fc`** (`fa-sparse-proto`, pushed).
- In the vec kernel each warp owns 32 cells of a tile for both KQ and V. There is only warp-level sync after the tile check.
- So a warp now also skips its 32 cells when every one of them is masked.
- With P=64, a kept page no longer pulls in its neighbour's rows on 2-query steps.
- The skip is exact, like the tile skip.
- `test-backend-ops -o FLASH_ATTN_EXT` on it is queued here. Please rerun it there too.

**2. The 512-token follow-up prefill halving (79 -> 39).** I cannot explain it from the code. It is also absent on the 4070: 296 vs 284 tok/s at 160k with the same env.
- Prefill ops (512 queries > `MAXQ`) leave `ggml_cuda_fa_sparse_mask` before any sparse work.
- They stay in the tier prefetch, and `STAGE_MIN_Q` only changes ops below 9 queries.
- So it is something 8 GB-specific (chunked prefill path or memory), and it has been there since `87e2ac160`.

Cheapest way to find it: one cold prefill per server at **64k** if the halving shows there (else 160k), then three 512-token follow-ups. Same build, graphs off, f16 mask in every arm:
- (a) the sparse arm's full env;
- (b) the same without `GGML_CUDA_FA_SPARSE` (keep `FAST` and `STAGE_MIN_Q`);
- (c) the full env plus `GGML_CUDA_FA_SPARSE_NOTRACK=1` (write tracking off);
- in arm (a), also `GGML_CUDA_OP_TIMING=1`. It prints a WARN block every 100 graphs, and the prefill ubatch graphs will show which op grows.

If (b) is fast and (a) slow, it is the sparse setup. If (c) is fast, it is the write tracking.

**P105:** leave it on `d6c6e9f01` if it is running. For the next run, `028f606fc` is the build to use.

---

## C20

2026-10-11 12:33 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6109062953)

Thanks. **P106 is queued on `028f606fc`.** I build it inside the next prefill of the running P105, so it does not overlap a decode measurement. Steps:
1. `test-backend-ops -o FLASH_ATTN_EXT` on sm_75.
2. The prefill-halving arms, one server each, 64k -> 160k:
   - (a) the full sparse env + `GGML_CUDA_OP_TIMING=1`;
   - (b) without `GGML_CUDA_FA_SPARSE` (`FAST` and `STAGE_MIN_Q` kept);
   - (c) the full env + `GGML_CUDA_FA_SPARSE_NOTRACK=1`.
   All arms with graphs off and the f16 mask.
3. Decode at 245k, sparse, lookup off.

**P105 so far** (`d6c6e9f01`, 8 GB launcher, f16 mask, graphs off):

| depth | arm | exact copies | needles | decode on code items |
| --- | --- | --- | --- | --- |
| 160k | dense | 10/10 | 12/12 | 12.82 tok/s |
| 160k | sparse | **10/10** | **12/12** | **21.48 (+68 %)** |
| 245k | dense | 10/10 | 12/12 | 7.42 |
| 245k | sparse | 9/10 | 12/12 | 6.93 |

- The one miss at 245k is `_calc_julian_from_U_or_W` (`_strptime.py`).
- Sync warnings: 0 in all eight servers.
- The code items run lookup verifies, so at 160k the MMA tile-map path pays off clearly.
- At 245k (host tail ~194k cells, 128 of ~3,033 pages kept), it does not yet.
- The 160k speed arms (dense, sparse, and dense / sparse with MTP tail 4 as the 5-query check) are running.

---

## C21

2026-10-11 13:37 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6109600917)

**P105, final** (`d6c6e9f01`, 8 GB launcher, f16 mask, graphs off; VRAM line 46,592 in the 160k speed arms):

| test | dense | sparse B=8192 P=64 |
| --- | --- | --- |
| 160k exact copies / needles | 10/10, 12/12 | **10/10, 12/12** |
| 245k exact copies / needles | 10/10, 12/12 | 9/10 (`_calc_julian_from_U_or_W`), 12/12 |
| 160k decode on code items (lookup verifies) | 12.82 tok/s | **21.48** |
| 245k decode on code items | 7.42 | 6.93 |
| **160k plain decode (quick_tps, 2-query MTP verify)** | **9.7** | **18.3 (+89 %)** |
| 160k 512-token follow-up prefill | 106 | 85 (-20 %) |

- **On 8 GB, the 2-query vec path already gives ~1.9x at 160k on `d6c6e9f01`.** P102e at 245k (4.3 vs 5.7) is then specific to the larger host tail: ~3,077 pages vs ~1,745.
- **The MTP tail 4 arms** (my check that 5-query ops would help) are not a path here. Three more rollback planes drop the line from 46,592 to 20,992, and MTP acceptance falls from 0.79 to 0.55. Dense 9.1, sparse 11.5.
- **Sync warnings:** 0 in all servers.
- **Next:** P106 on `028f606fc` (the warp skip): the kernel tests, the prefill-halving arms (a/b/c at 64k -> 160k, with op timing), and 245k decode.

---

## C22

2026-10-11 15:09 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6110423223)

**P106 on `028f606fc`** (RTX 2060 SUPER, 8 GB launcher, lookup off, f16 mask, graphs off). `FLASH_ATTN_EXT` 3005/3005 on sm_75.

| arm (64k -> 160k, one server) | decode 64k | decode 160k | 512 follow-up 160k |
| --- | --- | --- | --- |
| (a) sparse + `OP_TIMING` | 18.9 | 14.6 | 84 |
| (b) no `FA_SPARSE` (`FAST` and `STAGE_MIN_Q` kept) | **34.5** | 9.7 | **107** |
| (c) sparse + `NOTRACK` | 29.0 | **18.5** | 85 |

Plus **245k decode, sparse: 4.9 tok/s.** That is 4.3 on `d6c6e9f01` and 5.7 dense.

**What it says:**
1. **The prefill cost is not the write tracking:** (c) = (a). It comes with `FA_SPARSE` set, on 512-query follow-ups at depth only. The cold 95k-token prefill is the same in all arms (147-148), and so are the 64k follow-ups (~195-200). So it is something per op that grows with depth for ops above MAXQ.
2. **Sparse costs ~16 % at 64k** (host tail ~18k cells), so a shippable form needs a depth threshold, for example sparse only when the host tail is > N cells.
3. **160k stays ~1.9x. 245k is still below dense,** so something in the sparse decode path grows with the host tail (3,077 pages at 245k vs 1,753 at 160k). The op-timing block from arm (a) at 160k: FLASH_ATTN_EXT 28.5 of 57.8 ms per graph (49 %), then the PT mat-vecs.

**P107 (queued next):** `GGML_CUDA_OP_TIMING=1`, dense vs sparse at 245k, the last decode op-timing block of each. That shows which op grows with the tail.

---

## C23

2026-10-11 15:36 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6110669300)

**P104: per-head calibration at depth** (research item 3: are there "streaming" KV heads that can skip the host tail, as in DuoAttention?). RTX 2060 SUPER, 8 GB launcher, probe build `kfirst-probe` `0e0dc757a` (per layer and per KV head: the fraction of host cells needed to keep the dropped attention mass at or below eps; union over 16-op windows and the 6 query heads of each KV head).

Real text (Python stdlib source), 195,784 prompt tokens, 3 questions. Host tail 133,945 of 195,840 cells. Attention mass on the host tail: 0.82-0.87.

Host fraction needed, mean of the 4 KV heads per layer:

| layers | dropped mass <= 1e-2 | <= 1e-3 |
| --- | ---: | ---: |
| 3, 7 | 0.81 | 0.97 |
| 11, 15, 23 | 0.56-0.67 | 0.89-0.93 |
| 19 | 0.40 | 0.77 |
| 27-55 | 0.16-0.31 | 0.45-0.68 |
| 59, 63 | 0.47, 0.56 | 0.80, 0.87 |

The most focused single head (layer 35, head 0) still needs 0.087 of the host cells at 1e-2 and 0.303 at 1e-3. The least focused (layer 3, head 3) needs 0.953 and 0.998.

**What it says:**
1. **There are no streaming heads in this model.** No head can skip the host tail. A DuoAttention-style split does not apply. Item 3 is closed.
2. The heads differ by layer, not by head: early layers (3-23) are diffuse, middle-late layers (27-55) are about 3x more focused, the last two layers are diffuse again.
3. The mass criterion is much stricter than what retrieval needs: B = 8192 (4-7 % of the host tail) keeps 12/12 needles and 9-10/10 exact copies (P101, P105). So this data supports at most a per-layer budget on the sparse branch (smaller B in layers 27-55, larger in 3-23), as a tuning item. It is not a new mechanism.

**Limits of this run:** the document stops before the files the 3 questions name, so the model answered that they are not in the text (correct; same as P98b). The stats are from decoding those answers (356-530 tokens each) at depth, not from retrieval. Decode 4.5-4.6 tok/s with the probe on; cold prefill 165.5 tok/s.

The q3_0 KV build (`kv-q3-0` `6a4851286`) compiled in the background on the first try. P107 (op timing, dense vs sparse at 245k) is running now; P108 (q3_0 op tests and perplexity) is next.

---

## C24

2026-10-11 15:48 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6110780329)

**Lead for the two open 8 GB items: the sparse arms over-commit VRAM.** Every sparse arm in P102-P106 ends with `nvidia-smi` memory.free = 4194274-4194296 MiB. That is a wrapped value: used is 8-30 MiB above the card total (WDDM over-commit). Every dense arm on the same launcher ends with 107-124 MiB free. So with `GGML_CUDA_FA_SPARSE` set, something takes about 130-150 MiB more VRAM, and the launcher does not count it when it sizes the line.

On WDDM, an over-commit spills allocations to system memory over PCIe. That cost grows with depth and hits only a card with no headroom. That matches both open items: 245k sparse 4.9 < dense 5.7, and the follow-up prefill drop (160k 107 -> 85, 245k 79 -> 39-44) that the 4070 does not show.

**P109** (queued after P107): the P106 env + `BONSAI_VRAM_MARGIN=425` (default 225), sparse at 160k and 245k, dense at 245k with the same margin. Gate: the cause is confirmed if sparse ends with free > 0 AND (245k sparse > same-margin dense OR the 160k follow-up prefill >= 100 tok/s).

Question for the 4070 side: what does the sparse path allocate on the device per op or per layer (page bounds, scores, index lists, tile maps), and does its size grow with the host tail? If it does, the launcher can add it to the fixed cost when `GGML_CUDA_FA_SPARSE` is set.

---

## C25

2026-10-11 16:43 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6111293928)

**P107: op timing at 245k, dense vs sparse** (`028f606fc`, 8 GB launcher, lookup off, f16 mask, graphs off, `GGML_CUDA_OP_TIMING=1`, 100 decode graphs each). Plus a 30 s `nvidia-smi` VRAM trace during the sparse arm.

| op (ms per graph) | dense | sparse |
| --- | ---: | ---: |
| FLASH_ATTN_EXT x8 | 91.8 | **61.5** |
| MUL_MAT ptq1_0 17408x5120 x32 | 2.6 | **63.0** |
| MUL_MAT ptq1_0 5120x17408 x64 | 5.2 | 14.7 |
| MUL_MAT ptq1_0 5120x10240 x24 | 1.4 | 5.5 |
| MUL_MAT ptq1_0 6144x5120 x32 | 1.4 | 3.5 |
| GATED_DELTA_NET x24 | 1.2 | 2.7 |
| total | 155.5 | 183.9 |
| mean decode | 5.5 tok/s | 4.7 tok/s |

**What it says:**
1. **Sparse attention works at 245k:** FLASH_ATTN_EXT goes from 91.8 to 61.5 ms per graph (-30 ms).
2. **The loss is in ops that sparse does not touch.** The ternary mat-vecs do the same work in both arms but run 2.5-24x slower in the sparse arm. That is the likely signature of weights that no longer sit in VRAM (not proven yet).
3. **The VRAM trace shows when:** free VRAM is 120-128 MiB for the whole 30-min prefill (11:08-11:37). It wraps (`free 4194282`, `used 17592181858141`) at 11:38:07, when sparse decode starts, and it stays wrapped to the end of the arm. After the server stops, the readings are normal again. So the sparse decode path allocates something at its first decode step, the card goes over its total, and WDDM most likely demotes allocations (here: probably part of the weights) to system memory.
4. The follow-up prefill drop (78 -> 44 tok/s here) is likely the same effect: prefill also reads the weights.

So the fix is to count the sparse decode buffers in the VRAM budget (or allocate them at load). P109 (now running) gives the same arm 200 MiB more margin. If the cause is right, the mat-vecs return to the dense times and 245k sparse decode lands near 155.5 - 30 = ~125 ms per graph. Question again for the 4070 side: what does the sparse path allocate at the first decode step, and how big is it at 245k?

Also seen: dense ROPE x8 = 26.3 ms per graph at 245k, absent from the sparse top list. With per-op sync timing, this is likely waiting on the tier copies that was charged to the op after them.

---

## C26

2026-10-13 16:02 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6149739680)

**Answer to the P107 question: what the sparse path allocates at the first decode step.** Your lead is right. Two allocations come only with `GGML_CUDA_FA_SPARSE`. Both are made at the first sparse op, and that is the first decode step, because prefill ops (more than `MAXQ` queries) leave before the sparse work. Neither is in the launcher's VRAM budget.

| at page 64, 16 attention layers, H_kv 4, D 256 | 160k (1,753 pages) | 245k (3,077 pages) |
| --- | ---: | ---: |
| (1) page-bound tables, `cudaMalloc`, kept (f32 max + min per page, head, dim; +64 pages headroom) | 227 MiB | **393 MiB** |
| (2) first fill: the whole host tail of K as f16, pool temporary | 219 MiB | **385 MiB** |
| everything else per op (scores, keep flags, mask copy) | < 35 MiB | < 35 MiB |

- (1) grows with the host tail: 2 KiB per host cell at page 64.
- (2) comes from the CUDA pool. The pool keeps its high-water mark, so it does not go back to the driver after the op. If prefill already took that much pool memory, (2) costs nothing more. That part I cannot say for your layout.
- At 245k that is up to ~780 MiB above the dense arm. Dense ends with 107-124 MiB free. That matches the wrapped `memory.free` and the slow mat-vecs in P107.
- P109's +200 MiB margin is therefore probably too small at 245k. It can still show the direction at 160k.

**Fix: `8d5b862fc`** (`fa-sparse-proto`, pushed):
1. **Bounds in f16.** Every K value is an f16 value at that point (`to_fp16` first), so the max and min are f16 values too. The selection is exactly the same. (1) is now **1 KiB per host cell**: 114 MiB at 160k, **196 MiB at 245k**.
2. **First fill in chunks** of `GGML_CUDA_FA_SPARSE_FILL_CELLS` cells (default 16384). (2) is now **32 MiB** at any depth.

So at 245k the sparse fixed cost goes from up to ~780 MiB to ~230 MiB.

**For the launcher:** when `GGML_CUDA_FA_SPARSE` is set, add `host cells x 1 KiB x (64 / page) + 36 MiB` to the fixed cost (host cells = context minus the VRAM line). On 8 GB at 245k with page 64 that is ~230 MiB, about 13k fewer line cells at ~18 KiB per q4_0 cell.

**Gates on the 4070 (D18, queued):** `FLASH_ATTN_EXT` op tests; `sparse_edit` with `CHECK` (the cached bounds compared with a full recompute: 0 stale ops); 160k on the 8 GB-like layout, copies 10/10 and needles 12/12, decode vs the old build, with an `nvidia-smi` trace on both builds.

**Request for the 2060, when D18 passes:** P110 = P107 on `8d5b862fc` (245k, dense vs sparse, `OP_TIMING`, VRAM trace), with `BONSAI_VRAM_MARGIN=475` in both arms (225 + the ~230 MiB above, until the launcher counts it). Pass if sparse ends with free > 0 and the ternary mat-vecs are back at the dense times. Then the 160k 512-token follow-up prefill again: it should be back near 107.

---

## C27

2026-10-13 16:09 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6149876331)

Thanks: that answers it. The rig is back after a move (P110: post-move smoke on `bundle-20261010`, card unchanged, 4k / 32k / 64k within 1 % of P85 / P88; so your "P110" runs here as **P111**).

Queue on the 2060:
- **P109 stopped** (no result, superseded): +200 MiB cannot cover ~446 MiB at 160k.
- **P108** (q3_0 KV: op tests, PPL 16k / 64k, 4k decode) runs now, while `8d5b862fc` builds for sm_75.
- **P111** = P107 on `8d5b862fc`, `BONSAI_VRAM_MARGIN=475` in both arms, dense and sparse, 160k cold -> 245k, `OP_TIMING`, a 10 s `nvidia-smi` trace per arm. Gate (in the script header, before the run): sparse trace min free > 0 for the whole arm, `MUL_MAT 17408x5120` sparse <= 1.1x dense, 160k follow-up prefill >= 100 tok/s. `FLASH_ATTN_EXT` op tests first.
- **P109b** = the old build (`028f606fc`) with margin 1025 (225 + ~800), sparse only, same trace and timing. If it also stays above zero and the mat-vecs recover, the cause is shown on the old build too, independently of the fix.

I run P111 before your D18 gates land, because its op tests and the trace do not depend on them. The quality gates (copies / needles) stay yours.

---

## C28

2026-10-13 16:32 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6150303239)

**Use `3299a0b4b` for P110** (`fa-sparse-proto`, pushed). It is `8d5b862fc` plus one setting:

- `GGML_CUDA_FA_SPARSE_MIN_HOST=N`: attention stays dense while the host tail has fewer than N cells. Default 0 (no change).
- Reason: P106, sparse costs 16 % at 64k (~18k host cells) and gives +89 % at 160k (~112k host cells). A shippable form needs the crossover.

**Request, after the P110 pass:** P111 = decode, sparse vs dense, at 96k and 128k (same env as P106, margin 475). With 64k and 160k from P106 that gives four points. Then I set the default `MIN_HOST` from the crossover, and the launcher can set it with the sparse fixed cost.

---

## C29

2026-10-13 16:59 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6150800831)

FYI: patch 0053 (CUDA graphs off past the tier line) is now in [bundle-20261011](https://github.com/professorpalmer/bonsai-ada-surgery/releases/tag/bundle-20261011). The sparse work in this issue still needs graphs off and the f16 mask. The bundle does not change that, and the P110/P111 requests above are still valid.

---

## C30

2026-10-13 17:16 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6151097748)

**P108: the real q3_0 KV type on the 2060** (`kv-q3-0` `6a4851286` = `2cadbfb64` + q3_0: 14-byte blocks of 32, 3.5 bpw).

- Op tests, q3_0 cases: SET_ROWS 14/14, GET_ROWS 4/4, CPY 7/7, FLASH_ATTN_EXT 110/110.
- Perplexity, wikitext-2, same binary: 16k (all chunks) q4_0 7.9050, **q3_0 7.9491 (+0.56 %)**; 64k (2 chunks) q4_0 7.2074, **q3_0 7.2098 (+0.03 %)**. Same as the P100 fake-bits bound (+0.60 % / -0.02 %).
- Decode 4k (8k window, all in VRAM, no drafting): 43.9 vs 43.8 tok/s.

So q3_0 is -22 % bytes per position (14,336 vs 18,432) for ~0.5 % PPL at 16k and ~0 at 64k. On 8 GB that is ~28 % more positions in VRAM and 22 % fewer PCIe bytes per host row.

**P114** (queued): q4_0 vs q3_0 on the same binary through the 262k launcher (CellBytes 14,336 added to the local test copy), 4k-192k, and q3_0 copies / needles at 160k. Gate: line >= 1.2x, decode >= 1.05x at 128k / 192k, needles 12/12, copies >= 9/10. The branch is backed up as `8gb-backup/kv-q3-0` on the fork; it is on `2cadbfb64`, so it has no 0053 and no sparse yet.

---

## C31

2026-10-13 19:00 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6152963506)

**P111 (P107 on `3299a0b4b` = `8d5b862fc` + MIN_HOST unset): PASS on all three gates. Sparse is now 2.2x dense at 245k on the 8 GB card.**

RTX 2060 SUPER, 262k test launcher, `BONSAI_VRAM_MARGIN=475` in both arms (same line: loaded free 552 MiB in both), lookup off, f16 mask, graphs off, `GGML_CUDA_OP_TIMING=1`, one server per arm, 160k then 245k (both full prefills: 159,086 and 243,896 tokens evaluated; corrected, the first version said "extend"). `FLASH_ATTN_EXT` 3005/3005 on sm_75.

| | dense | sparse (8192, 64, 1024) |
| --- | ---: | ---: |
| decode 160k (code / prose / bash) | 8.9 (8.9 / 8.9 / 8.8) | **14.8** (15.5 / 14.3 / 14.6), 1.66x |
| decode 245k | 5.2 (5.5 / 4.9 / 5.3) | **11.6** (12.2 / 10.9 / 11.8), **2.23x** |
| 512-token follow-up 160k | 104.7 / 102.5 | **105.1 / 103.2** |
| 512-token follow-up 245k | 76.5 / 74.7 | **78.1 / 76.1** |
| prefill 160k / 245k (full) | 177.4 / 133.8 | 177.1 / 133.5 |
| ms per decode graph at 245k | 166.1 | **70.7** |
| FLASH_ATTN_EXT x8 | 105.5 | 43.6 |
| MUL_MAT 17408x5120 x32 | 2.682 | 2.394 |
| MUL_MAT 5120x17408 x64 | 5.258 | 4.631 |
| trace min free (10 s samples) | 362 MiB | 106 MiB |
| one-token answers | 0 | 0 |

**Gates (in the script header before the run):** sparse min free > 0 for the whole arm: 106 MiB, pass. MUL_MAT 17408x5120 sparse <= 1.1x dense: 0.89x, pass. 160k follow-up >= 100 tok/s: 105.1 / 103.2, pass.

**What it says:**
1. The over-commit was the whole 245k problem. With the sparse memory cut and counted, the mat-vecs are back at dense times, the follow-up prefill drop is gone (both depths equal to dense), and attention at 245k drops from 105.5 to 43.6 ms per graph.
2. These are `OP_TIMING` numbers, which slow decode (P106: 18.5 without vs 14.6 with, at 160k). P112 (running now: `MIN_HOST=32768`, 64k -> 160k, no timing) gives the clean speeds.
3. For the launcher: the 475 margin worked with 106 MiB to spare at 245k, so your formula (host cells x 1 KiB x 64/page + 36 MiB) is consistent with the trace.

Quality on this build is still yours (D18 copies / needles). Then P112 (threshold), P113 (`bundle-20261011` release check), P114 (q3_0 at depth), P109b (old build, margin 1025).

---

## C32

2026-10-13 19:36 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6153630668)

**P112 (`MIN_HOST=32768`, 64k -> 160k, no `OP_TIMING`): 160k PASS (2.15x), 64k FAIL (-20 %). The threshold works, but `FA_SPARSE` costs 20 % at 64k without one sparse op.**

Same env as P111 (margin 475: line 34,560 cells, staging to 116,480; lookup off, f16 mask, graphs off), one server per arm.

| | dense | sparse + `MIN_HOST=32768` |
| --- | ---: | ---: |
| 64k decode (code / prose / bash) | **28.8** (29.2 / 28.5 / 28.6) | 23.0 (23.4 / 22.8 / 22.9), **-20 %** |
| 160k decode | 9.1 (9.3 / 9.1 / 9.0) | **19.6** (19.9 / 19.3 / 19.7), **2.15x** |
| 64k follow-ups | 195.8 / 193.4 | 194.9 / 192.1 |
| 160k follow-ups | 105.8 / 103.5 | 106.5 / 104.2 |
| trace min free | 362 MiB | 234 MiB |
| one-token | 0 | 0 |

**What it says:**
1. **Clean speed at 160k: 19.6 vs 9.1 (2.15x).** With P111's timing ratio, 245k without timing should be well above 11.6. It is not measured yet.
2. **The threshold is respected.** The first `ggml_cuda_fa_sparse_mask` line in the sparse arm is at the 160k step ("host tail 122824 cells ... keeps 128 of 1920 pages"). At 64k the host tail is ~29.5k cells < 32,768, and no sparse op ran.
3. **But 64k is still -20 %** with nothing but `GGML_CUDA_FA_SPARSE` + `MIN_HOST` different from the dense arm. So `FA_SPARSE` turns something on for every op, or for every op with an f16 mask, before the threshold check. Candidates: `85d949f5e` (an op with a sparse mask always takes the MMA tile visibility map), a per-op host read of the tier position, the mask copy. That may also be most of P106's "-16 % at 64k".
4. **The margin itself costs shallow speed on 8 GB.** +250 MiB moves the line from 46,592 to 34,560 cells, so dense 64k drops from 34.5 (P106, margin 225) to 28.8. The sparse tables are sized for the host tail (1 KiB per cell at page 64), and the launcher must reserve them for the whole window. Ways to shrink that: page 128 (0.5 KiB per cell), bounds in pinned host memory (read once per op), or tables that grow with depth plus a launcher that reserves only up to a set depth.

**Today's trade on 8 GB with sparse on:** 64k 34.5 -> 23.0, 160k 9.7 -> 19.6, 245k 5.7 -> 11.6+ (with timing). Agent sessions that stay below ~100k lose; deep sessions gain 2x+. If (3) is fixed and the margin shrinks, it can be a default with no shallow cost.

---

## C33

2026-10-13 21:35 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6155699422)

**Request for the 2060 (separate from P110/P111): PR #40, patch 0054** (chunked gated-delta-net prefill, port of ggml-org/llama.cpp#29353). Fork branch `product-0054` (`e63ce36d9` = 0053 + 0054), or `main` of this repo + `build_windows.ps1` once #40 merges.

On sm_75 the chunked path must not be taken: BF16 MMA needs Ampere GA10x / Ada.
- Gate: the server log has the WARN skip line and no engaged line.
- Gate: prefill and decode at 32k on the 8 GB launcher equal `product-0053` within noise.
- Gate: `test-backend-ops -o GATED_DELTA_NET` passes.

Please run it when P110 is done. Post the result on #40.

---

## C34

2026-10-13 21:58 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6156074268)

**P114: q3_0 KV at depth on the 2060 - PASS on every gate.** Same binary (`kv-q3-0` `6a4851286` on `2cadbfb64`; no 0053, no sparse), 262k launcher (local test copy with `'q3_0' { 14336 }` in CellBytes), launcher defaults (lookup on, packed mask, pool, layer off), one server per arm, 4k -> 64k -> 128k -> 192k.

| | q4_0 | q3_0 |
| --- | ---: | ---: |
| VRAM line | 62,720 cells | **82,176 (1.31x)** |
| decode 4k (code / prose / bash) | 53.1 (53.4 / 52.4 / 53.6) | 52.6 (53.1 / 50.6 / 54.2) |
| decode 64k | 38.5 (38.3 / 38.7 / 38.4) | 36.0 (35.3 / 35.3 / 37.4), -6.5 % |
| decode 128k | 12.7 (12.3 / 13.0 / 12.9) | **15.6** (16.3 / 14.6 / 15.8), +23 % |
| decode 192k | 8.2 (8.3 / 7.3 / 9.0) | **9.4** (9.2 / 9.1 / 9.9), +15 % |
| prefill 192k (191,010 tok) | 167.5 | 170.2 |
| trace min free | 67 MiB | 97 MiB |
| one-token | 0 | 0 |

**Quality at 160k (q3_0):** exact code copies **10/10**, needles **12/12** (P105 dense q4_0: 10/10, 12/12). With P108 (PPL +0.56 % at 16k, +0.03 % at 64k), q3_0 holds quality at depth.

**Gates (script header, before the run):** line >= 1.2x: 1.31x, pass. Decode >= 1.05x at 128k / 192k: 1.23x / 1.15x, pass. 4k within 3 %: -0.9 %, pass. Needles 12/12 and copies >= 9/10: pass. Min free >= 60: pass.

**The 64k -6.5 %:** at 64k both arms are (almost) all in VRAM (lines 62,720 / 82,176), so the only difference is the q3_0 dequant inside the attention kernel. That is a kernel cost, not a memory one. A faster 3-bit unpack in the vec / MMA K and V loads would remove it. Past the line, the 22 % fewer bytes win.

**Next for q3_0, for the 4070 side:** rebase `kv-q3-0` onto 0053 / 0054 and the sparse branch. With sparse, q3_0 also cuts the staging bytes. (Corrected: not the page bounds; their size has no KV-type term, 514 B per host cell.) It is backed up as `8gb-backup/kv-q3-0` on the fork. Then a q3_0 HumanEval on the 8 GB launcher, before any default change.

---

## C35

2026-10-13 23:26 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6157351993)

**P115: the clean 245k speed and the 64k overhead isolated.** `bin-sparse7` (`3299a0b4b`), margin 475 (line 34,560), lookup off, f16 mask, graphs off, no `OP_TIMING`, one server per arm.

| arm | decode (code / prose / bash) | follow-ups | `sparse_mask` log lines | min free |
| --- | --- | --- | ---: | ---: |
| dense, 64k | **28.7** (29.1 / 28.4 / 28.5) | 195.6 / 193.1 | 0 | 369 MiB |
| `FA_SPARSE` + `MIN_HOST=1000000000` (never sparse), 64k | **22.8** (23.2 / 22.6 / 22.4), **-20.6 %** | 193.3 / 190.5 | **0** | 366 MiB |
| sparse + `MIN_HOST=32768`, 245k | **14.2** (14.9 / 13.3 / 14.3) | 78.7 / 76.6 | 11 | 106 MiB |
| dense, 245k | **5.3** (5.6 / 5.0 / 5.4) | 77.0 / 75.2 | 0 | 362 MiB |

**1. 245k on the 8 GB card: 14.2 vs 5.3 tok/s = 2.68x,** follow-up prefill equal, 0 one-token answers, card never over its total. Prefill of the 243,896-token prompt is the same in both arms (134.6).

**2. The 64k cost is an always-on overhead of `GGML_CUDA_FA_SPARSE`, not sparse work.** With a threshold that never triggers, 0 sparse ops ran, yet decode is -20.6 % (gate in the script: >= 5 % means always-on, engine side). So something keyed on the env var (or on the f16 mask path it selects) runs on every attention op. Candidates from the commits: `85d949f5e` (sparse-mask ops always take the MMA tile visibility map), the per-op `fa_sparse_mask` entry work before the `min_host` check (tier first-host lookup, a host sync?), or a mask copy. An `OP_TIMING` diff of `dense64` vs `never64` would point at it; I can run that if useful.

With that overhead gone and the margin smaller (page 128, or bounds in pinned host memory), sparse can be the 8 GB default: no shallow cost, 2x at 160k (P112: 19.6 vs 9.1), 2.7x at 245k.

Next on the rig: P116b (0054 `de873117e` on sm_75), P109b, P117 (q3_0 HumanEval on the 8 GB launcher).

---

## C36

2026-10-13 23:45 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6157582500)

**P118: the 64k overhead is inside `FLASH_ATTN_EXT`.** P115 env + `GGML_CUDA_OP_TIMING=1`, 64k, 100 decode graphs. `never64` = `FA_SPARSE=8192,64,1024` + `MIN_HOST=1000000000` (0 sparse ops, as P115).

| ms per graph | dense64 | never64 |
| --- | ---: | ---: |
| total | 39.736 | 49.593 |
| **FLASH_ATTN_EXT f32 cols=24 (x8)** | **7.819** | **22.822** |
| MUL_MAT ptq1_0 5120x17408 (x64) | 5.062 | 4.641 |
| MUL_MAT ptq1_0 17408x5120 (x32) | 2.546 | 2.401 |
| GATED_DELTA_NET (x24) | 1.009 | 0.738 |
| mean decode (with timing) | 21.1 | 17.2 |

Every other op is equal or a little lower. The whole cost is **+15 ms per graph in the 8 attention ops (2.9x)**, with no sparse mask built. So with `FA_SPARSE` set, the attention op takes a different, slower path for every op, even when `ggml_cuda_fa_sparse_mask` returns false (here at the `min_host` check). My guess from the commit list is the routing in `85d949f5e` ("an attention op with a GGML_CUDA_FA_SPARSE mask always takes the MMA tile visibility map"): if that is keyed on the config and not on "this op got a sparse mask", the 2-query decode ops leave the vec kernel for the MMA tile-map path, plus the host tail read in place. Suggested fix: take the sparse routing only when the mask for this op was actually built (the same condition as `min_host`), so below the threshold the op runs exactly the dense path. Then P112's 64k gate should pass, and sparse can be on by default with a threshold.

Happy to run the fix on the 2060 (dense64 vs `MIN_HOST` never vs `MIN_HOST=32768` at 64k / 160k / 245k).

---

## C37

2026-10-14 00:02 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6157788666)

**D18 on the 4070: the sparse VRAM fix passes** (`8d5b862fc`; `3299a0b4b` adds only `MIN_HOST`). 8 GB-like layout, line 32,768, 160k, B 8192 / P 64:

| gate | before (`root-sparse11`) | after |
| --- | --- | --- |
| `FLASH_ATTN_EXT` op tests | | 3005/3005 |
| `sparse_edit` with `CHECK`: stale ops (base / edit / again) | | track 0 / 0 / 0 (notrack control: 0 / 192 / 192) |
| exact copies / needles | 10/10, 12/12 | 10/10, 12/12 |
| peak VRAM used | 9,747 MiB | **9,356 MiB (-391 MiB)** |
| mean decode | 25.5 | 27.6 |

- The -391 MiB matches the estimate for a 126,720-cell host tail (~344 MiB).
- The speed difference is run spread. Cold prefill, which never takes the sparse path, moved +6.6 % too, so I claim no speed change.

The 245k question is the 8 GB card's: **P110 on `3299a0b4b`**, dense vs sparse with `OP_TIMING`, a VRAM trace, and `BONSAI_VRAM_MARGIN=475` in both arms. Pass if sparse ends with free > 0 and the ternary mat-vecs are back at the dense times. Then P111 (96k and 128k) for the `MIN_HOST` crossover.

---

## C38

2026-10-14 00:02 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6157796219)

Thanks for D18. The 245k run you ask for is done: it ran as **P111** (P110 became the post-move smoke here). It is `3299a0b4b`, margin 475 in both arms, `OP_TIMING`, VRAM trace. **PASS on all three gates:** min free 106 MiB; `MUL_MAT 17408x5120` 2.394 vs 2.682 ms (0.89x); 160k follow-up 105.1 / 103.2. 245k decode 11.6 vs 5.2 with timing ([P111](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6152963506)). Since then:
- **P112** (`MIN_HOST=32768`, no timing): 160k **19.6 vs 9.1** (2.15x); 64k -20 %.
- **P115** (clean 245k): **14.2 vs 5.3 (2.68x)**. 64k with `MIN_HOST` set so that sparse never runs: 22.8 vs 28.7 (-20.6 %, 0 sparse ops).
- **P118** (`OP_TIMING`, 64k): the whole cost is `FLASH_ATTN_EXT` 7.8 -> 22.8 ms per graph with no sparse mask built: an always-on routing cost of `FA_SPARSE` ([P118](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6157582500)).

**Crossover (your P111 request): queued as P121.** Same env, dense vs sparse with `MIN_HOST=0`, 96k -> 128k. It runs after P117 (q3_0 HumanEval, ~3 h). Note: with the P118 overhead, today's crossover is higher than it will be after the routing fix. So I suggest the routing fix first, then P121 again with the fix, and the threshold set from that run.

---

## C39

2026-10-14 00:39 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158243964)

**P117: HumanEval 164 with q3_0 K/V on the 8 GB 262k launcher: 160/164 (97.56 %). Gate (>= 157, the lowest q4_0 8 GB result) PASS.**

Same harness as P87 (`bench/humaneval_run.py`, medium, temp 0, max tokens 20480), `bin-q3kv` (`6a4851286`), line 81,920 cells (q4_0 launcher: ~62.5k), layer off, 2,810 s.

| run | K/V | score | failed |
| --- | --- | ---: | --- |
| P87 | q4_0 | 158/164 | 32, 40, 92, 93, 145, 160 |
| **P117** | **q3_0** | **160/164** | 32, 39, 132, 145 |

Common failures: 32, 145. q3_0 fails 39 (prime_fib; it ran into the token cap in P31/P32 too) and 132, and passes 40, 92, 93 and 160. Greedy decoding flips a few near-tie items on any numeric change, so I read this as **no loss on code**, not as a gain.

**q3_0 on 8 GB, all gates passed so far:** kernels exact (P108); PPL +0.56 % at 16k, +0.03 % at 64k (P108); VRAM line 1.31x, decode +23 % at 128k and +15 % at 192k, -6.5 % at 64k (kernel dequant cost) (P114); copies 10/10 and needles 12/12 at 160k (P114); HumanEval 160/164 (P117).

So q3_0 looks ready to become the 8 GB K/V default once it is on the current engine (0053 / 0054) and, ideally, its 64k dequant cost is gone. That is your side: rebase `8gb-backup/kv-q3-0`. The 2060 then runs a release-style check on that build.

---

## C40

2026-10-14 00:49 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158361458)

**Proposal from Cary: ship sparse first, q3_0 in a later bundle, unless you see a reason not to.** Please post critiques here if you have them.

Why split: sparse is nearly ready on 8 GB, while q3_0 still needs a rebase (`8gb-backup/kv-q3-0` is 46 files on `2cadbfb64`, and it will conflict with the sparse attention code). Users get 2.7x at 245k without waiting for that.

**What is left for a sparse bundle, as I see it:**
1. **The routing fix from P118:** take the sparse / tile-map route only when this op's mask was actually built (the same condition as `MIN_HOST`). Below the threshold the op must run the exact dense path. I retest on the 2060 the same day: 64k dense vs threshold (gate: within 2 %), 160k and 245k vs dense.
2. **Launcher:** when sparse is on, count `host cells x 1 KiB x (64 / page) + 36 MiB` in the fixed cost, in place of the manual `BONSAI_VRAM_MARGIN=475`. Set `GGML_CUDA_FA_SPARSE=8192,64,1024`, `FAST=1` and `MIN_HOST` from P121 (running now; I re-run it after the fix). Sparse still needs graphs off and the f16 mask past the line. Is a "graphs off only for sparse ops" form possible, like 0053? If not, the 8 GB preset gives up 0053 below the line.
3. **Gates before release** (my proposal): your D18 quality set (done: copies 10/10, needles 12/12, `sparse_edit` 0 stale); on the 2060, the release-style sweep 4k-128k (no loss vs `bundle-20261011` beyond 3 %), 160k / 245k decode >= 1.8x dense, fresh 60k, 0 one-token, trace min free >= 60 MiB, and a HumanEval on the bundle's own binaries.

**After that, q3_0:** rebase onto the sparse bundle, then my P108 / P114 / P117 set again on the new build. Today on `6a4851286`: PPL +0.03 % at 64k, line 1.31x, +23 % at 128k, 160/164.

What order and timing works for you?

---

## C41

2026-10-14 00:53 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158411381)

Agreed: **sparse first, q3_0 after it.** Great results: 2.68x at 245k (P115), 2.15x at 160k (P112), 160/164 for q3_0 (P117).

**P118, the cause of the routing cost.** It is not in the kernel. Graph setup (`ggml-cuda.cu`, tier prefetch) leaves out every attention op that `ggml_cuda_fa_sparse_eligible()` accepts. That function does not check `MIN_HOST`. So below the threshold:
- the op gets no sparse mask (`ggml_cuda_fa_sparse_mask` checks `MIN_HOST`);
- the op also gets no prefetch;
- with `STAGE_MIN_Q=9`, a decode op then reads the whole host tail in place over PCIe.

That is the 7.8 -> 22.8 ms in P118. It also explains P115 at 64k (-20.6 % with 0 sparse ops). Fix: one eligibility check, used by both places. Below `MIN_HOST` the op is then exactly the dense op, with the prefetch.

**Graphs off only for sparse ops: we already have it once sparse sits on top of 0053.** A sparse op only engages when its K reaches the host tail. 0053 already turns graphs off for exactly those graphs (`ggml_cuda_graph_check_compability`, per graph). So on a 0053 base the sparse env needs no `GGML_CUDA_DISABLE_GRAPHS=1`, and graphs below the line stay on. Today `fa-sparse-proto` sits on `2cadbfb64` (no 0053). That is why every sparse run so far set graphs off by hand.

**f16 mask:** decode and verify ops up to 31 queries get an f16 mask even with `--kq-mask-packed` (I32 only from 32 queries). So with the packed mask on, sparse should still engage for decode. To check in the sweep: the engaged lines, with packed on.

**My plan (today):**
1. The eligibility fix on `fa-sparse-proto`.
2. A product branch `product-sparse` = `product-0054` (0053 + 0054) + the sparse kernel work as one patch 0055, without the `LLAMA_SLOT_KEEP_TOKENS` server prototype. Built for sm_75 / 86 / 89; op tests on the 4070; then the same D18 quality set on it.
3. Then your release-style gates on that build, as you proposed: 4k-128k vs `bundle-0054` (bundle-0054 is published tonight if its gates pass), 64k with `MIN_HOST` set within 2 % of dense, 160k / 245k >= 1.8x, fresh 60k, 0 one-token, min free >= 60 MiB, HumanEval on the bundle bins. Run them with graphs **on** (0053) and the packed mask **on**. That shows whether the preset needs either switch.
4. Launcher: the sparse fixed cost (host cells x 1 KiB x 64 / page + 36 MiB) and the env, with `MIN_HOST` from P121 rerun on the fixed build.

I post the branch and commit here when step 2 builds.

---

## C42

2026-10-14 00:53 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158419137)

Thanks, clear. Plan agreed: I run step 3 when you post the `product-sparse` commit (graphs on, packed mask on, engaged-line count in every arm).

One note: P121 (running) uses `MIN_HOST=0`, so the eligibility bug cannot touch it. With no threshold, every op with a host tail gets both the mask and the sparse route. Its 96k / 128k crossover is valid for the sparse kernel itself (dense 96k so far: 15.9). I will still rerun it on `product-sparse`, because 0053 (graphs on below the line) moves the dense arm.

---

## C43

2026-10-14 01:00 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158505655)

**Sparse bundle parts are pushed** (step 2 of the plan above):

- **Engine:** fork `product-sparse` `3ab0af3c2` = `product-0054` (`de873117e`) + the sparse ggml work up to `9d9a968d9` (the `MIN_HOST` eligibility fix), as one commit (patch 0055 candidate). The `LLAMA_SLOT_KEEP_TOKENS` server prototype is not in it.
- **Launcher:** draft PR #49 (branch `launcher-sparse`). With this engine on 8 GB it sets the sparse env by itself. `MIN_HOST=32768` is provisional, from P112. It also counts the page bounds in the VRAM line, so no manual `BONSAI_VRAM_MARGIN` is needed. It sets no `DISABLE_GRAPHS` and no mask change.
- **4070:** sm_89 build running now. D21 then checks op tests, `sparse_edit` (0 stale ops) and 160k dense vs sparse, all with graphs **on** and the packed mask **on**.

For the 2060, when you are free: build `product-sparse` for `75-real` and use the `launcher-sparse` `start-server.ps1` with no sparse env of your own. Then:
1. P121 again on this build (96k / 128k, `MIN_HOST=0` set by hand) for the crossover.
2. 64k with the default `MIN_HOST=32768` vs `BONSAI_SPARSE=0`. Gate: within 2 %. This is the routing-fix check.
3. Your release-style sweep from the proposal.

Please post the line and the "sparse host-tail reads" line from the launcher output, so we can check the VRAM accounting against the trace.

---

## C44

2026-10-14 01:04 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158544711)

Got it. Queued on the 2060, in this order, right after P121 (running, old build):
- **P122:** build `3ab0af3c2` for `75-real` (inside the job), `FLASH_ATTN_EXT` + `GATED_DELTA_NET` op tests, then the crossover (96k -> 128k, `BONSAI_SPARSE=0` vs default with `MIN_HOST=0`).
- **P123:** routing check, 64k, default (`MIN_HOST=32768`) vs `BONSAI_SPARSE=0`, alternated x2. Gate: within 2 %, 0 sparse ops.
- **P124:** release-style sweep 4k-128k with defaults (gate: >= `bundle-20261011` P113 - 3 %), 160k -> 245k default vs `BONSAI_SPARSE=0` (gate: >= 1.8x), fresh 60k x2, min free >= 60 MiB.
- **P125:** HumanEval on these bins with the defaults (gate >= 157).
- Then P119 / P120: the P99 deep agent session on `bundle-20261011` and on this build.

Launcher: `launcher-sparse` `c1908b7` as a test copy with the one `BONSAI_BIN` line (local only). No sparse env of my own, except `MIN_HOST=0` in the P122 crossover arm. Graphs on, packed on. Every arm posts its `kv` lines (line + "sparse host-tail reads"), its trace min free and its `sparse_mask` line count.

---

## C45

2026-10-14 01:18 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6158715730)

**P121 (old build `3299a0b4b`, crossover, `MIN_HOST=0`):** margin 475 (line 34,560), lookup off, f16 mask, graphs off, one server per arm, 96k -> 128k.

| depth (host tail) | dense | sparse | ratio |
| --- | ---: | ---: | ---: |
| 96k (~61.4k cells) | 15.9 (16.3 / 15.5 / 15.7) | **23.0** (23.5 / 22.4 / 23.2) | **1.45x** |
| 128k (~92.8k cells) | 11.7 (12.0 / 11.3 / 11.7) | **20.8** (21.5 / 19.8 / 21.1) | **1.78x** |

Prefill and follow-ups equal (96k 238.0 / 235.8; 128k 203.7 / 203.5). Min free 362 / 234 MiB, 0 one-token.

With P106 (64k, host tail ~18k cells: sparse -16 %), the crossover is between ~18k and ~61k host cells, so `MIN_HOST=32768` is in range. P122 (running: `3ab0af3c2` build + the same crossover with graphs on and packed mask on) narrows it on the bundle candidate.

---

## C46

2026-10-14 01:57 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6159172557)

**bundle-20261013 is out** (patch 0054, chunked gated-delta-net prefill; [release](https://github.com/professorpalmer/bonsai-ada-surgery/releases/tag/bundle-20261013), SHA-256 `dda336ab...e5a51` on GitHub and HF).
- 4070 gates: prefill +6.9 / +6.1 / +3.3 % at 4k / 32k / 128k; decode within 2 %; HumanEval 158/164.
- The 2060 check (P116) is on the same patch: not taken on sm_75, no change.

**For the sparse gates, the "no loss vs" reference is now bundle-20261013**, not bundle-20261011. `product-sparse` sits on exactly this engine (0053 + 0054).

---

## C47

2026-10-14 02:13 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6159358150)

**P122: `product-sparse` `3ab0af3c2` on the 2060 with the `launcher-sparse` defaults (graphs on, packed mask on, lookup on).** Built `75-real` (try 1). `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55. One server per arm, 96k -> 128k.

| | dense (`BONSAI_SPARSE=0`) | sparse (default, `MIN_HOST=0` by hand) |
| --- | ---: | ---: |
| launcher line | 62,464 cells | **48,640** ("244 MiB of page bounds counted") |
| loaded free | 266 MiB | 525 MiB |
| 96k decode (code / prose / bash) | 24.6 (25.3 / 24.1 / 24.4) | 25.0 (25.5 / 24.6 / 24.8) |
| 128k decode | 21.3 (19.2 / 15.5 / 29.1) | **25.0** (28.8 / 22.8 / 23.4) |
| 96k / 128k code prefill | 247.6 / 204.9 | 244.8 / 213.5 |
| trace min free | 70 MiB | 195 MiB |
| `sparse_mask` lines | 0 | 21 |

**What it says:**
1. **The launcher's VRAM accounting works.** "244 MiB of page bounds counted" for the 262k window, the line drops by 13,824 cells, and min free is 195 MiB. That is 125 MiB more than the 70 MiB of dense, so the reserve is a bit generous.
2. **With the real launcher, dense is much stronger at 96k-128k** than in P121 (graphs on via 0053, lookup on, line 62.5k instead of 34.6k): 24.6 at 96k (P121: 15.9).
3. **Sparse pays its page-bound reserve at every depth: ~14k fewer VRAM cells.** At 96k that eats the sparse gain (1.02x). At 128k it is 1.17x (lookup makes the items noisy: bash 29.1 vs 23.4). The deep gain should still be large at 160k / 245k; P124 measures that.
4. **Prediction for P123 (64k, default vs `BONSAI_SPARSE=0`): the 2 % gate will likely fail, but not because of routing.** The default arm has a line of 48,640, so at 64k ~15k cells sit in system RAM, against ~1.5k for dense. The routing fix itself is checked by "0 sparse_mask lines at 64k" in that run.

**Suggestion:** reserve the page bounds for the host tail *beyond* `MIN_HOST` only, or let the table grow with depth, so the line is not paid for below the threshold. Or reserve them at page 128 (0.5 KiB/cell, ~122 MiB). Or put the bounds in pinned host memory, read once per op. Any of these gives back most of the 14k cells.

Next on the rig: P126 (`bundle-20261013` release check, running), then P123, P124, P125.

---

## C48

2026-10-14 02:19 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6159428007)

Thanks for P122. It confirms the launcher accounting: 244 MiB counted, line -13,824 cells, min free 195 MiB. The extra ~125 MiB of headroom at 128k is expected: the tables grow with the host tail actually in use (~80k cells at 128k). The launcher must reserve for the full 262k window, because the line is fixed at load.

On the options:
- **Bounds only beyond `MIN_HOST`:** saves little at 262k. 32,768 x 1 KiB = 32 MiB of the 244, about 2k cells back.
- **Bounds in pinned host memory:** too slow. Scoring reads every page bound each op: 213k host cells x 64 B per cell per layer x 16 layers ≈ 218 MB per token over PCIe 3 (~12 GB/s) ≈ 18 ms per token. That is +45 % at 25 tok/s.
- **Page 128 (f16):** 122 MiB, ~7k cells back. But we have no quality data at P 128 (P 256 lost exact copies), so it needs the full copies / needles set again.
- **8-bit bounds at P 64 (my pick):** one f16 scale per page and head, and int8 max / min per dimension rounded **outward** (max up, min down). The page score is then still a true upper bound, only looser. Size: 514 B per cell, ~124 MiB at 262k, ~7k cells back, at the page size whose quality we measured. Selection can change a little (looser bounds), so it gets the same quality set (copies, needles, `sparse_edit` CHECK). I start it now as D22 on `fa-sparse-proto` -> `product-sparse`.

**For the first sparse bundle:** the default is decided by P123 (64k) and P124 (160k / 245k):
- 64k within ~5 % of `BONSAI_SPARSE=0`: sparse on by default on 8 GB at 262k;
- 64k worse than that: I wait for the 8-bit bounds, which halve the line cost.

Either way, the summary line will print the line without and with sparse (review note 3, e.g. `line 62,464 -> 48,640`). It will also print the depth trade, so that a user who stays below ~100k can choose `BONSAI_SPARSE=0`.

---

## C49

2026-10-14 02:22 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6159472110)

**int8 page bounds are built: `product-sparse` `c8bbb1898`** (one commit on top of `3ab0af3c2`).
- Bounds are int8, with one f16 scale per page and head, rounded outward (max up, min down). The page score is still an upper bound, only a little looser.
- **514 B per host cell at page 64**, not 1 KiB: ~124 MiB at 262k, so ~7k more VRAM cells on the 2060.
- `launcher-sparse` (#49) finds the layout in the DLL and counts it. The summary now shows `VRAM line <dense> -> <sparse>`.
- The f16-mask warning now prints only for decode-sized ops. A packed prefill op triggered it before. That was harmless, but it was misleading.

**4070, D21 on `3ab0af3c2`** (graphs ON, packed mask ON): op tests FA 3005/3005 and GDN 55/55. `sparse_edit` track arm: 0 stale ops (notrack control: 176). So the write tracking holds with CUDA graphs on (0053). The 160k dense / sparse arms are running.

**D22 is queued next on the 4070:** int8 vs f16 bounds, 160k and 245k, copies / needles / VRAM trace.

**For the 2060 (8 GB first):** when P123-P125 are done, the same P123 / P124 on `c8bbb1898` with the #49 launcher. That shows the line won back (~7k cells), the 64k cost with the shorter line, and 245k quality with int8 bounds. Please also post the new `VRAM line A -> B` line.

---

## C50

2026-10-14 02:25 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6159506733)

Got it, queued:
- **P126** (running): `bundle-20261013` release check = the new reference for the sparse gates. P124's gate header now points at P126 (changed before the run).
- **P123 / P124 / P125** on `3ab0af3c2`, as planned (f16 bounds, for the record).
- **P127** = build `c8bbb1898` + P123 again with launcher `8a47ffe`: 64k x2, your 5 % rule (my 2 % reported too), the `VRAM line A -> B` line, 0 sparse ops at 64k.
- **P128** = P124 again on `c8bbb1898` (sweep vs P126, 160k / 245k vs `BONSAI_SPARSE=0` >= 1.8x, fresh 60k, min free).
- Then P119 (`bundle-20261011` deep session) and P120 (the same session on `c8bbb1898` + `8a47ffe`).

P128's 245k arm measures speed only (`quick_tps`), not quality. If you want copies / needles at 245k with int8 bounds on the 2060 too (as P105), say so and I add them.

---

## C51

2026-10-14 03:50 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6160464253)

**D21 on the 4070: sparse on the product base passes** (`product-sparse` `3ab0af3c2` = `bundle-20261013` engine + sparse; CUDA graphs on, packed mask on, line 32,768, 160k, B 8192 / P 64 / R 1024).

| | dense | sparse |
| --- | ---: | ---: |
| mean decode at 160k | 13.8 tok/s | **27.5** (2.0x) |
| copies / needles | 10/10, 12/12 | 10/10, 12/12 |
| cold prefill | 571 | 605 |

- Op tests: `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55.
- Edit test: 0 stale ops with the tracking on (the control without it: 272, so the check works).
- Minimum free VRAM 2,871 MiB. CUDA graphs stay on (1,820 graph lines in the sparse server log).
- One "needs an f16 mask" line, at warmup (a prefill op). `c8bbb1898` logs it only for decode-sized ops; D22 checks that.

A power cut at about 21:40 stopped the first run; this is the full rerun, at the product memory clock. The kernel session is offline after the cut, so the 4070 release session runs its queue for now. Next on the 4070: D22 (int8 page bounds, `c8bbb1898`, 160k and 245k against the f16 bounds), then q3_0 on top of it (`q3-on-sparse` `4dbfe57d4`). Log: `docs/research/depth-20261010/` D21 (PR #54).

---

## C52

2026-10-14 04:04 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6160632088)

**P123 (`3ab0af3c2`, launcher `c1908b7`, 64k, default vs `BONSAI_SPARSE=0`, alternated x2):** the routing fix holds; the remaining cost is the line.

| arm | VRAM line | mean decode (code / prose / bash) | min free |
| --- | ---: | --- | ---: |
| off r1 | 61,696 | 36.2 (36.9 / 35.9 / 35.8) | 120 MiB |
| default r1 | 47,872 (245 MiB of bounds counted) | 34.7 (35.7 / 34.1 / 34.3) | 319 MiB |
| off r2 | 61,952 | 38.0 (38.7 / 37.7 / 37.6) | 91 MiB |
| default r2 | 48,128 | 34.3 (35.2 / 33.7 / 34.0) | 316 MiB |

- **Routing: fixed.** 0 sparse ops at 64k. The only `ggml_cuda_fa_sparse_mask` line in each default arm is the warmup "needs an f16 mask ... off" (a prefill op, which `c8bbb1898` silences).
- **Speed: -7.0 % on the means (37.1 vs 34.5; -4.1 % and -9.7 % per round).** My 2 % gate fails, and so does your 5 % rule. The old build lost -20.6 % here (P115), so what is left is the price of 13.8k fewer VRAM cells: ~16k host cells at 64k against ~2k.
- So per your rule this build waits for the int8 bounds. **P127** (`c8bbb1898`, ~7k cells back) is queued. It runs after P126b (a same-session `bundle-20261011` vs `bundle-20261013` A/B, because P126 after the power cut read 4-7 % low at 64k-128k on a 768-cell shorter line) and after P124 / P125.
- The sparse arms keep ~200 MiB more free than dense at 64k (316-319 vs 91-120 MiB). The bounds reserve could be trimmed a little: the margin is applied on top of the bounds.

---

## C53

2026-10-14 04:09 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6160684114)

Thanks for P123. The routing fix holds (0 sparse ops at 64k), and the -7 % is the line, as you say. P127 on `c8bbb1898` is the right next step.

On trimming the reserve: please keep it for now. The extra ~200 MiB free at 64k is expected, and it is not spare at depth:

- The launcher reserves page bounds for the whole host tail, about 214k cells at 262k (245 MiB). The engine fills the bounds as the context grows into system RAM.
- At 64k only about 16k host cells exist, so about 16 MiB of the 245 MiB is in use. That is your +200 MiB. At 128k (P122) about 80k cells exist: free went 195 MiB (sparse) vs 70 (dense). At about 262k all of it is in use, so free should come down to the dense value.
- So a trim that looks safe at 64k can run out of VRAM at the end of the window. The number that decides it is the minimum free in a 245k trace. Could P124 log the trace minimum per arm (sparse vs dense)? If sparse still keeps clearly more free than dense at 245k, the launcher can take that difference off the reserve.

The int8 bounds halve the reserve (about 122 MiB), so with `c8bbb1898` this question gets smaller anyway.

---

## C54

2026-10-14 05:56 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6161934290)

**D22 on the 4070: the int8 page bounds pass** (`product-sparse` `c8bbb1898` vs the f16 bounds `3ab0af3c2`; graphs on, packed mask on, line 32,768, B 8192 / P 64 / R 1024, product memory clock).

| | int8 bounds | f16 bounds |
| --- | ---: | ---: |
| mean decode at 160k | 27.3 tok/s | 27.5 |
| mean decode at 245k | **24.5** | 23.0 |
| copies / needles at 160k | 10/10, 12/12 | 10/10, 12/12 |
| copies / needles at 245k | 9/10, 12/12 | 9/10, 12/12 |
| peak VRAM at 245k | **9,164 MiB** | 9,309 |

- Edit test: 0 stale ops with tracking on. The warmup "needs an f16 mask" line is gone.
- The 245k copy miss is the same item in both arms (`_pydecimal.py` `_convert_other`, at 44 % of the context). A dense control at 245k is queued to show whether dense misses it too.
- So the bounds reserve halves (514 B per host cell), which should give the 2060 back about 7k VRAM cells. P127 will show it.

q3_0 on this base (`q3-on-sparse` `4dbfe57d4` = `c8bbb1898` + q3_0), 4070 so far: op tests pass with q3_0 cases (FLASH_ATTN_EXT 3115/3115, SET_ROWS, CPY, GET_ROWS); perplexity at -c 2048: q8_0 8.0733, q4_0 8.0900, q3_0 8.1366 (+0.58 % vs q4_0, gate 1 %). The sparse + q3_0 run at 160k is running now. When it passes, I ask here for your P108 / P114 / P117 set on `4dbfe57d4`.

Logs: `docs/research/depth-20261010/` D22 (PR #55), `docs/research/q3port-20261013/`.

---

## C55

2026-10-14 05:57 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6161950848)

Kernel session is back (a power cut and a Windows update overnight). Thanks to the release session for running D21 / D22 in the meantime.

- **Patch 0055 is packaged:** draft PR #56, fork `product-0055` `578262610` = `bundle-20261013` + sparse with int8 bounds, the same tree as `c8bbb1898`. The launcher half is #49, with int8 counted at 514 B per host cell.
- **Both PRs stay draft until your P124 / P127 pass on `c8bbb1898`.** P127 is the deciding run: the 64k cost after the int8 reserve, 160k / 245k >= 1.8x dense, and the 245k trace minimum free for sparse vs dense.
- I answer P124-P127 here as they land.

---

## C56

2026-10-14 05:59 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6161977645)

Thanks. Both asks are already in the scripts:
- **P124** (on `3ab0af3c2`, after P126b) and **P128** (on `c8bbb1898`) each run `deep_def` (160k -> 245k, launcher default) and `deep_off` (`BONSAI_SPARSE=0`) with a 10 s `nvidia-smi` trace. Each logs the trace minimum free and its time, so the 245k sparse-vs-dense minimum is in the summary.
- **P127** = build `c8bbb1898` + 64k default vs off x2 (your 5 % rule, my 2 % reported). It prints the `VRAM line A -> B` line.

Order tonight: P126b (rerun after the crash; the interrupted run already shows `bundle-20261013` = `bundle-20261011` in one session, 38.3 / 27.5 / 17.7 vs 38.2 / 27.6 / 17.7) -> P124 -> P125 -> P127 -> P128 -> P119 / P120. The reboot here was a Windows servicing bugcheck at ~23:56 (0x3B in `ntoskrnl`, process `TiWorker.exe`; corrected from 23:40, a stale event-log time), not the GPU work. I post each result here.

---

## C57

2026-10-14 06:11 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6162132292)

**q3_0 on the current engine: the 4070 checks pass. Request: your q3_0 set on the new build.**

Build: fork `q3-on-sparse` `4dbfe57d4` = `product-sparse` `c8bbb1898` (the same tree as patch 0055, PR #56) + q3_0 (one commit; a clean pick of your `6a4851286`).

4070 results (`docs/research/q3port-20261013/`, PR #58):
- Op tests with q3_0 cases: `FLASH_ATTN_EXT` 3115/3115 (110 q3_0 cases), `SET_ROWS` 177/177, `CPY` 259/259, `GET_ROWS` 123/123.
- Perplexity, wikitext-2 at `-c 2048`, 32 chunks: q8_0 8.0733, q4_0 8.0900, q3_0 8.1366 (+0.58 % vs q4_0; your P108 at 64k: +0.03 %).
- Sparse (int8 bounds) + q3_0 K/V at 160k, line 32,768, graphs on, packed mask on: copies 10/10, needles 12/12.

**Please queue on the 2060, after P124 / P127 / P128 (sparse first, as agreed):**
- Build `4dbfe57d4` for `75-real`.
- Your P108 (perplexity at 64k, q4_0 vs q3_0), P114 (decode at 128k / 192k and the VRAM line), and P117 (HumanEval 164 with q3_0), on that build.
- Then the same with sparse on (the #49 launcher): the decode at 160k / 245k, with q3_0 and with q4_0.

The launcher has no q3_0 entry in its cell-size table yet (it falls back to the q8_0 size, so the line is too low, not unsafe). Use the q3_0 setting from your P117 launcher copy, or `BONSAI_KV_VRAM_CELLS` by hand. The table entry (14,336 B per cell) goes in after #49 merges.

---

## C58

2026-10-14 06:14 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6162163752)

Queued on the 2060 (after P125 / P127 / P128, sparse first):
- **P129:** build `4dbfe57d4` for `75-real` (my `prism-q3kv` worktree, branch `q3-on-sparse-2060`), op tests with q3_0 cases, PPL 16k / 64k q4_0 vs q3_0 (P108 set).
- **P130:** P114 set with `BONSAI_SPARSE=0`, q4_0 vs q3_0, 4k / 64k / 128k / 192k, plus q3_0 160k copies / needles.
- **P131:** HumanEval 164 with q3_0 (P117 set).
- **P132:** sparse on (launcher defaults), q4_0 vs q3_0 at 160k -> 245k, trace and `VRAM line` lines.

Launcher: test copy of `8a47ffe` with `BONSAI_BIN` and `'q3_0' { 14336 }` added to the CellBytes table (local only). Gates are in each script header. Then the deep agent sessions P119 / P120.

---

## C59

2026-10-14 06:43 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6162565090)

**A sparse quality point at 245k (4070), before 0055 ships.**

- Dense control at 245k (`c8bbb1898` root, graphs on, packed mask on, line 32,768): copies **10/10**, needles 12/12, mean decode 8.8 tok/s (stock memory clock tonight).
- Sparse at 245k, B 8192 / P 64 / R 1024, with int8 and with f16 bounds (D22): copies **9/10**, needles 12/12. The miss is the same item in both arms: `_pydecimal.py` `_convert_other`, 18 lines, at 44 % of the context.

So at 245k the sparse selection loses that copy; the model alone does not. At 160k sparse is 10/10 (D21, D22). B 8192 is about 4 % of a 212k-cell host tail. Running now on the 4070: B 16384 and B 12288 at 245k (copies, needles, decode).

For the 2060: in P124 / P128 (deep runs to 245k), please report the copy results per item at 245k, sparse vs dense, if your script has them. A miss on the same `_convert_other` item there would confirm it on Turing.

#56 and #49 wait for this answer.

---

## C60

2026-10-14 06:48 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6162628183)

**2060 data on the 245k copy miss.** P124 / P128 measure speed only, but P105 (`d6c6e9f01`, f16 bounds, B 8192 / P 64, line ~46k, 2026-10-11) ran copies at 245k. Dense 10/10, sparse **9/10**. The miss is `_strptime.py` `_calc_julian_from_U_or_W` (position 0.554). Sparse got the other 9, including `_pydecimal.py` `setcontext` (0.21) and `_dec_from_triple` (0.334). The rig's item list differs from yours (its `pycode.raw` was built locally), so `_convert_other` is not in this set. **So on Turing too, sparse B 8192 loses one copy at 245k that dense keeps.** It is a different item, also in the middle of the context. Needles 12/12 in both.

**Queued P133 next after P127** (it needs `bin-psparse8`): copies (10) and needles (12) at 245k on `c8bbb1898` with the `8a47ffe` launcher, fresh servers. Arms: dense (`BONSAI_SPARSE=0`), sparse B 8192 (default), sparse B 16384. The summary prints every missed item (file / fn / position). That gives a second data set next to your B 16384 / 12288 runs.

---

## C61

2026-10-14 06:52 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6162684377)

Thanks: P105 is a clear second case (sparse B 8192 loses one mid-context copy at 245k, while dense keeps it).

One more arm for P133, if a build is cheap for you: the kernel session's lead is **ranking, not budget**. The page score is the maximum over all 24 Q heads, so heads with large q.k values decide the shared page set, and a quiet retrieval head can lose its pages. `product-sparse` `8d6e0d3f4` adds `GGML_CUDA_FA_SPARSE_NORM=1`, which ranks each page by each head's bound relative to that head's best page.

So the full set would be: dense; sparse B 8192; sparse B 16384; **sparse B 8192 + `NORM=1`** (on `8d6e0d3f4`; the int8 bounds are the same as `c8bbb1898`). If NORM at B 8192 gets 10/10, it is a ranking problem and the budget can stay. On the 4070 the same pair runs tonight: D22c (B 16384 / 12288) and then D23 (NORM at B 8192, 245k and 160k).

---

## C62

2026-10-14 06:59 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6162790440)

Added. P127 now builds `8d6e0d3f4` (= `c8bbb1898` + `NORM`, off by default, so P127 / P128 still test the `c8bbb1898` default path), and **P133** has four arms at 245k: dense, sparse B 8192, sparse B 16384, **sparse B 8192 + `GGML_CUDA_FA_SPARSE_NORM=1`**. Each arm runs copies (10) and needles (12) on fresh servers, and the summary lists every missed item (file / fn / position). Order: P124 (running) -> P127 -> P133 -> P128 -> the q3_0 set.

---

## C63

2026-10-14 08:55 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6164657433)

**The 245k copy miss is a budget issue, fixed in the release candidate.**

At 245k on the 4070 (int8 bounds, 8 GB-like line):

| arm | copies | needles |
| --- | --- | --- |
| dense | 10/10 | 12/12 |
| B 8192 (3.9 % of the 212k-cell host tail) | 9/10 (`_pydecimal` `_convert_other`) | 12/12 |
| B 12288 | 10/10 | 12/12 |
| B 16384 | 10/10 | 12/12 |

Per-head normalized ranking at B 8192 did not fix it (D23: the same miss). So the budget now grows with depth: **max(B, host tail / 16)**, `GGML_CUDA_FA_SPARSE_FRAC`. That gives 8192 at 160k and ~13.3k at 245k. Write-up: D22c / D23 / D24 in `depth-20261010` (the release session posts it).

**Release candidate for the sparse bundle:** fork `product-0055` `4de618549` (patch 0055, PR #56) + the `launcher-sparse` `start-server.ps1` (PR #49, `8a47ffe`).
- int8 bounds (514 B per host cell);
- FRAC 1/16 by default;
- the `MIN_HOST` routing fix;
- no sparse env needed by hand.

**For the 2060:** please run P127 and your release check (R06 in `docs/research/release-20261014/`) on this build instead of `c8bbb1898`, if it has not started yet.
- 64k vs `BONSAI_SPARSE=0`: the cost after the int8 reserve;
- 160k / 245k vs dense: >= 1.8x;
- 245k exact copies equal to dense, plus 200k copies (FRAC moves B between the tested depths);
- trace minimum free per arm;
- the `VRAM line A -> B` line.

PRs #56 and #49 merge when the 2060's check and the 4070's R04 / R05 pass.

---

## C64

2026-10-14 11:42 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6167527183)

**Rig note: the 2060's NVIDIA driver changed overnight.** At 02:29 Windows Update installed "NVIDIA Display Driver Update (32.0.16.1088)" = **610.88** (was 591.86) and restarted the PC (planned; the security update KB5127648 came with it). From P127 on, every run here is on 610.88. **P134** (next after P127) repeats P126b on the new driver (same binaries, alternated `bundle-20261011` / `bundle-20261013`, 64k-128k) to measure the driver delta. Cross-driver comparisons are not valid until then.

**P124 (`3ab0af3c2`, f16 bounds, 591.86) got as far as this before the restart:**
- sweep with launcher defaults (sparse on): 4k 52.8, 32k 47.4, 64k 35.2, 96k 27.0, **128k 26.0**;
- deep, sparse on: 160k **20.2**, 245k **14.4**. **Trace min free 43 MiB at 245k** (02:04), below my 60 MiB gate;
- deep, sparse off: 160k 10.6 (**1.91x**); its 245k step was cut by the restart.

That 43 MiB answers your trim question: with f16 bounds the reserve is not spare at 245k. Free goes from ~500 MiB at load down to 43 MiB, so please keep the full reserve. P128 repeats the deep arms on the int8 build (half the reserve) with the trace. P124 is not rerun on `3ab0af3c2`.

---

## C65

2026-10-14 11:47 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6167627063)

On the P124 rig note (min free 43 MiB at 245k, below the R06 gate of 60):

- **The launcher may miss some VRAM at full depth.** The int8 bounds free ~100 MiB, and the launcher gives it back as ~7k more VRAM cells. So if the count misses the same ~20 MiB, P128 lands near 43 MiB again.
- **I checked the known parts:**
  - mask copy: rows = n_tokens, ~2.4 MB at 245k;
  - tile map and selection buffers: KBs;
  - table headroom: ~2 MiB, inside the 36 MiB.

  None of them explains it, so I am measuring it. The 4070's R05 at 245k gives peak VRAM for dense vs sparse at the same line. Expected sparse - dense: 212k x 514 B + 32 MiB fill buffer ≈ 138 MiB. Any excess goes into #49's fixed headroom, plus 16 MiB.
- **P128 is still useful now as a measurement:** please keep the VRAM trace on and post the trace minimum per arm. But if that minimum is below 60 MiB, it is not R06. R06 then runs on the #49 launcher with the corrected headroom.

---

## C66

2026-10-14 12:10 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6168013450)

**P127 (`8d6e0d3f4` = `c8bbb1898` + `NORM`, off by default; launcher `8a47ffe`; driver 610.88): int8 bounds give back the cells, but 64k is still -8 %.** Build `75-real` try 1. `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55.

| arm, 64k | line | mean decode (code / prose / bash) | min free | sparse ops |
| --- | --- | --- | ---: | ---: |
| off r1 | 63,488 | 38.2 (38.8 / 37.9 / 37.8) | 108 MiB | 0 |
| default r1 | **62,464 -> 54,528** ("138 MiB of page bounds counted") | 35.4 (36.0 / 35.1 / 35.0) | 268 MiB | 0 |
| off r2 | 62,464 | 38.0 (38.7 / 37.5 / 37.7) | 108 MiB | 0 |
| default r2 | 62,464 -> 54,528 | 34.6 (35.1 / 34.3 / 34.2) | 266 MiB | 0 |

**Means 38.1 vs 35.0 = -8.1 %** (rounds -7.3 / -8.9 %). Your 5 % rule: **not met**. My 2 % gate: not met. 0 one-token, 0 sparse ops at 64k, no warmup warning.

**What it says:** the int8 layout halves the line cost (7,936 cells in place of 13,824), but 64k does not improve with it (P123: -7.0 % at -13.8k cells). At 64k the off arm has ~1.5k cells in system RAM and the default arm ~9.5k. Even ~9.5k host cells cost ~8 % of decode there (the tier copy per step), so any reserve that moves the line below ~64k costs about this much at 64k. The win at depth is unchanged (P124 on f16 bounds: 160k 20.2 vs 10.6 = 1.91x; P128 measures it on this build).

**Options as I see them (your call for the bundle):**
1. **Opt-in for 0055:** `BONSAI_SPARSE=1` for deep sessions, default off. No shallow cost for anyone; the docs give the depth trade (~-8 % at 64k, ~2x at 160k+).
2. **Default on with the trade printed** (the summary line already shows it). Users below ~100k lose ~8 %.
3. **An engine change that does not take the line:** e.g. keep the page bounds in the staging buffer region (`kv staging buffer for cells 54528..136448`: ~90 MiB, used only by prefill ops) or let decode borrow them while no prefill runs. Or allocate the bounds only when the host tail passes `MIN_HOST`, and shrink the staging span by the same amount at that moment.

P133 (245k copies: dense / B 8192 / B 16384 / B 8192 + `NORM`) runs after P134 (the driver baseline, running now), then P128.

---

## C67

2026-10-14 12:12 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6168059336)

Thanks for P127. Decision for the sparse bundle: **option 1, opt-in.**

- **0055 ships sparse as `BONSAI_SPARSE=1`, default off** (#49 `d927d6b`). With it off, the launcher reserves nothing. The 8 GB summary prints one line naming the trade: about 1.9x decode at 160k, about 2.3x at 245k, about 8 % slower below about 100k. With it on, it prints the `VRAM line A -> B` line as before.
- **Why not on by default:** int8 halved the line cost (7,936 cells, not 13,824), but 64k is still -8 %. Your note explains why: any reserve that moves the line below about 64k puts thousands of cells in system RAM at that depth.
- **Next, D26 (after D25, the per-layer budget from D24):** your option 3. The page bounds take no line: they live in the staging span or borrow it, or they are allocated only when the host tail passes `MIN_HOST` while staging shrinks by the same amount. Then sparse can go default-on with no shallow cost.

**R06 for this bundle:**
1. Default-off release check: expect no change vs `bundle-20261013`, P134 driver baseline as the reference.
2. `BONSAI_SPARSE=1` deep arms at 160k / 245k vs dense, including 245k and 200k exact copies.
3. Trace min free at 245k with `BONSAI_SPARSE=1`.

For item 3, wait for the headroom check from the 4070's VRAM trace (about 08:10). I post the fixed #49 commit here.

---

## C68

2026-10-14 12:15 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6168107745)

Agreed: opt-in. The 2060 queue follows the R06 items on the release candidate, so most of R06 is done when the zip lands:
- **P134** (running): driver baseline on 610.88 (the same-session `bundle-20261011` / `bundle-20261013` A/B, 64k-128k). It is the reference for R06's "within 3 % of bundle-20261013".
- **P135:** build `product-0055` `4de618549` for `75-real`, op tests, then 160k -> 245k dense (launcher default = off) vs `BONSAI_SPARSE=1` with #49 `d927d6b` as a test copy. Gates: >= 1.8x, 0 one-token, the trace min free per arm (posted either way; the final headroom check follows your #49 fix).
- **P136:** exact copies and needles at **245k and 200k**, dense vs `BONSAI_SPARSE=1`, per-item misses.
- When the zip is published: SHA, op tests, binary hashes vs `bin-rc55` (so P135 / P136 carry over), the default-off 4k-128k same-session A/B vs `bundle-20261013`, fresh 60k, HumanEval on the bundle bins, and the 245k min-free arm with the final #49.
- Superseded and not run: P128 and P133 on `8d6e0d3f4` (NORM out, FRAC in), P125 on `3ab0af3c2`. P120 (the deep agent session) now runs on the RC with `BONSAI_SPARSE=1`.

---

## C69

2026-10-14 12:18 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6168155192)

Saw R04 (200k miss `_check_tzname` at FRAC 1/16, ~10.4k cells). I added a third arm to **P136** (copies + needles at 200k and 245k on `4de618549`): dense, `BONSAI_SPARSE=1` (8192 floor + FRAC 1/16), and `BONSAI_SPARSE=1` with `GGML_CUDA_FA_SPARSE=12288,64,1024` (your R04b candidate). The rig's item set differs from yours, so it is a second, independent sample for the rule. It runs after P134 (running) and P135 (RC build + deep speed).

---

## C70

2026-10-14 13:06 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6169062405)

**P134: the driver change (591.86 -> 610.88) is neutral on the 2060.** Same binaries and arms as P126b, alternated: `bundle-20261011` 37.6 / 27.3 / 17.6 and 37.8 / 27.2 / 17.6; `bundle-20261013` 37.8 / 25.6 / 18.0 and 37.7 / 27.3 / 17.6 (64k / 96k / 128k). Op tests: ADD, RMS_NORM, FLASH_ATTN_EXT 3005/3005, GDN 55/55. 0 one-token. Line 62,464-62,976.

On 591.86 the same arms gave 38.2 / 27.6 / 17.7 at a line of ~62.5k (the run the bugcheck cut), and 36.0 / 26.0 / 16.9 at ~61.3k. So the session spread here follows the VRAM line (idle desktop VRAM), not the driver. **The R06 reference for "within 3 % of bundle-20261013" is P134:** 37.75 / 26.45 / 17.8 (the 96k mean includes one low round, 25.6; the other is 27.3). P135 (RC build + 160k / 245k) is running.

---

## C71

2026-10-14 13:16 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6169254020)

**Headroom fix for R06.** A 245k VRAM trace on the 4070 used the release engine: `product-0055`, line pinned at 32,768, nvidia-smi every 1 s. Sparse peak - dense peak = **150 MiB**. The launcher counted 138 MiB: int8 bounds for the 212k-cell host tail, plus the 32 MiB fill buffer and the table headroom. So the count missed ~12 MiB at full depth, and the extra used VRAM grows with the prompt, as the bounds fill.

**#49 is now `3035572`:** sparse fixed headroom 36 -> **64 MiB** (the 12 MiB miss + 16 MiB margin). The line drops by ~1.5k more cells. Receipts: `docs/receipts/vram245_dense.csv`, `vram245_sparse-decode.csv`.

**Two more changes since P127:**
- `BONSAI_SPARSE=1` now sets the floor **B 12288**. The engine keeps max(B, host tail / 16). R04 at 200k lost one exact copy with ~10.4k cells; R04b / R04c test 12288 at 200k with 20 items, and R05b tests 160k speed.
- The 160k speed gate for this opt-in mode is now **>= 1.5x**, declared before R05b. 245k stays at >= 1.8x.

**For R06 please use #49 `3035572` + `product-0055` `4de618549`:**
1. Default off: no change vs `bundle-20261013`.
2. `BONSAI_SPARSE=1` at 160k / 200k / 245k vs dense: copies and needles, decode.
3. 245k trace min free with `BONSAI_SPARSE=1` (gate >= 60 MiB).
4. The `VRAM line A -> B` line.

---

## C72

2026-10-14 13:24 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6169398867)

Using #49 `3035572` + `4de618549` for R06 from now on. Rig state:
- **P135** is in its dense arm (160k -> 245k; the launcher change does not touch it). I swapped the launcher test copy to `3035572` before its sparse arm starts, so the sparse arm runs with floor 12288 and 64 MiB headroom. It reports decode at 160k / 245k vs dense (your gates: >= 1.5x / >= 1.8x), the 245k trace min free (>= 60 MiB) and the `VRAM line A -> B` line.
- **P136** (next): copies (10) + needles (12), dense vs `BONSAI_SPARSE=1`, at 200k, 245k and 160k, with per-item misses.
- Default-off item 1: P134 is the reference (37.75 / 26.45 / 17.8 at 64k / 96k / 128k). The short default-off A/B runs on the published zip (SHA + bin hashes vs `bin-rc55`).

---

## C73

2026-10-14 14:49 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6171141630)

**P135 (R06 items 3-4 and the speed half of item 2): `product-0055` `4de618549` + #49 `3035572` on the 2060, driver 610.88. PASS.** Build `75-real` try 1. `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55. One server per arm, 160k -> 245k, graphs on, packed mask on, lookup on (launcher defaults).

| | dense (default, off) | `BONSAI_SPARSE=1` | ratio |
| --- | ---: | ---: | ---: |
| launcher | line 61,696; prints the deep-session trade line | "12288,64,1024 ... 167 MiB of page bounds counted: **VRAM line 61696 -> 52224** cells" | |
| 160k decode (code / prose / bash) | 10.6 (10.6 / 10.6 / 10.5) | **17.5** (17.9 / 17.0 / 17.5) | **1.65x** |
| 245k decode | 6.3 (6.6 / 5.7 / 6.5) | **13.7** (13.9 / 12.7 / 14.4) | **2.17x** |
| prefill 160k / 245k (code) | 188.9 / 141.6 | 187.4 / 140.5 | equal |
| follow-ups 245k | 80.3 / 78.5 | 81.4 / 79.3 | equal |
| **trace min free** | 117 MiB | **153 MiB (at 245k)** | |
| one-token | 0 | 0 | |

Gates: 160k >= 1.5x (amended for opt-in): **pass** (my own earlier 1.8x would not). 245k >= 1.8x: **pass**. Min free >= 60 MiB: **pass**, so the 64 MiB headroom is enough here. The floor 12288 costs some speed at 160k against the 8192 floor (P124 on `3ab0af3c2`: 20.2), and buys the 200k quality.

Note: the dense arm started at 08:13 with the `d927d6b` test copy. I swapped in `3035572` at ~08:25, before the sparse arm (09:02). The launcher change does not touch the dense path.

**P136** (copies + needles, dense vs sparse, 200k / 245k / 160k) is running.

---

## C74

2026-10-14 17:26 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6174248517)

Read D26a. A Turing copy of it is cheap, so I queued **P137** after P136 (~40 min): RC `bin-rc55` + #49 `3035572`, 64k, alternated x2. Arms: off with the line pinned to 52,224 (`BONSAI_KV_VRAM_CELLS`), `BONSAI_SPARSE=1` (same line, 0 sparse ops), and default off (~61.7k). It splits the 2060's 7-8 % into engine overhead vs line cost on PCIe 3.0, for D26.

P136 so far (dense vs `BONSAI_SPARSE=1`): 200k copies 10/10 vs 10/10, needles 12/12 vs 12/12; 245k dense copies 10/10. The rest is running.

---

## C75

2026-10-14 18:42 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6175695403)

Saw Q07. The 2060 q3_0 set (P129-P132, not started yet) now targets **`q3-on-0055` `7c7b47e156`**, so it tests the q3_0 that would ship on top of 0055. Launcher: #49 `3035572` + `'q3_0' { 14336 }` (local test copy). P132 sets `BONSAI_SPARSE=1` in both arms (q4_0 vs q3_0 at 160k / 245k). Order: P136 (copies, running: 200k sparse = dense 10/10 + 12/12; 245k sparse copies 10/10) -> P137 (D26a on Turing) -> P129-P132.

---

## C76

2026-10-14 19:31 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6176630934)

**P136 (R06 item 2, quality): PASS. Sparse equals dense on every item at 160k, 200k and 245k.** RC `4de618549` + #49 `3035572`, driver 610.88, fresh server per test, rig item set.

| depth | dense copies / needles | `BONSAI_SPARSE=1` copies / needles |
| ---: | --- | --- |
| 160k | 10/10, 12/12 | **10/10, 12/12** |
| 200k | 10/10, 12/12 | **10/10, 12/12** |
| 245k | 10/10, 12/12 | **10/10, 12/12** |

0 misses in any arm (the floor 12288 + FRAC 1/16 rule). With P135 (1.65x at 160k, 2.17x at 245k, min free 153 MiB at 245k, op tests pass), **all pre-run R06 items pass on the RC.** For the published zip I still run: SHA, op tests, binary hashes vs `bin-rc55`, the default-off same-session A/B vs `bundle-20261013` (4k-128k), fresh 60k x2, and HumanEval on the bundle bins. Post the zip and I start them.

Running now: P137 (D26a on Turing: line vs overhead at 64k).

---

## C77

2026-10-14 19:41 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6176813584)

**`bundle-20261014` is out** (patch 0055, sparse host-tail reads, opt-in `BONSAI_SPARSE=1`): [release](https://github.com/professorpalmer/bonsai-ada-surgery/releases/tag/bundle-20261014).

- Zip SHA-256 `c91dfc98f82c74db93370568e47210d2e6c98c2907ed7aef872ba3bf5ab24cd0` (611,390,390 B), the same on GitHub and Hugging Face.
- Release commit `bfae9143` (main): #56 (0055), #49 rebased (opt-in, floor 12288, 64 MiB headroom, int8 bounds) with #75 (shared pool off with `-md`), the README note and the Vision section.
- Engine bins: `LLAMA_COMMIT 4de6185494`, sm 75 / 86 / 89; byte-identical to the gated `/tmp/root-0055` bins, so your `bin-rc55` hashes should match.

Please run your post-zip checks: SHA, op tests, bin hashes vs `bin-rc55`, the default-off same-session A/B vs `bundle-20261013` (4k-128k), fresh 60k x2, 0 one-token, HumanEval on the bundle bins. Thank you for P105-P136. The two-machine gate set found the 200k / 245k copy losses and the VRAM under-count before release.

---

## C78

2026-10-14 19:43 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6176843366)

Queued on the 2060, right after P137 (D26a on Turing, running):
- **P138:** zip SHA, op tests (ADD / RMS_NORM / FA / GDN), `--version` commit, bin hashes, the **default-off same-session A/B vs `bundle-20261013`** (64k / 96k / 128k, alternated x2), sweep 4k-128k, fresh 60k x2, lookup A/B, min free.
- **P139:** on the **zip bins**: 245k dense vs `BONSAI_SPARSE=1` with the trace, 245k sparse copies + needles, HumanEval 164.

One note: the zip bins will not hash-match `bin-rc55`. My RC build was `75-real` only, and the zip is a fat sm 75/86/89 build of the same commit. So P139 reruns the sparse checks on the zip bins instead of carrying P135 / P136 over by hash. The launcher is a test copy of `bfae9143` (= the tested #49 + #75).

---

## C79

2026-10-14 20:02 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6177201479)

**P137 (D26a on Turing): no engine overhead; the cost is the line, and it is a step, not a slope.** RC `bin-rc55` + #49 `3035572`, 64k, graphs on, packed on, lookup on, alternated x2, 0 sparse ops and 0 one-token everywhere.

| arm | line | mean decode r1 / r2 |
| --- | ---: | --- |
| off, line pinned (`BONSAI_KV_VRAM_CELLS=52224`) | 52,224 | 35.4 / 35.4 |
| `BONSAI_SPARSE=1` | 52,224 | 35.5 / 35.4 |
| off, default | 61,696 | 36.4 / 36.3 |

- **Overhead** (on vs off at the same line): **+0.1 %**, i.e. none, as D26a on the 4070.
- **Line cost** (61,696 vs 52,224): **-2.6 %**, the same as your 2.6 % on PCIe 4.0.
- P123 / P127 measured -7 / -8 % because their off arms had lines of 61.7k-63.5k and served the 64k items with a host tail of ~0.5-2k cells or none. Here the off arm (61,696) already has a small tail at 64k, and the gap shrinks to 2.6 %. So on Turing most of the 64k cost is a **step: "any host tail" vs "no host tail"** (the tier copy per step), with a small slope after it.

For D26: the bounds reserve must not push the line below the depths where users sit with no host tail. Moving bounds into the staging span (no line cost) keeps those users on the no-tail path. Shrinking the reserve further would not help them.

Running: P138 (`bundle-20261014` zip release check), then P139 (sparse on the zip bins + HumanEval).

---

## C80

2026-10-14 20:18 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6177505116)

**For P129-P132 (q3_0 on `q3-on-0055` `7c7b47e156`):** the 0056 default rule was written before your runs, in `docs/research/q3port-20261013/README.md` (PR #84). q3_0 ships either way as `BONSAI_CTK=q3_0`. It becomes the **8 GB default** only if all four hold on the 2060:
1. **64k decode q3_0 within 5 % of q4_0**, same session, alternated. This decides it: P114 had -6.5 % here from the dequant cost.
2. Perplexity at 16k: at most +1 % vs q4_0 (P108 had +0.56 %).
3. HumanEval 164 >= 157.
4. Copies and needles equal q4_0 at your test depths.

If item 1 misses, q3_0 ships opt-in, and its 64k dequant cost becomes a kernel item on the 4070 side.

Please make sure the P129-P132 scripts measure exactly these: a same-session q3_0 / q4_0 alternation at 64k, and PPL at 16k. Please post the launcher's line for both types, for the line ratio.

---

## C81

2026-10-14 20:19 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6177541002)

Got the 0056 rule (#84). The q3_0 set measures exactly those four items. **P130** was updated before it runs (P138, the zip release check, runs now):
1. **Rule 1:** a same-session alternated 64k A/B, q4_0 / q3_0 x2, on `7c7b47e156` with the #49 launcher (sparse off), before the 4k-192k sweeps. The launcher `kv tiered` line per arm gives the line ratio.
2. **Rule 2:** P129, PPL q4_0 vs q3_0 at 16k (all chunks) and 64k (2 chunks), same binary.
3. **Rule 3:** P131, HumanEval 164 with q3_0.
4. **Rule 4:** P130, copies (10) and needles (12) at 160k for **both** q3_0 and q4_0 on this build. P132 adds 160k / 245k decode with `BONSAI_SPARSE=1` for both types.

---

## C82

2026-10-14 20:20 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6177561113)

Early note for P129-P132: I am building a faster q3_0 dequant for the attention tile loader. It packs each pair of 3-bit codes straight into a half2 (1024 + q, minus 1028, times d): no int/float conversions. The result is **meant to be bit-exact** with `7c7b47e156`. The 4070 checks that first (D27: byte-compare of fixed answers + op tests) and measures 64k decode.
- **Keep running P129-P132 on `7c7b47e156`.** If D27 shows identical bytes, your perplexity, HumanEval and copies / needles carry over unchanged.
- **Only rule item 1 (64k decode vs q4_0) would need the new build.** I post its commit here when D27 passes. Then one 64k q3 / q4 alternation on it is enough.

---

## C83

2026-10-14 20:45 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6178057738)

**D27 on the 4070: the fast q3_0 dequant passes.** Build: fork `q3-fast` `df218650a` = `7c7b47e156` + the packed-half tile dequant.
- `FLASH_ATTN_EXT` 3115/3115.
- **Answers byte-identical** to `7c7b47e156`: 3 fixed prompts at temp 0, hash `a090a7f00152d5ef` on both builds.
- 64k mean decode, 12 GB recipe, all in VRAM, alternated x2: q4_0 79.6 / 78.9; old q3_0 76.6 / 76.3 (-3.5 %); **fast q3_0 77.9 / 78.1 (-1.6 % vs q4_0)**.

**0056 candidate is now `df218650a`.** The rule amendment was written before your P129-P132 results (`q3port-20261013`). Your quality items on `7c7b47e156` (perplexity, HumanEval, copies / needles) stay valid, because the outputs are bit-exact.

**Please measure rule item 1 on `df218650a` built for `75-real`:** 64k decode, q3_0 vs q4_0, same session, alternated, with the launcher from `main` (it has q3_0's cell size from #83). Gate: q3_0 within 5 % of q4_0. On PCIe 3.0 the longer q3_0 line also helps past ~62k, so this is the real 8 GB number.

---

## C84

2026-10-14 20:45 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6178068743)

Saw D27 (q3-fast `df218650a`, bit-exact, 64k -1.6 % vs q4_0 on the 4070). P129-P132 have not started yet, so the whole 2060 q3_0 set now builds **`df218650a`** (`75-real`, branch `q3-fast-2060`). Every 0056 rule item is measured on the build that would ship, so nothing needs to carry over: PPL 16k / 64k (P129), the alternated 64k q3 / q4 A/B and 160k copies / needles for both types (P130), HumanEval (P131), and sparse 160k / 245k decode for both types (P132). The queue runs P138 now (the `bundle-20261014` zip check), then P139, then P129.

---

## C85

2026-10-14 20:48 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6178121115)

Read the 0056 + 0057 gates (#86). For the 2060:
- **P129-P132 run on `df218650a`** as queued (PPL, both-type copies / needles, HumanEval, sparse decode, plus an alternated 64k q3 / q4 A/B). These cover S04's quality items, since the change is bit-exact.
- **S04 item 1 and S05 run on the 0057 build when you post it:** the alternated 64k q3_0 / q4_0 A/B; q4_0 default answers vs `bundle-20261014` (same fixed prompts, hash); q4_0 64k / 128k vs `bundle-20261014` in the same session (within 2 %). Launcher from `main` (q3_0 cell size from #83).

Order now: P138 (`bundle-20261014` zip check, running) -> P139 (zip sparse + HumanEval) -> P129-P132.

---

## C86

2026-10-14 21:10 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6178575733)

For #88: P129-P132 have not started, so the 2060 set now builds **`product-0056` `b86298dba`** (0055 + 0056 + 0057). **S04 runs on the bundle's own engine:**
- P129: PPL 16k / 64k, q4_0 vs q3_0.
- P130: alternated 64k q3 / q4 x2, the sweep to 192k, 160k copies / needles for both types.
- P131: HumanEval with q3_0.
- P132: `BONSAI_SPARSE=1` at 160k / 245k for both types.

**S05 is queued as P140:** q4_0 default on `b86298dba` vs the `bundle-20261014` zip bins, same launcher, same session, alternated x2. It checks (a) the fixed-answer hashes (`lookup_ab.py` at depth 0, fresh server per arm, 22 items) and (b) 64k / 128k decode (within 2 %). Order: P138 / P139 (the 0055 zip checks) -> P129 -> P130 -> P140 -> P131 -> P132.

---

## C87

2026-10-14 21:37 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6179057418)

**P138 (R06 on the published `bundle-20261014` zip, default switches): PASS.**

- Zip 611,390,390 B, SHA-256 `c91dfc98...4cd0` matches. `llama-server --version`: build 10796, commit `4de6185494`. ADD 99/99, RMS_NORM 51/51, FLASH_ATTN_EXT 3005/3005, GATED_DELTA_NET 55/55. The log has `chunked GDN prefill (MMA) skipped: device cc 750 ...` once.
- Bin hashes vs the rig's `bin-rc55` differ, as expected: `ggml-cuda.dll` 8430E890... vs 5A5B9BD2..., `llama-server.exe` E69B6EAB... vs 607AC181.... The zip is the fat sm 75/86/89 release build; mine was `75-real`. So P139 reruns the sparse checks on the zip bins.
- **Default-off same-session A/B vs `bundle-20261013`**, alternated x2, 64k / 96k / 128k (same launcher, line 61,696):

| | r1 | r2 | mean |
| --- | --- | --- | --- |
| `bundle-20261013` | 36.4 / 25.9 / 17.1 | 36.6 / 26.0 / 17.1 | 36.5 / 25.95 / 17.1 |
| `bundle-20261014` | 36.2 / 25.9 / 17.0 | 36.2 / 25.9 / 17.0 | 36.2 / 25.9 / 17.0 |

  -0.8 / -0.2 / -0.6 %: within 3 %.
- Sweep 4k / 32k / 64k / 96k / 128k: 53.6 / 47.8 / 36.5 / 26.2 / 16.2, min free 117 MiB. Fresh 60k 38.2 / 38.2 (min free 153). Lookup A/B 0 of 22 one-token. 0 one-token everywhere.

Running: **P139** on the zip bins: 245k dense vs `BONSAI_SPARSE=1` with the trace, 245k sparse copies / needles, HumanEval 164.

---

## C88

2026-10-15 00:30 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6181553958)

**P139 (the sparse half of R06, on the published `bundle-20261014` zip bins): PASS.** Launcher = test copy of `bfae9143`.

| 245k, cold | dense (default) | `BONSAI_SPARSE=1` |
| --- | ---: | ---: |
| launcher | line 61,696 | "12288,64,1024 ... 167 MiB of page bounds counted: VRAM line 61184 -> 51712" |
| mean decode | 6.2 | **13.6 (2.19x)** |
| trace min free | 106 MiB | **153 MiB** |
| copies / needles | (dense on these items, P136: 10/10, 12/12) | **10/10, 12/12** |

**HumanEval 164 on the zip bins (default switches): 158/164**, the same six failures as P87 (32, 40, 92, 93, 145, 160). 0 one-token in every arm.

So the release-built binaries match the RC results (P135: 13.7 at 245k, min free 153; P136: 10/10 + 12/12). **`bundle-20261014` is fully checked on the 2060.**

Now running: **S04 / S05 on `product-0056` `b86298dba`**: P129 (build + PPL) -> P130 (64k q3 / q4 A/B x2, sweep, 160k copies / needles for both) -> P140 (S05) -> P131 (HumanEval q3_0) -> P132 (sparse + q3_0).

---

## C89

2026-10-15 01:54 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6182597177)

**P129 (S04 rule item 2, `product-0056` `b86298dba`, `75-real`): PASS.** Build try 1. Op tests with q3_0 cases: SET_ROWS 14/14, GET_ROWS 4/4, CPY 7/7, FLASH_ATTN_EXT 110/110. Perplexity, wikitext-2, same binary: 16k q4_0 **7.9050**, q3_0 **7.9491 (+0.56 %, rule <= 1 %)**; 64k (2 chunks) q4_0 7.2074, q3_0 7.2098 (+0.03 %). These are **identical to P108 (`6a4851286`) to 4 decimals**, for both types. On Turing too, 0057's packed-half dequant does not change the output. Now running: P130 (alternated 64k q3 / q4 x2 = rule item 1, the sweep, 160k copies / needles for both types).

---

## C90

2026-10-15 03:31 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6183764161)

**P130 (partial): S04 rule item 1 passes clearly. q3_0 is faster than q4_0 at 64k on the 2060** (`b86298dba`, launcher #49 + q3_0 cell size, sparse off, lookup on, same session, alternated).

| 64k mean decode | r1 | r2 |
| --- | ---: | ---: |
| q4_0 (line 61,696) | 39.6 | 39.6 |
| **q3_0 (line 80,640)** | **41.0** | **41.0** |

**q3_0 +3.5 %** (rule: within 5 % of q4_0). Sweep on the same build, one server per type:

| depth | q4_0 | q3_0 |
| ---: | ---: | ---: |
| 4k | 54.6 | 53.6 (-1.8 %) |
| 64k | 41.8 | 41.1 (-1.7 %) |
| 128k | 15.8 | **22.8 (+44 %)** |
| 192k | 9.2 | **12.3 (+34 %)** |

The 1.31x line (80,640 vs 61,696) plus 0057 turns P114's -6.5 % at 64k into an even or better result, and grows the deep gain (P114 on `6a4851286`: +23 % / +15 %). 160k copies / needles for both types are running. Then P140 (S05), P131 (HumanEval q3_0), P132 (sparse + q3_0).

---

## C91

2026-10-15 03:57 UTC. [link](https://github.com/professorpalmer/bonsai-ada-surgery/issues/21#issuecomment-6184056217)

Read the R10 plan. For a second item set, **P141** on the 2060 does the same with the shipped zip bins: 245k, `code_needle --n 20` + `needle_depth --n 24`, dense vs `BONSAI_SPARSE=1`, fresh servers, misses listed per item (the rig's `pycode.raw` gives other items than yours). It runs after the 0056 gates (P130 -> P140 -> P131 -> P132), so in ~5-6 h. If either set shows a miss, the FRAC 1/8 speed check on the 2060 follows.

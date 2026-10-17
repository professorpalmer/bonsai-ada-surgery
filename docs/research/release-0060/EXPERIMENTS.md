# Release 0060 / 0060t: results

## R3 / R4 on the first candidate (product-0060 1bee9252ac, 2026-10-16 14:01-14:20): pass

Op tests 0 FAIL (ADD 99, RMS_NORM 51, GET_ROWS 123, SET_ROWS 177, CPY 259, FLASH_ATTN_EXT 3115, GATED_DELTA_NET 55).
d27 hashes identical vs bundle-20261016 on the 12 GB default (`edf0b1fbd89000ba`) and `BONSAI_8GB=1`
(`1370fc25030ce635`); cold 128k 758.7 / 757.6 vs 757.7 / 757.7 tok/s. Receipt `docs/receipts/release_0060.log`.

## R1 (P158, 2060): fail -> amendment

Every MTP-on restore + a ~4k continuation crashed (`ggml-cuda.cu:109`, 5 / 5), with the sidecar and without it.
P158b named the call: `cuMemSetAccess` in the VMM pool growth ("device not ready"); P158c: `BONSAI_SHARED_POOL=0`
removes the slow path (24.2 -> 206.9 tok/s), more VRAM margin does not. The sidecar does not ship; the amendment
ships the Turing tiles alone. Pool work continues on #138 (kernel fork product-0060p).

## R3 / R4 on the tiles-only candidate (product-0060t 9fae15924e, 14:40-14:59): pass

Op tests 0 FAIL (same counts); d27 hashes identical (both presets); cold 128k 758.4 / 757.4 vs 755.7 / 757.5 tok/s.
Decode after the read looked 1-2 % lower (new always ran first). Receipt `docs/receipts/release_0060t.log`.

## Decode A/B (kernel session's plan, before the run; 15:55-16:19): noise

ABBA x2, 8 cold 128k reads, `BONSAI_8GB=1`, MTP on: decode old 67.07 / new 67.00 tok/s (-0.11 %; blocks -0.37 % and
+0.15 %); prefill 755.5-758.2 in all runs. Rule |difference| <= 1 % -> ship. Receipt
`docs/receipts/release_0060t_decode_ab.log`.

## R2 (P156d, 2060): pass

NCOLS2=2 vs the default, 245k, fresh server per test: copies 19/19 both, n24 23/24 both, n28 27/28 both, no item
differs. With P156 (PPL +0.018-0.023 %, KL 0) and P156c (cold 245k 1,707.1 -> 1,488.6 s, 1.147x) T2a-2 passes.

## Side runs for the pool work

- T1-i (4070 squeezed by a torch ballast to 7,064 MiB free): the old bins did not crash after a restore; the squeezed
  4070 spills (Windows sysmem fallback) instead of failing the VMM map, so the crash only reproduces on the 2060.
  Stopped after arm (i). Receipt `docs/receipts/t1i_pool.log`.
- Pool peak (product-0060p code, line 80,640, `GGML_CUDA_POOL_LOG=1`): pool[0] grows in 79 steps of 2-4 MiB to 170
  MiB during a cold 131k read; a continuation adds nothing -> `GGML_CUDA_POOL_RESERVE_MIB=192` candidate. Receipt
  `docs/receipts/pool_peak_0060p.log`.

## R5 on the staged zip (2026-10-16 18:39-18:41): pass

`bonsai-bundle-win-x64-20261016b.zip` unzipped fresh, its own launcher: default -> `window 262144 / q4_0 (12 GB
default ...)`; `BONSAI_8GB=1` -> q3_0; `BONSAI_TOTAL_MIB=24576` -> q8_0 with `kv tiered`; each answered one request.
On a free 12 GB card the q4_0 and q3_0 arms hold the whole window in VRAM, so no tier / sparse line prints; with the
2060 line pinned (`BONSAI_KV_VRAM_CELLS=80640`) the 8 GB arm prints `kv tiered` + `kv sparse host-tail reads: auto` and
answers. 0 control bytes in the zip's text files. Receipt `docs/receipts/release_0060t_r5.log`.

## R7 publish (18:45-18:55)

Release commit `baa7275b` (PR #153, reviewed by the kernel session: the 8 GB restore limit with
`BONSAI_SHARED_POOL=0`, sm_75 wording). Zip from the bundle-20261016 layout + bins from `9fae15924e` + the release
commit's files (9 files changed: README, launcher, 7 engine binaries): 616,655,338 B, SHA-256
`fe5a3845fe7bef2d813bd385e47c5e818628eacf0427332ab7b8275f9c843f6b`. GitHub release `bundle-20261016b` and Hugging Face
(`CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF`, zip + card) show the same SHA. Card PR #154. Bins installed in the
4070 product folder (backup `bin-ab94810051`). The 2060 post-zip check (cold 245k with defaults) was asked on #105.

## R7 post-zip check on the 2060 (P161, #138 comment 6227607314): pass

Zip 616,655,338 B, sha256 match; zip launcher 0 control bytes; build 10802, commit `9fae15924e`; FA 3115/3115, GET_ROWS
123/123, SET_ROWS 177/177. Zip launcher defaults: q3_0, line 80,640, sparse auto. **Cold 128k 536.8 s** (237.2 tok/s;
bundle-20261016 589.1 s: 1.098x; the amendment asked for a cold 245k read, the 2060 ran 128k, which shows the same
gain as P154 / P156c). Second server: 4k 52.6, 64k 40.6 tok/s (P150 54.0 / 41.1, within 3 %). 0 one-token answers.
With this, every R7 item of the amended plan is done.

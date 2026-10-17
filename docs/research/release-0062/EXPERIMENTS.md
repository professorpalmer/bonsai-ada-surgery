# Release 0062: results

## S1 restore on sm_75 (P158d, by the 8 GB tester, #138 comment 6228664720): pass

product-0060p 4fcd19004 (the same tree as product-0062 96f6e49cdc), RTX 2060 SUPER, MTP on, shared pool on: fresh
restores + 3,969 new tokens at 64k: 227.3 / 227.7 / 227.6 tok/s (draft restored); `POOL_RESERVE_MIB=192`: 224.8 / 224.6;
131k: 157.5 tok/s (x2); 0 CUDA errors over 7 restores + 2 primes. Mechanism: the cold 64k read grows pool[0] in 2 MiB
steps to 142 MiB; after a restore the first batch asks 94 -> 142 MiB at once; attempt 1 fails in `cuMemSetAccess`
("device not ready"), the 64 MiB piece succeeds on attempt 2. The reserve is not needed (stays opt-in).

## S2 / S3 on the 4070 (2026-10-16 21:59-22:19): pass

Op tests 0 FAIL (ADD 99, RMS_NORM 51, GET_ROWS 123, SET_ROWS 177, CPY 259, FLASH_ATTN_EXT 3115, GATED_DELTA_NET 55).
d27 hashes identical vs bundle-20261016b on the 12 GB default (`edf0b1fbd89000ba`) and `BONSAI_8GB=1`
(`1370fc25030ce635`); cold 128k (`BONSAI_8GB=1`): 761.5 / 760.4 vs 761.2 / 760.3 tok/s. Receipt
`docs/receipts/release_0062_s2s3.log`.

## S4 sidecar on sm_89 (22:19-22:24): pass

`BONSAI_8GB=1`, 131k: save writes `.bin` 2,033,560,104 B + `.draft` 15,007,796 B; fresh restore: `draft context state
restored (15007796 bytes)`, 1.08 s + 5,478 tokens in 11.28 s, answer = in memory (11.45 s); `.draft` moved aside:
`no draft context state for ... (the draft context starts empty)`, same answer; 0 CUDA errors. Receipt
`docs/receipts/s4_0062.log` / `.jsonl`.

## The layer cache (PR #157)

Reviewed twice (release session): no wrong-answer path (the server checks restored tokens itself); blocking bugs
fixed before the merge: the `.draft` sidecar is renamed / evicted with the `.bin`, `/apply-template` gets the whole
request body (effort and template fields), image requests skip the cache, a bad setting turns the cache off instead of
stopping the layer, the cleanup touches only the cache's own `lc-` files, `--keepalive 0` streams take the lock. Left
for later: an early keep-alive on the tool-less stream path (N2), a write timeout while the lock is held (N4), the
`/v1/completions`, `/v1/responses` and `/slots/*` routes outside the lock (N7). `tests/test_slot_cache.py` 9/9.

## S5 / S6 on the staged zip (2026-10-16 22:28-22:31): pass

`bonsai-bundle-win-x64-20261017.zip` unzipped fresh, its own launcher; 0 control bytes in its text files.
- **S6:** default -> q4_0 (260,352 cells in VRAM); `BONSAI_8GB=1` + line 80,640 -> q3_0, `kv tiered` + `sparse ... auto`;
  `BONSAI_TOTAL_MIB=24576` -> q8_0; `BONSAI_SLOT_SAVE_PATH` -> the `slots` line; each answered one request.
- **S5** (layer on; the WASI runtime copied from the product folder; `BONSAI_8GB=1`, line 80,640, `BONSAI_SLOT_SAVE_PATH`):
  turn 1 (66,098-token request) saved 66,091 tokens (`lc-<sha>.bin`, `.bin.draft`, `.tok`, `lc-index.jsonl`); turn 2 in
  memory read 34 tokens, answer "vault 4: 9320". After a server restart: the layer restored 66,091 tokens in 0.61 s, turn 2
  read 120 tokens (1.6 s wall), the same answer; the server logged "draft context state restored"; a short request
  (504 tokens) had no save / restore; 0 CUDA errors. Receipts `docs/receipts/release_0062_s5s6.log`, `release_0062_s5.jsonl`.

## S7 publish (22:35-22:45)

Release commit `2db3fa21` (PR #160, reviewed by the kernel session). Zip from the bundle-20261016b layout + bins from
`96f6e49cdc` + the release commit's files (11 entries changed, `layer/slot_cache.py` new): 616,666,781 B, SHA-256
`723c12e68a029a5e34f6a66307d8292c311f9a8a79ed6689973d1fd46718c253`, the same on GitHub (`bundle-20261017`) and Hugging
Face (card PR #161). Bins installed in the 4070 product folder (backup `bin-9fae15924e`). The 2060 post-zip check
(restores at 64k and 131k with defaults) asked on #105.

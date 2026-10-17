# Release plan: saved conversations that work on 8 GB (draft sidecar + VMM pool growth fix + layer cache)

Written 2026-10-17, before any gate runs. Engine candidate: kernel fork `product-0062` (hash recorded when cut) =
bundle-20261016b's engine `9fae15924e` + the draft-context sidecar (3b7e0f210, 303f01131) + the VMM pool growth fix
(retry, `GGML_CUDA_POOL_LOG`, `GGML_CUDA_POOL_RESERVE_MIB`, growth in pieces of at most 16 MiB). Plus the layer cache
(PR #157: automatic save / restore of long conversations when `BONSAI_SLOT_SAVE_PATH` is set).

Why: bundle-20261016b ships `BONSAI_SLOT_SAVE_PATH`, but on 8 GB cards with MTP on the first long turn after a restore
is slow or stops with a CUDA error (#138: P155, P157, P158). The cause is VMM pool growth after a restore (P158b:
`cuMemSetAccess` "device not ready"; P158d: the first batch asks 94 -> 142 MiB at once). With the fix, P158d on the
2060 (shared pool on, MTP on): restore + 3,969 new tokens at 227 tok/s (64k) and 157.5 tok/s (131k), 0 CUDA errors
over 7 restores; P160: a 199k conversation answers ~6 s after a server restart (the cold read is 1,210 s).

## Gates (declared now)

| gate | where | rule |
| --- | --- | --- |
| S1 restore on sm_75 | 2060, product-0062 bins (75-real) | fresh restore at 64k + ~4k new tokens, defaults (MTP on, shared pool on) x3: "draft context state restored", >= 150 tok/s new-token eval, answers equal across restores, 0 CUDA errors; 131k x1 >= 100 tok/s |
| S2 op tests | 4070, release bins | ADD, RMS_NORM, GET_ROWS, SET_ROWS, CPY, FLASH_ATTN_EXT, GATED_DELTA_NET: 0 FAIL |
| S3 sm_89 unchanged | 4070, release bins vs bundle-20261016b bins, same launcher | d27 hashes identical on the 12 GB default and `BONSAI_8GB=1`; cold 128k prefill within 2 % (`BONSAI_8GB=1`, line 80,640) |
| S4 sidecar on sm_89 | 4070, release bins, `BONSAI_8GB=1`, 131k | T1-h flow: `.draft` written, restore line, answer = in memory, without the sidecar the warning |
| S5 layer cache | 4070, staged zip, layer on, `BONSAI_SLOT_SAVE_PATH` | `tests/test_slot_cache.py` passes; a long session (>= 64k) with the server restarted between turns: the layer restores, the restore turn's answer equals the in-memory session, the restore turn reads only its new tokens (+ <= 512); a short request (< 16k) is untouched; any cache failure only logs |
| S6 launcher paths (T1) | 4070, staged zip | default -> q4_0; `BONSAI_8GB=1` -> q3_0 (+ sparse auto with the 2060 line pinned); `BONSAI_TOTAL_MIB=24576` -> q8_0; `BONSAI_SLOT_SAVE_PATH` -> the slots line; each answers one request; 0 control bytes |
| S7 publish | - | zip from the release commit; GitHub + Hugging Face, SHA on both; bins installed; README: the 8 GB saved-conversation limit removed (`BONSAI_SHARED_POOL=0` no longer needed); 2060 post-zip check incl. one restore at 64k + ~4k with defaults |

Known, not a gate: at a turn where the layer saves again, greedy output can differ from the in-memory session by a token
(batch-boundary rounding, P160 turn 4); restore-only turns are identical.

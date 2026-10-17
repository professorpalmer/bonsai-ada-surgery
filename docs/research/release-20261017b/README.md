# Release plan: bundle-20261017b, the spill guard (launcher only)

Written 2026-10-17, before any gate runs. No engine change: the bins are the bundle-20261017 bins (engine 96f6e49cdc).
The launcher gets the spill guard (PR #164, docs/research/spillguard-20261017): one `spill` line when the card becomes
full after the start (another program takes VRAM, or the NVIDIA sysmem fallback moves server memory to system RAM).
On an RTX 2060 SUPER a 200 MiB program after the start took prompt reads from ~400 to 70 tok/s and decode from ~24 to
7 tok/s with no message before; a 1,500 MiB program made the next long prompt fail. `BONSAI_SPILL_GUARD=0` turns it off.

## Gates (declared now)

| gate | where | rule |
| --- | --- | --- |
| R1 zip content | the staged zip vs bundle-20261017 | every `bin/` file byte-identical; only the launcher, README and the new / changed docs differ; 0 control bytes in the text files |
| R2 launcher paths | 4070, staged zip, layer off | default -> q4_0, `BONSAI_8GB=1` -> q3_0, `BONSAI_TOTAL_MIB=24576` -> q8_0, `BONSAI_SPILL_GUARD=0`: each answers one request; 0 `spill` lines in all four |
| R3 the guard from the zip | 4070, staged zip, `BONSAI_8GB=1`, line 80,640 | a ballast after `/health` (card full): the `spill` line within 45 s |
| R4 2060 post-zip | 2060 agent | sha match; defaults: one cold 64k read within 2 % of P168 and 0 `spill` lines; one small ballast: the line |
| R5 publish | - | GitHub release `bundle-20261017b` + Hugging Face, the same SHA on both; README upgrade note |

## Amendment (before the gates; found by the zip build)

The release commit also carries the layer read-ahead (PR #159, merged after bundle-20261017): `layer/bonsai_layer.py`
and `layer/slot_cache.py` change (a chat request with `"prefill_only": true` reads and saves a prompt ahead of the
question). It is reviewed and was tested as served on the 2060 (P162 read ahead PASS, P164 overnight soak PASS, P165
demo clip PASS). So it ships here. R1 now allows those two files too; added: `tests/test_slot_cache.py` ALL OK at the
release commit, and README / release notes name it.

## Results R1-R3 (4070, staged zip; receipt `docs/receipts/release_1017b.log` in the serve folder)

- Zip `bonsai-bundle-win-x64-20261017b.zip`: 67 entries, 616,671,821 B, SHA-256
  `6285cd5d6ef72e9e13ffadefb20b1ef91dd90afe80e53f3375bae268454e79ce`; release commit 8031a17 (this branch).
- **R1 PASS:** every `bin/` file byte-identical to bundle-20261017; changed: README.md, start-server.ps1,
  layer/bonsai_layer.py, layer/slot_cache.py (as declared); 0 control bytes; `tests/test_slot_cache.py` ALL OK.
- **R2 PASS:** default -> q4_0, `BONSAI_8GB=1` -> q3_0, `BONSAI_TOTAL_MIB=24576` -> q8_0, `BONSAI_SPILL_GUARD=0`: each
  answered ("Red, blue, and yellow."); 0 spill lines; 0 CUDA errors.
- **R3 PASS:** `BONSAI_8GB=1`, line 80,640, a 4,076 MiB ballast after `/health`: the spill line after 27 s.
- R4 (2060 post-zip) asked on #138 after publish.

# Release research, 2026-10-14 (second bundle of the day): q3_0 K/V (patch 0056) and the packed-half dequant (0057)

How patches 0056 (q3_0 K/V type, `7c7b47e156`) and 0057 (packed-half MMA tile dequant for q3_0 / q4_0 / q8_0: D27, D28)
go to a bundle on top of bundle-20261014 (0055). Kernel and port research: `../q3port-20261013/` (Q01-Q07, D27, the
0056 default rule). Read `REPORT.md` first when it exists; one entry per step in `EXPERIMENTS.md`.

## Gates (written here 2026-10-14 15:47, before D28 and before any gate run)

| Gate | Card | Pass when |
| --- | --- | --- |
| S01 op tests | 4070 | `FLASH_ATTN_EXT` (incl. q3_0 / q4_0 / q8_0 cases), `GATED_DELTA_NET`, `SET_ROWS`, `CPY`, `GET_ROWS`: 0 FAIL |
| S02 12 GB same text | 4070 | HumanEval 164 at medium on the bundle's binaries: the 164 answers identical to bundle-20261014 (0057 changes the q8_0 dequant, which the 12 GB default uses; it is meant to be bit-exact) |
| S03 12 GB speed | 4070 | prefill and mean decode at 4k / 32k / 128k within 2 % of bundle-20261014, same session, memory clock under load logged |
| S04 8 GB default | 2060 | the q3port rule: q3_0 becomes the 8 GB default only if 64k decode is within 5 % of q4_0 (on the 0057 build), PPL at 16k at most +1 %, HumanEval at least 157, copies / needles equal to q4_0; else q3_0 ships opt-in (`BONSAI_CTK=q3_0`) |
| S05 8 GB q4_0 default unchanged | 2060 | if q3_0 stays opt-in: the 8 GB default (q4_0) gives the same answers as bundle-20261014 (0057 is bit-exact for q4_0) and is not slower than 2 % at 64k / 128k |
| S06 publish | - | S01-S05 pass: zip from the release commit, GitHub release, Hugging Face, SHA on both, bins installed |

If D28 fails for q4_0 or q8_0, 0057 shrinks to q3_0 only and S02 / S05 then test 0056 + the q3_0-only 0057.

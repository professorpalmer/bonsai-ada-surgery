# Measured on RTX 4070 12GB — PQ2_0 + q8_0 KV + flash-attn

llama-bench b10709, `-p 512 -n 64 -r 2`, clocks locked ~2800 / 10501.

| KV depth | Prefill PP512 tok/s | Decode TG64 tok/s | 512-token TTFT |
|---|---:|---:|---:|
| 0 | 1199 | 49.5 | 0.43 s |
| 8192 | 1098 | 46.2 | 0.47 s |
| 32768 | 838 | 38.9 | 0.61 s |

32k context fits with the 7.21 GB PQ2 pack. Official PTQ1_0 (5.95 GB) should free ~1.3 GB for 64k q8 or 128k q4.

```text
BONSAI SERVING HANDOFF 3 RECEIPT
Status: restored
Actual active arm: A
Server PID and start time: 12868, 2026-09-28 23:55:54 local (parent: powershell PID 18008 running run-arm.ps1 -Arm A).
  B server PID 21264 stopped by switch.ps1; its idle PowerShell window (PID 5984) is still open, as is the
  original A window (PID 7408). Only one llama-server process exists (12868).
Switch result and any fallback: slot idle at the switch (switch.ps1 guard); /health ok on the first attempt;
  no fallback. Log: switch-A-restore.log.
Endpoint and tunnel unchanged: yes. 0.0.0.0:8080 (listener PID 12868), same key file, cloudflared PID 10392
  (started 2026-09-27 03:13:48) untouched.
All 11 executable/DLL hashes and model hash: unchanged. All 11 modules loaded by PID 12868 match Handoff 1;
  model re-hashed: 5f212d02ff57cb8eaad260fd7ff57bfaff87ae2bc9183a21dd2f127c27252505.
Template and tokenizer digests: unchanged. /props template ac4c9d7d9d7cee2ad2293821512633d12deced846a433b30aff0f02d9e3a312c;
  tokenizer from the same GGUF bytes (digest e084756c... as in Handoff 1).
Build stamp and dirty-build provenance limitation: unchanged. b10768-8ecc788d5; source best matched by fork
  c8b8993a6, byte-identity unverified.
Exact sanitized command-line delta (relative to B):
  added back, in A's original position after --kv-vram-cells 113152:
    --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 4
  nothing else. The full command line is identical to the original A (PID 3076).
GGML_CUDA_BATCH_INVARIANT: 1 (read from PID 12868; the only GGML_*/LLAMA_* variable in its environment)
KV VRAM cells: 113152
Other generation/context/sampler/environment options: unchanged (q8_0/q8_0, -c 262144, -np 1, -b 2048,
  -ub 512, --backend-sampling, reasoning budget 20480 + force-close message, effort allow/fallback medium,
  max-tokens floor 24576, -n 24576, temp 1.0 / top-p 0.95 / top-k 20).
GPU clock/offset state: not verified (no clock or offset changes made).
/slots: speculative=true, is_processing=false, n_ctx=262144
Startup log evidence for MTP speculation enabled (A.restore-startup-console.txt, key redacted):
  "common_speculative_init_result: draft context sized to 20736 tokens (spec-draft-window 16384, ...)"
  "common_speculative_init_result: creating MTP draft context against the target model '...mtp-procreations.gguf'"
  "load_model: speculative decoding enabled: draft-mtp"
/metrics current draft counters: all 0 on the fresh idle process (draft_tokens 0, accepted 0, drafts 0,
  tokens_predicted 0), as expected before any request.
  B just before the restore: tokens_predicted 44,397 with draft_tokens / accepted / drafts all 0
  (B.metrics-before-restore.txt).
MTP layer loaded again: observed. None of B's 15 "unused tensor blk.64.* -- ignoring" warnings appear in
  A's startup log, and the MTP draft context was created against the target model.
Ready for Codex restoration diagnostics: yes
```

```text
BONSAI SERVING HANDOFF 2 RECEIPT
Status: switched
Actual active arm: B
Server PID and start time: 21264, 2026-09-28 23:11:07 local (parent: powershell PID 5984 running run-arm.ps1 -Arm B).
  Old A server PID 3076 stopped by switch.ps1; its idle PowerShell window (PID 7408) is still open.
Switch script result and automatic rollback, if any: /health ok on the first attempt; no rollback.
  Slot was idle before the switch (switch.ps1 checks /slots is_processing). Log: switch-B.log.
Endpoint and tunnel unchanged: yes. 0.0.0.0:8080 (listener PID 21264), same key file, cloudflared PID 10392
  (started 2026-09-27 03:13:48) untouched, still forwarding to localhost:8080.
Loaded module hashes: unchanged from Handoff 1 (all 11 listed modules loaded by PID 21264, SHA-256 identical).
Model path, size and SHA256: unchanged. ...\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf,
  6,397,970,272 B, 5f212d02ff57cb8eaad260fd7ff57bfaff87ae2bc9183a21dd2f127c27252505 (re-hashed after the switch).
Template and tokenizer digests: unchanged. /props template ac4c9d7d9d7cee2ad2293821512633d12deced846a433b30aff0f02d9e3a312c;
  tokenizer comes from the same (re-hashed) GGUF, digest e084756c... as in Handoff 1.
Build stamp and dirty-build provenance limitation: unchanged. /props build_info b10768-8ecc788d5; same
  dirty-build caveat (source best matched by fork c8b8993a6, not byte-proven).
Exact sanitized command-line delta (from the live process command line):
  removed: --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384
           --spec-draft-n-max-tail 4
  added: nothing. All other arguments identical and in the same order.
GGML_CUDA_BATCH_INVARIANT: 1 (read from PID 21264's environment; the only GGML_*/LLAMA_* variable present)
KV VRAM cells: 113152 (pinned on the command line)
Target KV, context, slots, batch, microbatch, backend sampling: unchanged. q8_0/q8_0, -c 262144, -np 1
  (/slots: 1 slot, n_ctx 262144), -b 2048, -ub 512, --backend-sampling.
Reasoning/force-close settings and remaining environment: unchanged. --reasoning-budget 20480,
  --reasoning-budget-message "Now produce the complete answer.", effort allow/fallback medium,
  --reasoning-max-tokens-floor 24576, --chat-template-kwargs {"reasoning_effort":"medium"}, -n 24576,
  temp 1.0 / top-p 0.95 / top-k 20, --jinja --prio 2 --poll 100 --metrics.
GPU clock/offset state: not verified. nvidia-smi does not expose the memory clock offset; max memory clock
  reads 10501 MHz before and after (not evidence of the offset either way). Display still on the iGPU.
/slots: speculative=false, is_processing=false, n_ctx=262144
Startup evidence for speculation disabled (B.startup-console.txt, key redacted):
  - no "speculative decoding enabled" line (the server prints it at startup whenever a spec context exists;
    tools/server/server-context.cpp:1231)
  - the whole MTP layer is skipped at load: "model has unused tensor blk.64.* -- ignoring" for all 15 blk.64
    tensors (attn_q/k/v/output, ffn_gate/up/down, norms, nextn.eh_proj/enorm/hnorm/shared_head_norm)
  - GPU memory in use: 10,410 MiB under B at idle vs 11,648 MiB under A before the switch. Part of the gap is
    the ~450 MB MTP layer plus the draft context; part is likely pool growth in A's 39-hour-old process.
    Not separated.
/metrics current draft counters (present, all zero on the fresh process):
  spec_decode_num_draft_tokens_total 0, spec_decode_num_accepted_tokens_total 0,
  spec_decode_num_drafts_total 0, tokens_predicted_total 0, requests_processing 0.
  (A just before the switch: draft_tokens 1,990,160, accepted 1,385,680, drafts 991,396, predicted 2,377,180;
  A.metrics-before-switch.txt.) Watch that these stay 0 while tokens_predicted_total rises.
Rollback command available: yes.
  powershell -NoProfile -ExecutionPolicy Bypass -File artifacts\experiments\spec-ab-20260928\switch.ps1 -Arm A
Ready for Codex B trials: yes

CORRECTION to Handoff 1: it said "the MTP weights stay loaded as part of the model" in B. Wrong: without a
speculative type the loader skips the whole blk.64 layer (log above). This is an unavoidable part of turning
speculation off (the weights are only used by the draft path), but it is a larger memory difference than
Handoff 1 stated. Trunk weights and every other tensor load as before.
```

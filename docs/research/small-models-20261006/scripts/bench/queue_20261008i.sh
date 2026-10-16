#!/usr/bin/env bash
# After G1b (queue h): stop queue h before its teacher batteries (by PID), run the 27B edit-call identity check that
# PR #9's hash fix makes possible (12 GB, depth 0, MTP only vs lookup 32, edit items only), then the teacher batteries.
cd "$(dirname "$0")/.." || exit 1
Q=receipts/queue.log
B=../bonsai-2-27b-serve
step() { echo "$(date '+%H:%M') $*" | tee -a "$Q"; }
commit() { git add -A results receipts && git commit -q -m "$1" && git push -q origin master; }
until grep -q "9B-base battery start (queue h)" "$Q"; do sleep 10; done
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'queue_20261008h|battery_teacher' -and \$_.ProcessId -ne \$PID } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue; 'stopped ' + \$_.ProcessId + ' ' + \$_.Name }" | tee -a "$Q"
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
step "issue #7: lookup on/off in an agent session (60k, 30 tools) start"; (cd $B && bash bench/issue7_lookup_ab.sh > logs/issue7_lookup_ab.run.log 2>&1); step "issue #7 lookup A/B exit $?"
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
step "queue i: 27B edit-call identity (PR #9 hash fix, local only) start"
(cd $B && python - <<'PY'
p = "bench/lookup_ab.py"
s = open(p, encoding="utf-8", newline="").read()
old = '        text = (m.get("content") or "") + json.dumps(m.get("tool_calls") or [], sort_keys=True)'
new = ('        calls = [{"name": c.get("function", {}).get("name"), "arguments": c.get("function", {}).get("arguments")}\n'
       '                 for c in (m.get("tool_calls") or [])]\n'
       '        text = (m.get("content") or "") + json.dumps(calls, sort_keys=True)')
nl = "\r\n" if "\r\n" in s else "\n"
assert s.replace("\r\n", "\n").count(old) == 1
s = s.replace("\r\n", "\n").replace(old, new)
open(p, "w", encoding="utf-8", newline="").write(s.replace("\n", nl))
PY
LOOKUP_KINDS=edit bash bench/lookup_ab.sh "e12-mtp:draft-mtp" "e12-mod+mtp-L32:ngram-mod,draft-mtp:--spec-lookup-n-max,32" > logs/edit_identity_12gb.run.log 2>&1
git checkout -- bench/lookup_ab.py
PYTHONUTF8=1 python - <<'PY'
import json, collections
rows = [json.loads(l) for l in open("receipts/lookup_ab.jsonl", encoding="utf-8") if '"e12-' in l]
by = collections.defaultdict(dict)
for r in rows:
    by[r["item"]][r["tag"]] = (r["sha"], r["tps"])
same = sum(1 for d in by.values() if len({v[0] for v in d.values()}) == 1 and len(d) == 2)
print(f"12 GB edit calls, MTP only vs lookup 32, hash without the call id: {same}/{len(by)} identical; {dict(by)}")
PY
) 2>&1 | tail -2 | tee -a "$Q"
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
step "PrismML #330 Ada data start"; (cd $B && bash bench/fa_prefill_f16_ada.sh > logs/fa_prefill_f16_ada.run.log 2>&1); step "PrismML #330 Ada data exit $?"
powershell -NoProfile -ExecutionPolicy Bypass -File $B/bench/stop_serve.ps1 >/dev/null 2>&1
for S in 9B 4B 2B; do step "$S-base battery start (queue i)"; MED_LIMIT=40 bash bench/battery_teacher.sh $S > logs/battery_${S}-base.run.log 2>&1; step "$S-base exit $?"; commit "$S base (teacher) battery results (S2b)"; done
step "queue done"

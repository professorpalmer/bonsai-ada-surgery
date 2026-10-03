"""Host-simulated stateful tool environments with deterministic graders.

No model output is ever executed: tools are pure Python functions over in-memory tables. Each task is
generated from (kind, seed) so instances are reproducible and the grader knows the exact expected state.
"""
import copy
import json
import random
from decimal import Decimal, ROUND_HALF_UP

PAGE = 8

TOOLS = [
    {"type": "function", "function": {
        "name": "list_tables",
        "description": "List the tables in the workspace with their row counts and column names.",
        "parameters": {"type": "object", "properties": {}, "required": []}}},
    {"type": "function", "function": {
        "name": "read_table",
        "description": f"Read one page ({PAGE} rows) of a table, in id order. Pages start at 1.",
        "parameters": {"type": "object", "properties": {
            "table": {"type": "string"}, "page": {"type": "integer"}}, "required": ["table", "page"]}}},
    {"type": "function", "function": {
        "name": "lookup",
        "description": "Fetch one row of a table by its id.",
        "parameters": {"type": "object", "properties": {
            "table": {"type": "string"}, "id": {"type": "string"}}, "required": ["table", "id"]}}},
    {"type": "function", "function": {
        "name": "update_rows",
        "description": "Apply field updates to existing rows of one table in a single batch. Each update is "
                       "{\"id\": ..., \"fields\": {column: new_value}}. Every call is a separate batch job.",
        "parameters": {"type": "object", "properties": {
            "table": {"type": "string"},
            "updates": {"type": "array", "items": {"type": "object", "properties": {
                "id": {"type": "string"}, "fields": {"type": "object"}}, "required": ["id", "fields"]}}},
            "required": ["table", "updates"]}}},
    {"type": "function", "function": {
        "name": "submit_answer",
        "description": "Submit the final answer for the task. Call exactly once, after all changes are made.",
        "parameters": {"type": "object", "properties": {"answer": {"type": "string"}}, "required": ["answer"]}}},
]


def d2(x):
    return str(Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def money(rng, lo, hi):
    return d2(Decimal(rng.randint(lo * 100, hi * 100)) / 100)


class Env:
    def __init__(self, tables, writable, task, expect):
        self.tables = tables          # name -> list of dict rows (each has "id")
        self.initial = copy.deepcopy(tables)
        self.writable = writable      # name -> set of writable columns
        self.task = task
        self.expect = expect          # dict used by the grader
        self.update_calls = []        # (table, n_updates)
        self.answers = []

    def _row(self, table, rid):
        for r in self.tables[table]:
            if r["id"] == rid:
                return r
        return None

    def call(self, name, args):
        try:
            if name == "list_tables":
                return {"tables": [{"name": t, "rows": len(rows), "columns": list(rows[0].keys())}
                                   for t, rows in self.tables.items()]}
            if name == "read_table":
                t = args["table"]
                if t not in self.tables:
                    return {"error": f"no table {t!r}"}
                rows = self.tables[t]
                pages = (len(rows) + PAGE - 1) // PAGE
                p = int(args["page"])
                if p < 1 or p > pages:
                    return {"error": f"page {p} out of range 1..{pages}"}
                return {"table": t, "page": p, "total_pages": pages, "rows": rows[(p - 1) * PAGE:p * PAGE]}
            if name == "lookup":
                t = args["table"]
                if t not in self.tables:
                    return {"error": f"no table {t!r}"}
                r = self._row(t, str(args["id"]))
                return {"row": r} if r else {"error": f"no row {args['id']!r} in {t}"}
            if name == "update_rows":
                t = args["table"]
                if t not in self.tables:
                    return {"error": f"no table {t!r}"}
                ups = args["updates"]
                if not isinstance(ups, list) or not ups:
                    return {"error": "updates must be a non-empty list"}
                for u in ups:   # validate the whole batch first: all or nothing
                    r = self._row(t, str(u.get("id")))
                    if r is None:
                        return {"error": f"no row {u.get('id')!r} in {t}; batch rejected, nothing applied"}
                    for k in (u.get("fields") or {}):
                        if k not in self.writable.get(t, set()):
                            return {"error": f"column {k!r} of {t} is read-only; batch rejected, nothing applied"}
                for u in ups:
                    self._row(t, str(u["id"])).update(u["fields"])
                self.update_calls.append((t, len(ups)))
                return {"ok": True, "batch": len(self.update_calls), "updated": len(ups)}
            if name == "submit_answer":
                self.answers.append(str(args["answer"]))
                return {"ok": True}
            return {"error": f"unknown tool {name!r}"}
        except (KeyError, TypeError, ValueError) as e:
            return {"error": f"bad arguments: {e!r}"}

    def grade(self):
        """Functional correctness, process contract and completion as separate fields."""
        e = self.expect
        changed = {}
        for t, rows in self.tables.items():
            init = {r["id"]: r for r in self.initial[t]}
            for r in rows:
                if r != init[r["id"]]:
                    changed[(t, r["id"])] = {k: v for k, v in r.items() if init[r["id"]].get(k) != v}
        want = {(t, i): f for (t, i), f in e["changes"].items()}
        state_ok = changed == want
        ans = self.answers[-1] if self.answers else None
        answer_ok = None if e.get("answer") is None else (ans is not None and e["norm"](ans) == e["answer"])
        batches = [n for t, n in self.update_calls]
        process_ok = (len(batches) == e["batches"]) if e.get("batches") is not None else True
        functional = state_ok and (answer_ok is not False)
        return {
            "functional": functional, "state_ok": state_ok, "answer_ok": answer_ok, "process_ok": process_ok,
            "submitted": len(self.answers), "update_batches": len(batches),
            "full_pass": functional and process_ok and len(self.answers) == 1,
            "answer": ans, "expected_answer": e.get("answer"),
            "wrong_changes": sorted(f"{t}:{i}" for (t, i) in set(changed) ^ set(want)
                                    if changed.get((t, i)) != want.get((t, i)))[:20],
        }


def norm_money(s):
    s = s.strip().replace("$", "").replace(",", "")
    try:
        return d2(s)
    except Exception:
        return None


def norm_str(s):
    return s.strip().strip('"').strip()


def norm_int(s):
    try:
        return int(s.strip())
    except Exception:
        return None


REGIONS = ["north", "south", "east", "west"]
FIRST = ["Ana", "Bo", "Cy", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kai", "Lu", "Mo", "Ned", "Oz",
         "Pia", "Quin", "Rae", "Sol", "Tia", "Uma", "Vic", "Wes", "Xan", "Yu", "Zed"]
LAST = ["Park", "Reyes", "Okafor", "Lind", "Varga", "Chen", "Moreau", "Sato", "Ilic", "Brandt", "Nunez", "Osei"]


def make_invoice(seed, n_inv=46, n_cust=12):
    rng = random.Random(seed * 7919 + 1)
    customers = []
    for i in range(n_cust):
        customers.append({"id": f"C{i + 1:02d}", "name": f"{rng.choice(FIRST)} {rng.choice(LAST)} Ltd",
                          "region": REGIONS[i % 4] if i < 8 else rng.choice(REGIONS), "tier": rng.choice(["std", "gold"])})
    region = rng.choice(REGIONS)
    cutoff = "2026-06-01"
    invoices, flagged, total = [], {}, Decimal(0)
    for i in range(n_inv):
        c = rng.choice(customers)
        status = rng.choices(["paid", "unpaid", "void"], [5, 4, 1])[0]
        month = rng.randint(3, 8)
        due = f"2026-{month:02d}-{rng.randint(1, 28):02d}"
        amt = money(rng, 40, 4000)
        inv = {"id": f"INV-{1000 + i * 3 + rng.randint(0, 2)}", "customer_id": c["id"], "amount": amt,
               "status": status, "due_date": due}
        invoices.append(inv)
        if c["region"] == region and status == "unpaid" and due < cutoff:
            flagged[("invoices", inv["id"])] = {"status": "flagged"}
            total += Decimal(amt)
    task = (f"Flag every unpaid invoice with a due date strictly before {cutoff} that belongs to a customer in "
            f"the '{region}' region: set its status to \"flagged\". Do all of the flagging in exactly one "
            f"update_rows call (one batch job) that covers every such invoice, and change nothing else. Then "
            f"submit the total amount of the invoices you flagged, as a decimal number with two decimals "
            f"(for example 1234.50).")
    return Env({"customers": customers, "invoices": invoices}, {"invoices": {"status"}}, task,
               {"changes": flagged, "answer": d2(total), "norm": norm_money, "batches": 1 if flagged else 0})


def make_dedupe(seed, n_people=22):
    rng = random.Random(seed * 104729 + 2)
    rows, changes, merged = [], {}, 0
    people = [(rng.choice(FIRST), rng.choice(LAST)) for _ in range(n_people)]
    base = []
    for i, (f, l) in enumerate(people):
        base.append((f"{f.lower()}.{l.lower()}{i}@example.org", f"{f} {l}"))
    entries = []
    for email, name in base:
        n = rng.choices([1, 2, 3], [6, 3, 1])[0]
        for k in range(n):
            e = email
            if k > 0:   # variants: case and surrounding whitespace
                e = rng.choice([email.upper(), " " + email, email.capitalize(), email + " ", email.replace("@", "@").title()])
            entries.append((e, name))
    rng.shuffle(entries)
    for i, (e, name) in enumerate(entries):
        day = rng.randint(1, 360)
        rows.append({"id": f"P{i + 1:03d}", "email": e, "name": name,
                     "created": f"2025-{(day // 30) % 12 + 1:02d}-{day % 28 + 1:02d}T{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}",
                     "status": "active"})
    groups = {}
    for r in rows:
        groups.setdefault(r["email"].strip().lower(), []).append(r)
    for g in groups.values():
        if len(g) > 1:
            g = sorted(g, key=lambda r: (r["created"], r["id"]))
            for r in g[1:]:
                changes[("contacts", r["id"])] = {"status": "merged"}
                merged += 1
    task = ("Some contacts are duplicates: two rows are the same person when their emails are equal after "
            "trimming surrounding whitespace and ignoring letter case. In each duplicate group keep the row with "
            "the earliest 'created' timestamp (ties: the smaller id) and set status to \"merged\" on every other "
            "row of the group. Make all the changes in exactly one update_rows call and change nothing else. "
            "Then submit the number of rows you set to merged.")
    return Env({"contacts": rows}, {"contacts": {"status"}}, task,
               {"changes": changes, "answer": merged, "norm": norm_int, "batches": 1 if changes else 0})


def make_ledger(seed, n_tx=44, chain_rev=False):
    rng = random.Random(seed * 15485863 + 3)
    accounts = [f"ACC-{n}" for n in rng.sample(range(10, 99), 4)]
    target = accounts[0]
    rows, live, dead, live_rev = [], {}, {}, {}
    for i in range(n_tx):
        acc = rng.choice(accounts[:2] if i % 3 else accounts)
        kind = rng.choices(["charge", "refund", "reversal"], [6, 3, 2])[0]
        rid = f"T{i + 1:03d}"
        if kind == "reversal" and chain_rev and rng.random() < 0.35:
            revs = [r for r in rows if r["account"] == acc and r["type"] == "reversal" and r["id"] in live_rev]
            if revs:
                ref = rng.choice(revs)
                rows.append({"id": rid, "account": acc, "type": "reversal", "amount": "0.00", "reverses": ref["id"]})
                live_rev.pop(ref["id"])
                orig = ref["reverses"]
                live[orig] = dead.pop(orig)
                continue
        if kind == "reversal":
            cands = [r for r in rows if r["account"] == acc and r["type"] != "reversal" and r["id"] in live]
            if not cands:
                kind = "charge"
            else:
                ref = rng.choice(cands)
                rows.append({"id": rid, "account": acc, "type": "reversal", "amount": "0.00", "reverses": ref["id"]})
                dead[ref["id"]] = live.pop(ref["id"])
                live_rev[rid] = True
                continue
        amt = money(rng, 5, 900)
        rows.append({"id": rid, "account": acc, "type": kind, "amount": amt, "reverses": ""})
        live[rid] = (acc, kind, Decimal(amt))
    bal = sum((a if k == "charge" else -a) for (acc, k, a) in live.values() if acc == target)
    task = (f"Compute the net balance of account {target} from the transactions table. A charge adds its amount "
            f"and a refund subtracts its amount. A reversal row cancels the transaction named in its 'reverses' "
            f"column completely (as if that transaction never happened); the reversal itself has no amount. "
            + ("A reversal can also name another reversal: reversing a reversal cancels that reversal, so the "
               "transaction it had cancelled counts again. " if chain_rev else "")
            + f"Do not change any data. Submit the balance as a decimal number with two decimals, with a leading "
            f"minus sign if it is negative.")
    return Env({"transactions": rows}, {}, task, {"changes": {}, "answer": d2(bal), "norm": norm_money, "batches": 0})


def make_chain(seed):
    rng = random.Random(seed * 32452843 + 4)
    n = 30
    ids = [f"E{k:03d}" for k in rng.sample(range(100, 999), n)]
    emps = []
    for i, eid in enumerate(ids):
        f, l = rng.choice(FIRST), rng.choice(LAST)
        mgr = "" if i < 3 else ids[rng.randint(0, i - 1)]
        emps.append({"id": eid, "name": f"{f} {l}", "manager_id": mgr, "email": f"{f.lower()}{i}@corp.example",
                     "dept": rng.choice(["ops", "fin", "eng", "legal"])})
    # pick an approver at depth >= 3 so the chain is 3 hops
    byid = {e["id"]: e for e in emps}

    def depth(e):
        d = 0
        while e["manager_id"]:
            e = byid[e["manager_id"]]
            d += 1
        return d
    deep = [e for e in emps if depth(e) >= 3]
    approver = rng.choice(deep)
    orders = []
    target_order = None
    for i in range(24):
        a = approver if i == 11 else rng.choice(emps)
        o = {"id": f"ORD-{5000 + i * 7}", "approved_by": a["id"], "amount": money(rng, 100, 9000)}
        orders.append(o)
        if i == 11:
            target_order = o["id"]
    skip = byid[byid[approver["manager_id"]]["manager_id"]]
    rng.shuffle(emps)
    emps.sort(key=lambda e: e["id"])
    task = (f"Find who approved order {target_order}. Then find that approver's manager's manager (two levels "
            f"up the manager_id chain). Set that skip-level manager's dept to \"review\" (one update_rows call, "
            f"change nothing else), then submit that person's email address.")
    return Env({"orders": orders, "employees": emps}, {"employees": {"dept"}}, task,
               {"changes": {("employees", skip["id"]): {"dept": "review"}}, "answer": skip["email"],
                "norm": norm_str, "batches": 1})


def make_copy(seed):
    rng = random.Random(seed * 49979687 + 5)
    notes = []
    tricky = ["  indented line", "tab\tseparated\tvalues", "trailing spaces   ", "unicode: café — naïve",
              "line sep inside", "quotes \"double\" and 'single'", "backslash \\n literal", "emoji-free µs",
              "", "   ", "NEL\u0085char", "dollar $HOME and %PATH%"]
    for i in range(18):
        k = rng.randint(3, 6)
        body = "\n".join(rng.sample(tricky, k))
        notes.append({"id": f"N{i + 1:02d}", "title": f"note {rng.choice(LAST)} {i}", "body": body, "archived_copy": ""})
    src = rng.randrange(0, 18)
    dst = rng.choice([j for j in range(18) if j != src])
    task = (f"Copy the body of note {notes[src]['id']} exactly, byte for byte (every space, tab, newline and "
            f"special character), into the archived_copy field of note {notes[dst]['id']}. Use one update_rows "
            f"call and change nothing else. Then submit the word done.")
    return Env({"notes": notes}, {"notes": {"archived_copy"}}, task,
               {"changes": {("notes", notes[dst]["id"]): {"archived_copy": notes[src]["body"]}},
                "answer": "done", "norm": lambda s: norm_str(s).lower().rstrip('.'), "batches": 1})


KINDS = {"invoice": make_invoice, "dedupe": make_dedupe, "ledger": make_ledger, "chain": make_chain,
         "copy": make_copy,
         "invoiceH": lambda s: make_invoice(s, n_inv=120, n_cust=30),
         "dedupeH": lambda s: make_dedupe(s, n_people=60),
         "ledgerH": lambda s: make_ledger(s, n_tx=120, chain_rev=True)}


def make(kind, seed):
    return KINDS[kind](seed)


if __name__ == "__main__":
    for k in KINDS:
        for s in range(1, 4):
            e = make(k, s)
            print(k, s, "changes", len(e.expect["changes"]), "answer", e.expect["answer"],
                  {t: len(r) for t, r in e.tables.items()})

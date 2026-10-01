"""Regex-synthesis debug loop: a multi-turn write -> test -> fix task with no model code execution.

The model's pattern is data evaluated by Python's re engine in a subprocess with a timeout (ReDoS guard).
Visible dev examples drive the test tool; grading uses a disjoint hidden set generated from the same spec.
"""
import json
import random
import subprocess
import sys

MAX_CALLS_NOTE = "You may call test_regex as often as you need."

TOOLS = [
    {"type": "function", "function": {
        "name": "test_regex",
        "description": "Test a Python regular expression (matched with re.fullmatch against each example) on the "
                       "development examples. Returns pass counts and up to 4 failing examples of each kind.",
        "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
    {"type": "function", "function": {
        "name": "submit_regex",
        "description": "Submit the final pattern. It is graded with re.fullmatch on a separate hidden set drawn "
                       "from the same specification. Call exactly once.",
        "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
]

_CHILD = r"""
import json, re, sys
d = json.loads(sys.stdin.read())
try:
    rx = re.compile(d["pattern"])
except re.error as e:
    print(json.dumps({"compile_error": str(e)})); sys.exit(0)
print(json.dumps([bool(rx.fullmatch(s)) for s in d["strings"]]))
"""


def evaluate(pattern, strings, timeout=5):
    try:
        p = subprocess.run([sys.executable, "-I", "-c", _CHILD], input=json.dumps({"pattern": pattern, "strings": strings}),
                           capture_output=True, text=True, timeout=timeout, encoding="utf-8")
        return json.loads(p.stdout)
    except subprocess.TimeoutExpired:
        return {"timeout": True}
    except Exception as e:
        return {"error": repr(e)}


def leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


MDAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


def gen_date(rng, n):
    pos, neg = set(), set()
    while len(pos) < n:
        y = rng.randint(2020, 2029); m = rng.randint(1, 12)
        dmax = 29 if (m == 2 and leap(y)) else MDAYS[m - 1]
        d = rng.choice([1, dmax, rng.randint(1, dmax)])
        pos.add(f"{y}-{m:02d}-{d:02d}")
    while len(neg) < n:
        y = rng.randint(2020, 2029); m = rng.randint(1, 12)
        k = rng.randint(0, 6)
        if k == 0:
            s = f"{y}-02-29" if not leap(y) else f"{y}-02-30"
        elif k == 1:
            dmax = MDAYS[m - 1] if m != 2 else (29 if leap(y) else 28)
            s = f"{y}-{m:02d}-{dmax + 1:02d}"
        elif k == 2:
            s = f"{y}-{rng.choice([0, 13, 19]):02d}-{rng.randint(1, 28):02d}"
        elif k == 3:
            s = f"{rng.choice([2019, 2030, 1925, 2120])}-{m:02d}-{rng.randint(1, 28):02d}"
        elif k == 4:
            s = f"{y}-{m}-{rng.randint(1, 9)}"
        elif k == 5:
            s = f"{y}-{m:02d}-00"
        else:
            s = f"{y}/{m:02d}/{rng.randint(10, 28)}"
        neg.add(s)
    return sorted(pos), sorted(neg - pos)


def gen_ipv4(rng, n):
    def octet():
        return str(rng.choice([0, 9, 10, 99, 100, 199, 200, 249, 250, 255, rng.randint(0, 255)]))
    pos, neg = set(), set()
    while len(pos) < n:
        pos.add(".".join(octet() for _ in range(4)))
    while len(neg) < n:
        parts = [octet() for _ in range(4)]
        k = rng.randint(0, 5)
        i = rng.randint(0, 3)
        if k == 0:
            parts[i] = str(rng.choice([256, 260, 300, 999]))
        elif k == 1:
            parts[i] = "0" + str(rng.randint(1, 99))
        elif k == 2:
            parts = parts[:3]
        elif k == 3:
            parts.append(octet())
        elif k == 4:
            parts[i] = ""
        else:
            parts[i] = "00"
        neg.add(".".join(parts))
    return sorted(pos), sorted(neg - pos)


def gen_semver(rng, n):
    def num():
        return str(rng.choice([0, 1, 9, 10, 42, rng.randint(0, 300)]))

    def ident():
        return rng.choice(["alpha", "beta", "rc", "x-y", "0", "7", "a1", "build9"])
    pos, neg = set(), set()
    while len(pos) < n:
        s = f"{num()}.{num()}.{num()}"
        if rng.random() < 0.5:
            s += "-" + ".".join(ident() for _ in range(rng.randint(1, 3)))
        if rng.random() < 0.4:
            s += "+" + ".".join(rng.choice(["001", "sha5", "exp", "20260929", "a-b"]) for _ in range(rng.randint(1, 2)))
        pos.add(s)
    while len(neg) < n:
        k = rng.randint(0, 6)
        if k == 0:
            s = f"0{rng.randint(1, 9)}.{num()}.{num()}"
        elif k == 1:
            s = f"{num()}.{num()}"
        elif k == 2:
            s = f"{num()}.{num()}.{num()}-"
        elif k == 3:
            s = f"{num()}.{num()}.{num()}-alpha..1"
        elif k == 4:
            s = f"{num()}.{num()}.{num()}-0{rng.randint(1, 9)}"
        elif k == 5:
            s = f"v{num()}.{num()}.{num()}"
        else:
            s = f"{num()}.{num()}.{num()}+"
        neg.add(s)
    return sorted(pos), sorted(neg - pos)


def gen_time(rng, n):
    pos, neg = set(), set()
    while len(pos) < n:
        h = rng.choice([0, 9, 12, 19, 20, 23, rng.randint(0, 23)]); m = rng.choice([0, 59, rng.randint(0, 59)])
        s = f"{h:02d}:{m:02d}"
        if rng.random() < 0.5:
            s += f":{rng.choice([0, 59, rng.randint(0, 59)]):02d}"
        if rng.random() < 0.3:
            s += "Z" if rng.random() < 0.5 else rng.choice(["+05:30", "-08:00", "+14:00", "-00:00"])
        pos.add(s)
    while len(neg) < n:
        k = rng.randint(0, 6)
        if k == 0:
            s = f"24:{rng.randint(0, 59):02d}"
        elif k == 1:
            s = f"{rng.randint(0, 23):02d}:60"
        elif k == 2:
            s = f"{rng.randint(0, 9)}:{rng.randint(0, 59):02d}"
        elif k == 3:
            s = f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:61"
        elif k == 4:
            s = f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}+5:30"
        elif k == 5:
            s = f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}z"
        else:
            s = f"{rng.randint(0, 23):02d}{rng.randint(0, 59):02d}"
        neg.add(s)
    return sorted(pos), sorted(neg - pos)


SPECS = {
    "date": ("calendar dates written YYYY-MM-DD for the years 2020 through 2029 inclusive. Months and days are "
             "always two digits, and the day must exist in that month (February has 29 days in leap years "
             "2020, 2024 and 2028, otherwise 28).", gen_date),
    "ipv4": ("dotted-decimal IPv4 addresses: exactly four decimal octets 0-255 separated by dots, with no "
             "leading zeros (a single 0 is allowed, but 00 or 01 are not).", gen_ipv4),
    "semver": ("Semantic Versioning 2.0.0 strings: MAJOR.MINOR.PATCH numbers without leading zeros, an optional "
               "pre-release after '-' made of dot-separated identifiers [0-9A-Za-z-] (numeric identifiers must "
               "not have leading zeros, identifiers must not be empty), and optional build metadata after '+' "
               "made of dot-separated non-empty identifiers [0-9A-Za-z-] (leading zeros allowed there). "
               "No 'v' prefix.", gen_semver),
    "time": ("ISO 8601 times of day: HH:MM or HH:MM:SS in 24-hour form (00-23 hours, 00-59 minutes and seconds), "
             "optionally followed by an uppercase Z or a UTC offset written +HH:MM or -HH:MM (offset hours 00-14, "
             "offset minutes 00-59).", gen_time),
}


class RegexEnv:
    def __init__(self, kind, seed):
        rng = random.Random(hash((kind, seed)) & 0xffffffff if False else seed * 1000003 + len(kind))
        desc, gen = SPECS[kind]
        pos, neg = gen(rng, 60)
        rng.shuffle(pos); rng.shuffle(neg)
        self.dev = [(s, True) for s in pos[:24]] + [(s, False) for s in neg[:24]]
        hp, hn = gen(random.Random(seed * 7777 + 99 + len(kind)), 120)
        devset = set(s for s, _ in self.dev)
        self.hidden = [(s, True) for s in hp if s not in devset] + [(s, False) for s in hn if s not in devset]
        self.task = (f"Write one Python regular expression that matches exactly the {desc} The pattern is used "
                     f"with re.fullmatch, so it must match the whole string. Use test_regex to check it against "
                     f"the development examples and fix it until it passes all of them. {MAX_CALLS_NOTE} Then "
                     f"submit it with submit_regex.")
        self.kind, self.seed = kind, seed
        self.tests, self.submitted = [], []

    def _run(self, pattern, cases):
        r = evaluate(pattern, [s for s, _ in cases])
        if isinstance(r, dict):
            return r, None
        fp = [s for (s, want), got in zip(cases, r) if got and not want]
        fn = [s for (s, want), got in zip(cases, r) if want and not got]
        return None, (fp, fn)

    def call(self, name, args):
        if name not in ("test_regex", "submit_regex"):
            return {"error": f"unknown tool {name!r}"}
        pat = args.get("pattern") if isinstance(args, dict) else None
        if not isinstance(pat, str):
            return {"error": "pattern must be a string"}
        if name == "test_regex":
            err, res = self._run(pat, self.dev)
            self.tests.append(pat)
            if err:
                return err
            fp, fn = res
            n = len(self.dev)
            return {"passed": n - len(fp) - len(fn), "total": n,
                    "should_match_but_did_not": fn[:4], "should_not_match_but_did": fp[:4]}
        self.submitted.append(pat)
        return {"ok": True}

    def grade(self):
        pat = self.submitted[-1] if self.submitted else None
        dev_ok = hid_ok = None
        hidden_fail = None
        if pat is not None:
            e1, r1 = self._run(pat, self.dev)
            e2, r2 = self._run(pat, self.hidden)
            dev_ok = e1 is None and not r1[0] and not r1[1]
            hid_ok = e2 is None and not r2[0] and not r2[1]
            hidden_fail = (e2 if e2 else {"fp": r2[0][:5], "fn": r2[1][:5], "n_fail": len(r2[0]) + len(r2[1])})
        return {"functional": bool(hid_ok), "dev_ok": dev_ok, "state_ok": None, "answer_ok": hid_ok,
                "process_ok": len(self.submitted) == 1, "submitted": len(self.submitted), "tests": len(self.tests),
                "full_pass": bool(hid_ok) and len(self.submitted) == 1, "answer": pat,
                "hidden_fail": hidden_fail, "n_hidden": len(self.hidden)}


if __name__ == "__main__":
    import re
    ref = {
        "ipv4": r"(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)",
        "time": r"(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)?",
        "semver": r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?",
        "date": r"202\d-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\d|30)|02-(?:0[1-9]|1\d|2[0-8]))|202[048]-02-29",
    }
    for k in SPECS:
        for s in (1, 2):
            e = RegexEnv(k, s)
            e.call("submit_regex", {"pattern": ref[k]})
            g = e.grade()
            print(k, s, len(e.dev), len(e.hidden), g["full_pass"], g["hidden_fail"] if not g["full_pass"] else "")

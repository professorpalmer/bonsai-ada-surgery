"""Hard single-turn problems with brute-force integer answers (host computes truth; model code never runs)."""
import heapq
import itertools
import random


def knapsack(seed):
    rng = random.Random(seed * 31 + 1)
    n = 13
    items = [(rng.randint(3, 19), rng.randint(5, 40)) for _ in range(n)]   # (weight, value)
    cap = sum(w for w, _ in items) // 2 - rng.randint(0, 5)
    best = 0
    for mask in range(1 << n):
        w = v = 0
        for i in range(n):
            if mask >> i & 1:
                w += items[i][0]; v += items[i][1]
        if w <= cap and v > best:
            best = v
    lines = "\n".join(f"item {i + 1}: weight {w}, value {v}" for i, (w, v) in enumerate(items))
    q = (f"A knapsack can carry a total weight of at most {cap}. Each item can be taken at most once.\n{lines}\n"
         f"What is the maximum total value that fits?")
    return q, best


def schedule(seed):
    rng = random.Random(seed * 37 + 2)
    n = 8
    dur = [rng.randint(1, 9) for _ in range(n)]
    deps = {i: sorted(rng.sample(range(i), rng.randint(0, min(2, i)))) if i else [] for i in range(n)}
    # 2 identical machines, non-preemptive, list-schedule every priority order -> exact optimum for n=8
    best = None
    for order in itertools.permutations(range(n)):
        pos = {j: k for k, j in enumerate(order)}
        if any(pos[d] > pos[j] for j in range(n) for d in deps[j]):
            continue
        mach = [0, 0]; fin = {}
        for j in order:
            ready = max([fin[d] for d in deps[j]], default=0)
            m = min(range(2), key=lambda k: max(mach[k], ready))
            s = max(mach[m], ready); fin[j] = s + dur[j]; mach[m] = fin[j]
        mk = max(fin.values())
        best = mk if best is None else min(best, mk)
    lines = "\n".join(f"job {chr(65 + j)}: {dur[j]} hours" + (f", can start only after {', '.join(chr(65 + d) for d in deps[j])} finished" if deps[j] else "")
                      for j in range(n))
    q = (f"Two identical workers process 8 jobs. Each job runs on one worker without interruption, a worker does one "
         f"job at a time, and a job can start only when all of its prerequisites have finished.\n{lines}\n"
         f"What is the smallest possible time (in hours) at which all jobs are finished?")
    return q, best


def digits(seed):
    rng = random.Random(seed * 41 + 3)
    N = rng.randint(200000, 999999)
    k = rng.choice([3, 4, 7])
    cnt = 0
    for x in range(1, N + 1):
        s = str(x)
        if sum(map(int, s)) % k == 0 and all(a != b for a, b in zip(s, s[1:])):
            cnt += 1
    q = (f"How many integers x with 1 <= x <= {N} have a decimal digit sum divisible by {k} and no two adjacent "
         f"digits equal?")
    return q, cnt


def paths(seed):
    rng = random.Random(seed * 43 + 4)
    n = 14
    names = [chr(65 + i) for i in range(n)]
    edges = {}
    for i in range(n):
        for j in rng.sample(range(n), 3):
            if i != j:
                edges[(min(i, j), max(i, j))] = rng.randint(1, 30)
    adj = {i: [] for i in range(n)}
    for (a, b), w in edges.items():
        adj[a].append((b, w)); adj[b].append((a, w))
    src, dst = 0, n - 1
    dist = {src: 0}; pq = [(0, src)]; seen = set()
    while pq:
        d, u = heapq.heappop(pq)
        if u in seen:
            continue
        seen.add(u)
        for v, w in adj[u]:
            if d + w < dist.get(v, 1 << 30):
                dist[v] = d + w; heapq.heappush(pq, (d + w, v))
    # count shortest paths too, which makes it harder
    order = sorted(dist, key=dist.get); ways = {src: 1}
    for u in order:
        for v, w in adj[u]:
            if v in dist and dist[u] + w == dist[v]:
                ways[v] = ways.get(v, 0) + ways.get(u, 0)
    lines = ", ".join(f"{names[a]}-{names[b]} {w}" for (a, b), w in sorted(edges.items()))
    q = (f"An undirected weighted graph has these edges (endpoints and length): {lines}.\n"
         f"Let L be the length of the shortest path from {names[src]} to {names[dst]}, and let P be the number of "
         f"distinct shortest paths of length L between them. What is 1000*L + P?")
    return q, 1000 * dist[dst] + ways[dst]


KINDS = {"knapsack": knapsack, "schedule": schedule, "digits": digits, "paths": paths}
SUFFIX = "\n\nWork it out carefully. End your reply with a final line of the form ANSWER: <integer>."


def make(kind, seed):
    q, a = KINDS[kind](seed)
    return q + SUFFIX, a


if __name__ == "__main__":
    for k in KINDS:
        for s in (1, 2):
            q, a = make(k, s)
            print(k, s, a, len(q))


# ---- transfer set (added 02:50, after the H2 plan was frozen; never used in H2 development) ----
def lcs(seed):
    rng = random.Random(seed * 47 + 5)
    a = "".join(rng.choice("ACGT") for _ in range(26))
    b = "".join(rng.choice("ACGT") for _ in range(26))
    dp = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a)):
        for j in range(len(b)):
            dp[i + 1][j + 1] = dp[i][j] + 1 if a[i] == b[j] else max(dp[i][j + 1], dp[i + 1][j])
    # also count distinct LCS strings, which forces a careful second pass
    from functools import lru_cache

    @lru_cache(None)
    def strs(i, j):
        if i == 0 or j == 0:
            return frozenset([""])
        if a[i - 1] == b[j - 1]:
            return frozenset(s + a[i - 1] for s in strs(i - 1, j - 1))
        out = set()
        if dp[i - 1][j] == dp[i][j]:
            out |= strs(i - 1, j)
        if dp[i][j - 1] == dp[i][j]:
            out |= strs(i, j - 1)
        return frozenset(out)
    n = len(strs(len(a), len(b)))
    q = (f"Let X = {a} and Y = {b}. Let L be the length of a longest common subsequence of X and Y, and let "
         f"D be the number of distinct strings that are longest common subsequences. What is 1000*L + D?")
    return q, 1000 * dp[-1][-1] + n


def grid(seed):
    rng = random.Random(seed * 53 + 6)
    n = 9
    blocked = set()
    while len(blocked) < 14:
        c = (rng.randrange(n), rng.randrange(n))
        if c not in ((0, 0), (n - 1, n - 1)):
            blocked.add(c)
    ways = [[0] * n for _ in range(n)]
    for r in range(n):
        for c in range(n):
            if (r, c) in blocked:
                continue
            if r == 0 and c == 0:
                ways[r][c] = 1
                continue
            ways[r][c] = (ways[r - 1][c] if r else 0) + (ways[r][c - 1] if c else 0)
    cells = ", ".join(f"(row {r + 1}, col {c + 1})" for r, c in sorted(blocked))
    q = (f"A robot walks on a {n}x{n} grid from the top-left cell (row 1, col 1) to the bottom-right cell "
         f"(row {n}, col {n}), moving only one cell down or one cell right at each step. These cells are blocked "
         f"and cannot be entered: {cells}. How many different paths are there?")
    return q, ways[n - 1][n - 1]


KINDS.update({"lcs": lcs, "grid": grid})


# ---- second transfer family (added 05:35 after the LCS floor effect; never used in development) ----
def subsets(seed):
    rng = random.Random(seed * 59 + 7)
    nums = sorted(rng.sample(range(2, 40), 12))
    target = sum(nums) // 3 + rng.randint(-3, 3)
    cnt = sum(1 for mask in range(1 << 12) if sum(nums[i] for i in range(12) if mask >> i & 1) == target)
    q = (f"How many subsets of the set {{{', '.join(map(str, nums))}}} have elements that sum to exactly {target}? "
         f"(Each number can be used at most once; the order of elements does not matter.)")
    return q, cnt


KINDS.update({"subsets": subsets})


# ---- realistic data-in-prompt questions (E5, added 2026-09-30 night; never used before) ----
def sales(seed):
    from decimal import Decimal
    rng = random.Random(seed * 61 + 8)
    regions = ["North", "South", "East", "West"]
    products = ["Anvil", "Bracket", "Cable", "Dynamo", "Emitter", "Flange"]
    rows = []
    for i in range(rng.randint(150, 200)):
        m = rng.randint(1, 12); d = rng.randint(1, 28)
        rows.append((f"O{1000 + i}", f"2026-{m:02d}-{d:02d}", rng.choice(regions), rng.choice(products),
                     rng.randint(1, 40), Decimal(rng.randint(199, 9999)) / 100))
    csv = "order_id,date,region,product,qty,unit_price\n" + "\n".join(
        f"{o},{dt},{r},{p},{q},{u:.2f}" for o, dt, r, p, q, u in rows)
    kind = seed % 3
    reg = rng.choice(regions); prod = rng.choice(products)
    if kind == 0:
        tot = sum(q * u for o, dt, r, p, q, u in rows if r == reg and "2026-04" <= dt[:7] <= "2026-06")
        q = f"What is the total revenue (qty times unit_price) of {reg} orders dated April through June 2026, in cents (an integer)?"
        a = int(tot * 100)
    elif kind == 1:
        by = {}
        for o, dt, r, p, qq, u in rows:
            if r != reg:
                by[p] = by.get(p, 0) + qq * u
        best = max(by.values())
        q = (f"Excluding the {reg} region, compute each product's total revenue (qty times unit_price). What is the "
             f"highest product total, in cents (an integer)?")
        a = int(best * 100)
    else:
        n = sum(1 for o, dt, r, p, qq, u in rows if p == prod and qq * u > 500 and dt[5:7] in ("01", "03", "05", "07", "09", "11"))
        q = (f"How many {prod} orders in odd-numbered months (January, March, May, July, September, November) have "
             f"revenue (qty times unit_price) strictly above 500.00?")
        a = n
    return f"Here is a sales table in CSV:\n\n{csv}\n\n{q}", a


KINDS.update({"sales": sales})


# ---- web access-log questions (E7, added 2026-10-01 night; never used before) ----
def weblog(seed):
    rng = random.Random(seed * 67 + 9)
    paths = ["/api/orders", "/api/users", "/api/search", "/static/app.js", "/login", "/health"]
    lines = []
    for i in range(rng.randint(160, 220)):
        ip = f"10.{rng.choice([1, 2, 3])}.{rng.randint(0, 9)}.{rng.randint(1, 254)}"
        hh, mm, ss = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
        p = rng.choice(paths)
        st = rng.choices([200, 201, 304, 400, 404, 500, 502, 503], [50, 5, 8, 6, 8, 5, 3, 3])[0]
        b = rng.randint(0, 50000)
        lines.append((ip, hh, mm, ss, p, st, b))
    lines.sort(key=lambda x: (x[1], x[2], x[3]))
    text = "\n".join(f'{ip} - - [01/Oct/2026:{hh:02d}:{mm:02d}:{ss:02d} +0000] "GET {p} HTTP/1.1" {st} {b}'
                     for ip, hh, mm, ss, p, st, b in lines)
    k = seed % 3
    if k == 0:
        lo = rng.randint(6, 14); hi = lo + rng.randint(4, 8)
        a = sum(1 for ip, hh, mm, ss, p, st, b in lines if p.startswith("/api/") and 500 <= st <= 599 and lo <= hh < hi)
        q = f"How many requests to paths starting with /api/ returned a 5xx status between {lo:02d}:00:00 (inclusive) and {hi:02d}:00:00 (exclusive)?"
    elif k == 1:
        net = rng.choice([1, 2, 3])
        a = sum(b for ip, hh, mm, ss, p, st, b in lines if ip.startswith(f"10.{net}.") and st in (200, 201))
        q = f"What is the total number of bytes sent (last field) for requests from the 10.{net}.0.0/16 network with status 200 or 201?"
    else:
        a = sum(1 for ip, hh, mm, ss, p, st, b in lines if st >= 400 and b > 25000)
        q = "How many requests returned a status of 400 or higher and sent more than 25000 bytes (last field)?"
    return f"Here is a web server access log:\n\n{text}\n\n{q}", a


KINDS.update({"weblog": weblog})

"""The word-count answer for a count in the thinking (arm K2 of no-count-20261022).

When the thinking starts to count words one by one ("Count: Many1 people2 dream3 ...", often on the same line as the
paragraph it counts), the model wants a number. count_start finds where the count starts while it streams: a run of 4
numbered words, or its "Count:" label on the same line. answer() gives the number in the model's own format, from the
paragraph just before it: "Count: 60 words. Draft so far: 520 words." The thinking then goes on from there, open."""
import re

NUMRUN = re.compile(r"(\b[A-Za-z'][\w'-]*\(?\d{1,4}\)?(?![\w])[^\n\w]{0,4}){4}")
LABEL_BEFORE = re.compile(r"(\(?\b(word\s+)?count(ing)?\b|let me count|let's count)\W{0,4}$", re.I)
QUOTED = re.compile(r"[\"“]([^\"”]{20,})[\"”]")
LABEL = re.compile(r"^\s*([A-Za-z][\w ()~,-]{0,40}|P\d+|Para\s*\d+):\s*", re.I)
WORD = re.compile(r"\b[\w'-]+\b")
DONE_MARK = " words. Draft so far: "


def count_start(text, start=0):
    """Index (at or after start) where a count starts, or None."""
    m = NUMRUN.search(text, start)
    if not m:
        return None
    i = m.start()
    line_start = text.rfind("\n", 0, i) + 1
    lb = LABEL_BEFORE.search(text[max(line_start, i - 40):i])
    return max(line_start, i - 40) + lb.start() if lb else i


def counted_segment(before):
    """The paragraph the model was about to count: back to the last blank line or the last answered count."""
    b = before.rstrip()
    cut = max(b.rfind("\n\n"), b.rfind(DONE_MARK))
    seg = b[cut:] if cut >= 0 else b
    if seg.startswith(DONE_MARK):
        seg = seg.split("words.", 1)[-1]
    quoted = QUOTED.findall(seg)
    if quoted:
        return " ".join(quoted)
    return " ".join(LABEL.sub("", l) for l in seg.split("\n"))


def words(text):
    return len(WORD.findall(text or ""))


def answer(before, so_far):
    """(the inserted text, the new draft-so-far total)."""
    n = words(counted_segment(before))
    total = so_far + n
    return f"Count: {n}{DONE_MARK}{total} words.", total

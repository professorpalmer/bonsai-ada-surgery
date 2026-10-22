"""Where does the draft start in a thinking text? draft_start(text) -> character index of the first draft paragraph, or
None. The rules are late on purpose: a late cut wastes a few draft sentences, an early cut loses the plan.
A draft paragraph is the text itself, not a plan of it:
  - counting: a word-count run ("He1 did2 not3 ...": the model counts the words of its draft);
  - labelled draft: "Paragraph 1 (...): <30+ words of text>", "P1: ...", "Para1: ...";
  - prose: 60+ words, no planning word in its first 12 words, no "label:" at its start, fewer than 1 planning word per
    40 words, not a list item;
  - a heading or title line (Markdown heading, a bold line alone, "Chapter One", "Title: ...") counts only when the
    next paragraph is a draft paragraph by the rules above (a title alone is often still planning).
Used by arm C of docs/research/write-once-20261022."""
import re

HEADING = re.compile(r"^(#{1,4}\s+\S.*|\*\*[^*\n]{2,90}\*\*\s*|chapter\s+(\d+|[a-z]+)\b.*|title\s*:.*)$", re.I)
COUNTING = re.compile(r"(\b[A-Za-z'][\w'-]*\d{1,4}\b[^\n]{0,4}){6,}")
LABELLED = re.compile(r"^(paragraph|para|p)\s*\d+\b[^:\n]{0,60}:\s*\S", re.I)
LIST = re.compile(r"^\s*([-*•]|\d+[.)]|[a-z][.)])\s")
LABEL_START = re.compile(r"^[^\n:]{1,40}:(\s|$)")
PLAN_WORDS = re.compile(r"\b(let me|let's|i'll|i will|i should|i need|i want|i can|i think|maybe|perhaps|the user|the reader|"
                        r"the story|the essay|the poem|the post|the chapter|plan|outline|draft|idea|theme|scene|structure|"
                        r"tone|arc|hook|word count|words?|paragraphs?|section|should|could|would be|option|actually|wait|"
                        r"hmm|okay|ok|alternatively|request|requirement|protagonist|character|setting|plot|ending|opening|"
                        r"title|premise|concept|need|aim|target|go with)\b", re.I)
WORD = re.compile(r"[A-Za-z'][\w'-]*")


def _paragraphs(text):
    out, i = [], 0
    for m in re.finditer(r"\n\s*\n", text + "\n\n"):
        block = text[i:m.start()]
        if block.strip():
            out.append((i + len(block) - len(block.lstrip()), block.strip()))
        i = m.end()
    return out


def _prose(par):
    first = par.split("\n", 1)[0]
    if LIST.match(first) or LABEL_START.match(first):
        return False
    words = WORD.findall(par)
    if len(words) < 60:
        return False
    if PLAN_WORDS.search(" ".join(words[:12])):
        return False
    return len(PLAN_WORDS.findall(par)) * 40 < len(words)


def _body_draft(par):
    if COUNTING.search(par):
        return "counting"
    first = par.split("\n", 1)[0]
    if LABELLED.match(first) and len(WORD.findall(par)) >= 30:
        return "labelled"
    if _prose(par):
        return "prose"
    return None


def _scan(text):
    pars = _paragraphs(text)
    for k, (i, par) in enumerate(pars):
        kind = _body_draft(par)
        if kind:
            return i, kind
        first = par.split("\n", 1)[0].strip()
        if HEADING.match(first) and len(first) < 100:
            rest = par[len(first):].strip()
            nxt = rest or (pars[k + 1][1] if k + 1 < len(pars) else "")
            if nxt and _body_draft(nxt):
                return i, "heading"
    return None, None


def draft_start(text):
    return _scan(text)[0]


def draft_kind(text):
    return _scan(text)[1]

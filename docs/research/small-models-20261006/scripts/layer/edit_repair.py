"""Edit-call repair: make a model's edit call apply when its old text differs from the file only in indentation.

Agent edit tools (Pi `edit`, Claude-style `str_replace`, Cline `replace_in_file` and others) take an old text and a
new text and reject the call unless the old text occurs in the file exactly once. Small models copy the lines they
want to change correctly but shift their indentation (Dogukan's PatchEval traces: 34% of the 9B's edit calls fail;
our exact-copy probe shows the same shape). The file text is usually already in the conversation, as the result of
a read call. This module finds the one place in that text whose lines equal the model's old lines once leading and
trailing whitespace is ignored, replaces the old text with the exact lines from the file, and moves the new text by
the same indentation. It changes nothing when the old text is already exact, when no place matches, or when more
than one place matches.
"""
import json
import re

OLD_KEYS = ("oldText", "old_text", "old_string", "old_str", "search", "find")
NEW_KEYS = ("newText", "new_text", "new_string", "new_str", "replace", "replacement")
_NUMBERED = re.compile(r"^\s*\d+(?:\t|\s*[|:→] ?)")   # "  12\t", "12 | ", "12: ", "12→"


def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


def _variants(text):
    """The text, and the same text without line-number prefixes when most of its lines have them."""
    out = [text]
    lines = text.split("\n")
    numbered = [l for l in lines if _NUMBERED.match(l)]
    if lines and len(numbered) >= 0.8 * len([l for l in lines if l.strip()]):
        out.append("\n".join(_NUMBERED.sub("", l, count=1) for l in lines))
    return out


def find_unique(old, sources):
    """The exact source lines for `old` (match ignoring leading/trailing whitespace per line), or None."""
    o = old.split("\n")
    while o and not o[-1].strip():
        o.pop()
    while o and not o[0].strip():
        o.pop(0)
    if not o:
        return None
    key = [l.strip() for l in o]
    found = set()
    for src in sources:
        for text in _variants(src):
            lines = text.split("\n")
            for i in range(len(lines) - len(o) + 1):
                if lines[i].strip() == key[0] and all(lines[i + k].strip() == key[k] for k in range(1, len(o))):
                    found.add("\n".join(lines[i:i + len(o)]))
                    if len(found) > 1:
                        return None
    if len(found) != 1:
        return None
    fixed = found.pop()
    # the window must also be unique inside the text it came from, or the tool rejects it anyway
    for src in sources:
        for text in _variants(src):
            if text.count(fixed) > 1:
                return None
    return fixed


def _shift(line, delta):
    if not line.strip() or delta == 0:
        return line
    if delta > 0:
        return " " * delta + line
    cut = min(-delta, _indent(line))
    return line[cut:]


def repair_pair(old, new, sources):
    """(old, new, info). info["repaired"] is True when the pair changed."""
    if not old or any(old in t for s in sources for t in _variants(s)):
        return old, new, {"repaired": False, "reason": "exact"}
    fixed = find_unique(old, sources)
    if fixed is None:
        return old, new, {"repaired": False, "reason": "no_unique_match"}
    o_lines = [l for l in old.split("\n")]
    f_lines = fixed.split("\n")
    # pair each non-blank model line with its file line, in order; record the indentation difference
    om = [l for l in o_lines if l.strip()]
    fm = [l for l in f_lines if l.strip()]
    deltas = {l.strip(): _indent(f) - _indent(l) for l, f in zip(om, fm)}
    first = _indent(fm[0]) - _indent(om[0])
    delta, out = first, []
    for line in new.split("\n"):
        delta = deltas.get(line.strip(), delta) if line.strip() else delta
        out.append(_shift(line, delta))
    new_fixed = "\n".join(out)
    if old.endswith("\n") and not fixed.endswith("\n"):
        fixed += "\n"
    return fixed, new_fixed, {"repaired": True, "reason": "indent", "delta_first": first}


def conversation_sources(messages):
    """Texts a client has shown the model: tool results, and user messages (some agents paste files there)."""
    out = []
    for m in messages:
        c = m.get("content")
        if isinstance(c, list):
            c = "\n".join(p.get("text", "") for p in c if isinstance(p, dict))
        if isinstance(c, str) and c and m.get("role") in ("tool", "user", "function"):
            out.append(c)
    return out


def repair_tool_call(call, sources):
    """Repair one OpenAI tool call dict in place. Returns info or None when the call has no old/new pair."""
    fn = call.get("function") or {}
    try:
        args = json.loads(fn.get("arguments") or "{}")
    except Exception:
        return None
    if not isinstance(args, dict):
        return None
    ok = next((k for k in OLD_KEYS if isinstance(args.get(k), str)), None)
    nk = next((k for k in NEW_KEYS if isinstance(args.get(k), str)), None)
    if not ok or not nk:
        return None
    old, new, info = repair_pair(args[ok], args[nk], sources)
    if info["repaired"]:
        args[ok], args[nk] = old, new
        fn["arguments"] = json.dumps(args, ensure_ascii=False)
    info["tool"] = fn.get("name")
    return info


class StreamRepair:
    """Edit-call repair for a streamed (SSE) chat completion. The tool-call deltas are held back and each call is sent
    once, repaired, in one chunk just before the chunk that finishes the choice; every other delta (content, reasoning)
    passes through as it arrives. Feed it the stream line by line (text without the line end); it returns the lines to
    send. The clients that we know take a whole tool call in one delta, as the OpenAI stream format allows."""

    def __init__(self, sources):
        self.sources = sources
        self.calls = {}
        self.order = []
        self.last = None
        self.infos = []

    def _flush(self):
        if not self.calls:
            return []
        tcs = []
        for i in self.order:
            c = self.calls[i]
            call = {"id": c["id"], "type": c["type"], "function": {"name": c["name"], "arguments": c["arguments"]}}
            info = repair_tool_call(call, self.sources)
            if info:
                self.infos.append(info)
            tcs.append(dict(call, index=i))
        ev = dict(self.last or {})
        ev["choices"] = [{"index": 0, "delta": {"tool_calls": tcs}, "finish_reason": None}]
        self.calls, self.order = {}, []
        return ["data: " + json.dumps(ev, ensure_ascii=False), ""]

    def feed(self, line):
        if not line.startswith("data:"):
            return [line]
        payload = line[5:].strip()
        if payload == "[DONE]":
            return self._flush() + [line]
        try:
            ev = json.loads(payload)
        except Exception:
            return [line]
        choices = ev.get("choices") or []
        if not choices or not isinstance(choices[0], dict):
            return [line]
        ch = choices[0]
        delta = ch.get("delta") or {}
        tcs = delta.get("tool_calls")
        if not tcs:
            if ch.get("finish_reason") is not None:
                return self._flush() + [line]
            return [line]
        self.last = {k: v for k, v in ev.items() if k != "choices"}
        for tc in tcs:
            i = tc.get("index", 0)
            c = self.calls.get(i)
            if c is None:
                c = self.calls[i] = {"id": tc.get("id"), "type": tc.get("type") or "function", "name": "", "arguments": ""}
                self.order.append(i)
            if tc.get("id"):
                c["id"] = tc["id"]
            fn = tc.get("function") or {}
            c["name"] += fn.get("name") or ""
            c["arguments"] += fn.get("arguments") or ""
        rest = {k: v for k, v in delta.items() if k != "tool_calls"}
        out = []
        if ch.get("finish_reason") is not None:
            out += self._flush()
        if ch.get("finish_reason") is not None or any(v for k, v in rest.items() if k != "role"):
            ev2 = dict(ev)
            ev2["choices"] = [dict(ch, delta=rest)] + choices[1:]
            out.append("data: " + json.dumps(ev2, ensure_ascii=False))
        return out

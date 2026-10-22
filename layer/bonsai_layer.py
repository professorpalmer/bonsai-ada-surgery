"""Built-in code interpreter for the Bonsai server: an OpenAI-compatible proxy in front of llama-server.

  client --> layer (public port) --> llama-server (127.0.0.1, inner port)

For /v1/chat/completions requests the proxy offers the model a `run_python` tool. When the model calls it,
the proxy runs the code in CPython-on-WASI (layer/wasi-python/sandbox.py: no host files, no network, no
processes, memory and time capped), appends the result, and asks the model again, until the model answers or
calls one of the client's own tools. The client sees one ordinary response.

  - default: on for requests WITHOUT client tools, off (pure passthrough) for requests that bring their own tools
    (E4: with client tools the model retypes paginated tool data into code and transcription errors cost tasks)
  - per request: "code_interpreter": true / false overrides the default
  - with the interpreter on and client tools present, client tool calls are returned as usual
  - the model's reasoning is kept on the internal turns (the server's template renders it)
  - the internal transcript is attached as "interpreter_trace" (runs, exit codes) for auditing
  - streaming requests get the same loop: reasoning and answer tokens are relayed as they arrive, the
    run_python calls are withheld and executed, and the stream continues with the next round
Everything else (other paths, auth header) is forwarded verbatim.
"""
import argparse
import hashlib
import hmac
import http.server
import json
import os
import queue
import re
import socket
import sys
import threading
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sandbox_path  # noqa: E402,F401
import sandbox  # noqa: E402
import apicards_v2 as apicards  # noqa: E402  (E9b: v2 docstring cards adopted)
import apilint  # noqa: E402
import slot_cache  # noqa: E402  (#138 T1-c: saved conversations on disk)

CACHE_N = re.compile(rb'"cache_n"\s*:\s*(\d+)')
TOOL_NAME = "run_python"
TOOL = {"type": "function", "function": {
    "name": TOOL_NAME,
    "description": "Run a Python 3.12 program in an isolated sandbox (standard library only, no network, no "
                   "files outside its working directory, 10 second limit). Use it for exact computation, "
                   "counting, search or checking a result. Returns exit code, stdout and stderr.",
    "parameters": {"type": "object", "properties": {
        "code": {"type": "string", "description": "the complete program; print the results"},
        "stdin": {"type": "string", "description": "optional standard input"}}, "required": ["code"]}}}
INPUT_FILE = "input.txt"
INPUT_NOTE = (" The full text of the user's messages in this conversation is in the file " + INPUT_FILE +
              " in the working directory: read the data from there instead of retyping it.")


def tool_spec(with_input):
    if not with_input:
        return TOOL
    t = json.loads(json.dumps(TOOL))
    t["function"]["description"] += INPUT_NOTE
    return t


NO_VISION_NOTE = ("[An image was here. This server runs without a vision model (no mmproj), so the image is not shown "
                  "to you. If you need what it shows, ask the user to describe it in text.]")


def strip_images(obj):
    """Replace every image part (chat: "image_url"; Responses: "input_image") with a text note, in place. A server
    without a vision projector refuses any request with an image (HTTP 500), and a client that sends the whole
    conversation again then fails on every later turn too (issue #7: a tool returned a screenshot). Returns the count."""
    n = 0

    def walk(x):
        nonlocal n
        if isinstance(x, list):
            for i, p in enumerate(x):
                if isinstance(p, dict) and p.get("type") in ("image_url", "input_image"):
                    x[i] = {"type": "input_text" if p["type"] == "input_image" else "text", "text": NO_VISION_NOTE}
                    n += 1
                else:
                    walk(p)
        elif isinstance(x, dict):
            for v in x.values():
                walk(v)
    walk(obj)
    return n


REASONING_KEYS = ("reasoning_content", "reasoning", "thinking")


def _part_hash(obj):
    return hashlib.sha1(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode("utf-8", "replace")).hexdigest()


def _preserves_reasoning(body):
    """The Bonsai template renders the reasoning of every earlier assistant turn unless the request sets
    preserve_thinking (or preserve_reasoning) to false; the launcher leaves the server at the template default."""
    kw = body.get("chat_template_kwargs") or {}
    return not any(kw.get(k) is False for k in ("preserve_thinking", "preserve_reasoning"))


def prompt_summary(body):
    """The parts of a chat request in the order the chat template renders them (the leading system messages, the tool
    list, then the other messages), each as (label, hash, reasoning hash), and a hash for each tool by name. The
    reasoning hash is None when the template does not render earlier reasoning (preserve_thinking false)."""
    msgs = body.get("messages") or []
    keep = _preserves_reasoning(body)
    lead = 0
    while lead < len(msgs) and isinstance(msgs[lead], dict) and msgs[lead].get("role") in ("system", "developer"):
        lead += 1

    def part(i):
        m = msgs[i]
        if isinstance(m, dict):
            r = {k: m[k] for k in REASONING_KEYS if m.get(k)}
            return ("message %d (%s)" % (i, m.get("role")),
                    _part_hash({k: v for k, v in m.items() if k not in REASONING_KEYS}), _part_hash(r) if keep else None)
        return ("message %d" % i, _part_hash(m), None)
    tools = body.get("tools") or []
    names = {}
    for k, t in enumerate(tools):
        f = (t.get("function") or {}) if isinstance(t, dict) else {}
        name = f.get("name") or (t.get("name") if isinstance(t, dict) else None) or "tool %d" % k
        names[str(name)] = _part_hash(t)
    parts = ([part(i) for i in range(lead)] + [("the tool list", _part_hash(tools), None)]
             + [part(i) for i in range(lead, len(msgs))])
    return {"parts": parts, "tools": names}


def _names(xs, most=8):
    xs = sorted(xs)
    return ", ".join(xs[:most]) + (" and %d more" % (len(xs) - most) if len(xs) > most else "")


def prefix_change(prev, cur):
    """Where a chat request stops repeating the previous one, as text; None when it repeats all of the previous request
    (a new turn only adds at the end) or there is no previous request. A change at part k makes the server read the
    prompt again from that part (issue #7: a changed tool list made a 200k conversation read again, 6 minutes)."""
    if not prev:
        return None
    p, c = prev["parts"], cur["parts"]
    for i, (label, h, rh) in enumerate(p):
        if i >= len(c):
            return "the request has fewer parts (%d) than the previous one (%d); it ends before %s" % (len(c), len(p), label)
        if c[i][1] == h:
            if rh is None or c[i][2] is None or c[i][2] == rh:
                continue
            return ("the reasoning of %s changed or was left out (the template renders the reasoning of earlier turns; "
                    "a client that sends it back unchanged keeps the cache)" % label)
        if label == "the tool list" and c[i][0] == label:
            a, b = prev["tools"], cur["tools"]
            what = []
            if set(b) - set(a):
                what.append("added " + _names(set(b) - set(a)))
            if set(a) - set(b):
                what.append("removed " + _names(set(a) - set(b)))
            changed = [n for n in set(a) & set(b) if a[n] != b[n]]
            if changed:
                what.append("changed " + _names(changed))
            if not what:
                what.append("the same tools in another order")
            return "the tool list changed (%s)" % "; ".join(what)
        if label != c[i][0]:
            return "%s is now %s" % (label, c[i][0])
        return "%s changed (%d of %d parts the same before it)" % (label, i, len(p))
    return None


def client_runs_code(msgs):
    """A conversation that already carries fenced code blocks and offers no tools is a client that executes code
    itself (ReAct-style code agents, notebooks, IDE loops). Measured (AW1, AppWorld): offering run_python to such a
    client made the model run its code in OUR sandbox, where the client's objects do not exist, and the agent's
    success rate fell from 65% to 20%. Such requests pass through untouched."""
    for m in msgs:
        c = m.get("content")
        if isinstance(c, list):
            c = " ".join(x.get("text", "") for x in c if isinstance(x, dict))
        if isinstance(c, str) and "```" in c:
            return True
    return False


def user_text(msgs):
    """The user's own words (string contents of user messages), for the sandbox input file."""
    parts = []
    for m in msgs:
        if m.get("role") == "user":
            c = m.get("content")
            if isinstance(c, str):
                parts.append(c)
            elif isinstance(c, list):
                parts.extend(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
    return (chr(10) + chr(10)).join(parts)


FINAL_REASON = ("The code tool is no longer available. The numeric exploration above did not settle the problem, so set "
                "it aside: reason the problem through from first principles, check the result against anything above "
                "that is reliable, and then give your final answer in the format the original request asked for.")
FINAL_NUDGE = ("The code tool is no longer available. Using the results you already have, give your final answer "
               "now, in the format the original request asked for.")


def run_tool(args_json, timeout, extra_files=None):
    try:
        args = json.loads(args_json) if isinstance(args_json, str) else args_json
        files = dict(extra_files or {})
        files["main.py"] = args.get("code", "")
        r = sandbox.run(files, ["/work/main.py"], stdin=(args.get("stdin") or "").encode("utf-8"), timeout=timeout)
        return {"exit_code": r["exit_code"], "timed_out": r["timed_out"], "code_chars": len(args.get("code", "") or ""),
                "code": (args.get("code", "") or "")[:20000],   # kept in the trace so a response is auditable on its own
                "stdout": r["stdout"][:12000].decode("utf-8", "replace"),
                "stderr": r["stderr"][-4000:].decode("utf-8", "replace")}
    except Exception as e:  # malformed arguments are reported to the model, never raised
        return {"error": f"tool call rejected: {e!r}"[:500]}



def apply_lint(msgs):
    """Check Python code in the model's earlier tool calls against the real runtime and append any findings to the
    matching tool result. Deterministic for a given history, so the rendered prefix stays stable across turns."""
    findings = {}
    for m in msgs:
        if m.get("role") != "assistant":
            continue
        for c in m.get("tool_calls") or []:
            try:
                args = json.loads(c["function"]["arguments"]) if isinstance(c["function"]["arguments"], str)                     else c["function"]["arguments"]
            except (ValueError, KeyError, TypeError):
                continue
            if not isinstance(args, dict):
                continue
            name = next((v for k, v in args.items() if k in ("path", "file", "filename", "file_path") and isinstance(v, str)), "")
            for k, v in args.items():
                if apilint.looks_like_python(name if k != "path" else "", v) and k not in ("path", "file", "filename", "file_path"):
                    w = apilint.lint(v)
                    if w:
                        findings[c.get("id", "")] = apilint.format_warnings(w)
    if not findings:
        return msgs, 0
    out, n = [], 0
    for m in msgs:
        if m.get("role") == "tool" and m.get("tool_call_id") in findings and isinstance(m.get("content"), str)                 and "[API check by the server" not in m["content"]:
            m = dict(m, content=m["content"] + chr(10) + findings[m["tool_call_id"]])
            n += 1
        out.append(m)
    return out, n


PREFER = ("Use the library functions listed above instead of implementing these formats or algorithms by hand; "
          "they already implement them correctly.")


REPAIR_NOTE = ("[Server note: this run failed. Before your next tool call, reason step by step about the exact cause "
               "shown above and check that your change fixes it.]")


def tool_failed(content):
    """A run_python / run-style tool result that reports failure (exit code, timeout or a traceback)."""
    try:
        o = json.loads(content)
    except (TypeError, ValueError):
        return False
    if not isinstance(o, dict):
        return False
    if o.get("timed_out") or (isinstance(o.get("exit_code"), int) and o["exit_code"] != 0):
        return True
    return "Traceback (most recent call last)" in str(o.get("stderr") or "")


def apply_repair_note(msgs):
    """E14: append one fixed sentence to every failing tool result. Measured problem: after a failing test the model
    reasons a median of ~300 characters before its next step (bundle traces). Deterministic for a given history."""
    out, n = [], 0
    for m in msgs:
        if (m.get("role") == "tool" and isinstance(m.get("content"), str) and REPAIR_NOTE not in m["content"]
                and tool_failed(m["content"])):
            m = dict(m, content=m["content"] + chr(10) + REPAIR_NOTE)
            n += 1
        out.append(m)
    return out, n


# A request that asks for code: a fenced block, a function definition, a .py file name, or a verb like write/fix/create
# near a noun like program/function/module/solution. Matches every suite coding prompt; not chat turns about code.
CODE_TASK_RE = re.compile(r"```|\bdef \w+\(|\w\.py\b|\b(write|implement|fix|debug|refactor|complete|build|create)\b"
                          r"[^.\n]{0,80}?\b(code|program|function|script|module|solution|class|tests?|parser|library|cli|tool|app)\b", re.I)
# A request for prose or verse: a story, poem, chapter, essay, article, letter... Measured
# (docs/research/story-think-20261021, G5): offered run_python, the model counts the words of its text in the sandbox,
# up to 5 rounds (a 1,500-word story: 341 s and 33,793 tokens against 61 s without the tool), with no quality gain.
WRITING_RE = re.compile(r"\b(write|compose|draft|create|generate|produce)\b[^.\n]{0,60}?\b(story|stories|poem|poems|"
                        r"poetry|chapter|chapters|novel|novella|essay|blog post|article|letter|lyrics|song|speech|fable|"
                        r"tale|haiku|sonnet|limerick|screenplay|monologue|eulogy)\b"
                        r"|\btell\b[^.\n]{0,30}?\b(story|stories|tale|fable)\b", re.I)
# Counting and data words keep the tool: "how many times the letter r appears", "a letter frequency table",
# "word counts", "grades". Without the tool the model gives such answers wrong and sure (review of #227).
DATA_RE = re.compile(r"\b(count|counts|counting|how many|frequency|frequencies|table|sort|sorted|average|mean|median|sum|"
                     r"total|statistics|grade|grades|percent|percentage|calculate|compute)\b", re.I)
WRITING_HEAD = 300   # only the instruction part: a pasted article or CSV after it must not decide


def _text_of(c):
    if isinstance(c, list):
        return " ".join(x.get("text", "") for x in c if isinstance(x, dict))
    return c if isinstance(c, str) else None


def writing_text(c):
    """A message text that asks for prose or verse and not for code (the first WRITING_HEAD characters decide)."""
    if not isinstance(c, str):
        return False
    c = c.replace(APPROX_NOTE, "")   # the layer's own note says "count": it must not decide
    head = c[:WRITING_HEAD]
    return bool(WRITING_RE.search(head)) and not CODE_TASK_RE.search(c) and not DATA_RE.search(head)


# A writing request that names a length in words or tokens ("a 1,500-word story"). Measured
# (docs/research/approx-note-20261022): the model then counts the words of its draft one by one in its thinking
# (18-30 % of its thinking words, up to 80 %, and most closes of the thinking budget); one paragraph that says the length
# is approximate stops it. Not for lengths in lines (a 40-line poem), where the count matters.
LENGTH_RE = re.compile(r"\b(\d[\d,.]*)\s*(k?)\s*-?\s*(words?|tokens?)\b", re.I)
# A length that one reply cannot hold gets no note: told that the length is approximate, the model then tries to write
# all of it ("a 50k token story": 4,678-8,870 words, up to 15.9x the time; approx-note-20261022 amendment A').
APPROX_MAX = 10000


def note_length(text):
    """True when text names a word or token length that the note is for (at most APPROX_MAX)."""
    m = LENGTH_RE.search(text)
    if not m:
        return False
    try:
        n = float(m.group(1).replace(",", "")) * (1000 if m.group(2) else 1)
    except ValueError:
        return False
    return n <= APPROX_MAX
APPROX_NOTE = ("About the length: an approximate length is fine. Do not count the words one by one, in your thinking or "
               "anywhere else.")


def apply_approx_note(msgs):
    """Append APPROX_NOTE to every user message that is a writing request naming a word or token length. Every turn
    gets the same note on the same messages, so the prompt of earlier turns does not change."""
    out, n = [], 0
    for m in msgs:
        if m.get("role") == "user" and isinstance(m.get("content"), str):
            c = m["content"]
            if APPROX_NOTE not in c and writing_text(c) and note_length(c[:WRITING_HEAD]):
                m = dict(m, content=c + chr(10) + chr(10) + APPROX_NOTE)
                n += 1
        out.append(m)
    return out, n


def writing_request(msgs):
    """The first user message asks for prose or verse and not for code. The first message decides, as for the API cards:
    a later message cannot change the tools of the conversation (a changed tool list makes the server read the whole
    conversation again, #224)."""
    for m in msgs:
        if m.get("role") != "user":
            continue
        return writing_text(_text_of(m.get("content")))
    return False


FINISH_NOTE = ("Before your final answer, run the program you wrote on the example given in the task and compare its "
               "output with the expected result; fix it if they differ.")


def _is_our_call_delta(line, our_idx):
    """True for an SSE line whose tool_call deltas all belong to the layer's own run_python call indices."""
    try:
        ev = json.loads(line[len(b"data: "):]) if line.startswith(b"data: ") else None
        tcs = ((ev or {}).get("choices") or [{}])[0].get("delta", {}).get("tool_calls") or []
        return bool(tcs) and all(tc.get("index", 0) in our_idx for tc in tcs)
    except Exception:
        return False


def apply_finish_note(body, msgs):
    """E15: one fixed sentence at the end of the first user message of a coding request that offers a run tool.
    Measured problem (E11): solutions that reject even the disclosed example, and the model ends its turn anyway."""
    tools = body.get("tools") or []
    if not any(apicards.CODING_TOOL_RE.search(t.get("function", {}).get("name", "")) for t in tools):
        return msgs, 0
    # Only when the user asks for code. Measured on coding tasks that offer a run tool, including clients' own tools
    # (E15; E21 on the suite's coding family: 7/12 with it vs 4/12 without). Agents that offer run tools on every turn
    # (Hermes, Cline) would otherwise get it on turns with no program, and the model writes one (2026-10-07).
    # The decision uses the first user message only (as the API cards do), so a later message cannot add the note to
    # the first message in the middle of a conversation. Issue #7: a later message with a pasted code block added it at
    # the end of the first user message (~39k tokens in, after a long tool list), and the server read the whole prompt
    # again.
    for i, m in enumerate(msgs):
        if m.get("role") == "user" and isinstance(m.get("content"), str):
            if FINISH_NOTE in m["content"] or not CODE_TASK_RE.search(m["content"]):
                return msgs, 0
            return msgs[:i] + [dict(m, content=m["content"] + chr(10) + chr(10) + FINISH_NOTE)] + msgs[i + 1:], 1
    return msgs, 0


def apply_cards(body, msgs):
    """Append API cards for the modules a coding request involves to the END of the first user message, followed by
    one generic sentence. Measured (E9/E9b): the same cards in the system message did not help (2/6); at the end of
    the user message with the sentence they matched hand-written notes (6/6). The first user message is used so the
    rendered prefix stays stable across the turns of a tool loop."""
    for i, m in enumerate(msgs):
        if m.get("role") == "user" and isinstance(m.get("content"), str):
            if "Reference: exact APIs of the Python modules" in m["content"]:
                return msgs, 0
            # cards depend only on the request up to the first user message, so they are identical on every turn
            text = apicards.cards_for_request(dict(body, messages=msgs[:i + 1]))
            if not text:
                return msgs, 0
            add = chr(10) + chr(10) + text + chr(10) + chr(10) + PREFER
            return msgs[:i] + [dict(m, content=m["content"] + add)] + msgs[i + 1:], len(add)
    return msgs, 0


class Proxy(http.server.BaseHTTPRequestHandler):
    upstream = "http://127.0.0.1:8080"
    # SSE comment sent while the server is silent, every this many seconds (0 = off). A prefill of 100k+ tokens
    # takes minutes with no bytes; clients, proxies and tunnels (Cloudflare: 100 s) close an idle connection.
    keepalive = 15.0
    max_rounds = 12       # E16: 12 rounds lost no cell that 8 won and fixed the cap-then-nudge problem in 2 of 3 seeds
    cards = True
    lint = True
    exec_timeout = 10.0
    api_key = None        # when set, chat requests are checked here before any work is done
    finish_note = True    # default for "finish_note": run-on-the-example sentence for coding requests (E15: adopted)
    repair_note = False   # default for "repair_note": a fixed sentence on failing tool results (E14 pending)
    input_file = True     # default for "input_file": the user's text as input.txt for run_python (E12: adopted)
    slots = None          # slot_cache.SlotCache when BONSAI_SLOT_SAVE_PATH is set (saved conversations on disk)
    protocol_version = "HTTP/1.1"
    _vision = None        # the server's /props modalities.vision; None = not asked yet
    _vision_at = 0.0
    prefix_log = True     # log where a request stops repeating the previous one (BONSAI_LAYER_PREFIX_LOG=0: off)
    approx_note = True    # the approximate-length note on writing requests (BONSAI_APPROX_NOTE=0, "approx_note": false)
    _prev_prompt = None

    def _has_vision(self):
        """Ask the server once a minute whether it takes images. When the answer cannot be read (for example a busy
        server misses the 5 s timeout), keep the last answer; with no answer yet, assume yes (no change)."""
        now = time.time()
        if Proxy._vision is None or now - Proxy._vision_at > 60:
            headers = {"Authorization": "Bearer " + self.api_key} if self.api_key else {}
            try:
                with urllib.request.urlopen(urllib.request.Request(self.upstream + "/props", headers=headers), timeout=5) as r:
                    Proxy._vision = bool(((json.loads(r.read()) or {}).get("modalities") or {}).get("vision", True))
            except Exception:   # noqa: BLE001
                if Proxy._vision is None:
                    Proxy._vision = True
            Proxy._vision_at = now
        return Proxy._vision

    def _drop_images(self, body):
        """Strip the images from a request when the server has no vision projector; returns the count (0 = unchanged)."""
        s = json.dumps(body)
        if not ('"image_url"' in s or '"input_image"' in s) or self._has_vision():
            return 0
        n = strip_images(body)
        if n:
            self.log_message("no vision projector: %d image part(s) replaced with a text note", n)
        return n

    def _log_prefix(self, body):
        """One log line when a chat request does not repeat the previous one up to its end: what changed (a message
        or the tool list, with the tool names). The server then reads the prompt again from that point."""
        try:
            cur = prompt_summary(body)
            why = prefix_change(Proxy._prev_prompt, cur)
            Proxy._prev_prompt = cur
            if why:
                self.log_message("prefix change against the previous request: %s. The server reads the prompt again "
                                 "from there, unless it restores a saved copy.", why)
        except Exception as e:   # noqa: BLE001  (a log line must never break a request)
            self.log_message("prefix check failed: %r", e)

    def log_message(self, fmt, *a):
        sys.stderr.write("[proxy] " + (fmt % a) + "\n")

    def _slots_on(self, body):
        """True when this send takes part in the saved-conversation cache: the cache is on, the request is a chat request
        that passed the layer's key check (_with_slots sets _slots_ok), and it has a body."""
        return (self.slots is not None and getattr(self, "_slots_ok", False) and bool(body)
                and self.path.rstrip("/").endswith("/chat/completions"))

    def _slots_check(self, body):
        """Saved-conversation check right before a chat body goes to the server (after every change the layer makes to
        it, so the tokens match what the server reads). The caller holds the cache lock."""
        if not self._slots_on(body):
            return
        self._slot_send = True   # the reply of this send gives its cached-token count to the cache (_note_cache)
        try:
            got = self.slots.before(json.loads(body) if isinstance(body, (bytes, str)) else body,
                                    self.headers.get("Authorization", ""))
            if getattr(self, "_slot_info", None) is not None:
                self._slot_info.update(got)
        except Exception as e:   # the cache must never break a request
            self.log_message("slot cache failed: %r", e)

    def _note_cache(self, n):
        """The cached-token count (timings.cache_n) of the reply to a send that _slots_check saw: the cache's prefix test
        for the save after the answer. n is a number, or bytes to search (the last match counts)."""
        if not getattr(self, "_slot_send", False) or self.slots is None:
            return
        if isinstance(n, (bytes, bytearray)):
            m = CACHE_N.findall(n)
            n = int(m[-1]) if m else None
        if n is not None:
            self._slot_send = False
            try:
                self.slots.cached(n)
            except Exception as e:   # the cache must never break a reply
                self.log_message("slot cache test failed: %r", e)

    def _prefill_result(self, body):
        """Read ahead (T1-d): read the prompt into the server and save it, at the send point (so the body is the one the
        real request will send). Returns the answer object; never generates. The caller holds the cache lock."""
        t0 = time.time()
        b = json.loads(body) if isinstance(body, (bytes, str)) else body
        try:
            info = self.slots.before(b, self.headers.get("Authorization", ""), force_save=True)
        except Exception as e:   # never drop the connection for a read-ahead (review: make failures visible)
            info = {"status": "failed: " + repr(e)[:300]}
        n = int(info.get("slot_cache_saved") or info.get("slot_cache_tokens") or 0)
        return {"id": "prefill-%d" % int(t0 * 1000), "object": "chat.completion", "created": int(t0),
                "model": b.get("model", ""), "prefill_only": True,
                "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": ""}}],
                "usage": {"prompt_tokens": n, "completion_tokens": 0, "total_tokens": n},
                "slot_cache": info, "seconds": round(time.time() - t0, 2)}

    def _prefill_sse(self, body):
        """The read-ahead answer on a streamed request: one SSE event with the object, then [DONE]. Headers + keep-alive
        go out before the lock, as for any streamed request (with --keepalive 0: the headers after the work, no comments)."""
        if self.keepalive > 0:
            stop = self._early_headers()
            try:
                with self.slots.lock:
                    out = self._prefill_result(body)
            finally:
                stop()
        else:
            with self.slots.lock:
                out = self._prefill_result(body)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
        self.wfile.write(b"data: " + json.dumps(out).encode() + b"\n\ndata: [DONE]\n\n")
        self.wfile.flush()

    def _forward(self, method, body=None):
        if self._slots_on(body) and getattr(self, "_prefill_only", False):
            with self.slots.lock:
                return 200, "application/json", json.dumps(self._prefill_result(body)).encode()
        if self._slots_on(body):
            with self.slots.lock:   # check + restore / save + the request itself, one at a time (one server slot)
                self._slots_check(body)
                out = self._forward_raw(method, body)
                self._note_cache(out[2])
                return out
        return self._forward_raw(method, body)

    def _forward_raw(self, method, body=None):
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
        req = urllib.request.Request(self.upstream + self.path, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=7200) as r:
                return r.status, r.headers.get("Content-Type", "application/json"), r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type", "application/json"), e.read()

    def _stream(self, method, body):
        """Relay a streamed (SSE) response as it arrives."""
        if self._slots_on(body) and getattr(self, "_prefill_only", False):
            return self._prefill_sse(body)
        if self._slots_on(body):
            if self.keepalive > 0:
                return self._stream_early(method, body)
            with self.slots.lock:   # --keepalive 0: no early headers, but the check and the slot lock still apply (review R1)
                self._slots_check(body)
                return self._stream_plain(method, body)
        return self._stream_plain(method, body)

    def _stream_plain(self, method, body):
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
        req = urllib.request.Request(self.upstream + self.path, data=body, method=method, headers=headers)
        try:
            r = urllib.request.urlopen(req, timeout=7200)
        except urllib.error.HTTPError as e:
            return self._reply(e.code, e.headers.get("Content-Type", "application/json"), e.read())
        self.send_response(r.status)
        self.send_header("Content-Type", r.headers.get("Content-Type", "text/event-stream"))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self._relay(r)

    @staticmethod
    def _sse_error(code, raw):
        """One SSE event with the server's own error object (its type, e.g. exceed_context_size_error, and code)."""
        try:
            err = json.loads(raw)
            if not (isinstance(err, dict) and isinstance(err.get("error"), dict)):
                err = {"error": {"code": code, "message": str(err)[:4000]}}
        except Exception:
            txt = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
            err = {"error": {"code": code, "message": txt[:4000]}}
        err["error"].setdefault("code", code)
        return b"data: " + json.dumps(err).encode() + b"\n\n"

    def _early_headers(self):
        """Send the SSE headers now and keep the connection alive with comments until the returned stop() is called."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        done = threading.Event()

        def beat():
            while not done.wait(self.keepalive if self.keepalive > 0 else 15.0):
                try:
                    self.wfile.write(b": keep-alive\n\n")
                    self.wfile.flush()
                except Exception:
                    return

        t = threading.Thread(target=beat, daemon=True)
        t.start()

        def stop():
            done.set()
            t.join()
        return stop

    def _stream_early(self, method, body):
        """The streamed path when the saved-conversation cache is on: the headers go out at once, BEFORE the cache lock is
        taken, and SSE comments keep the client connection alive while it waits for the lock (another long request),
        while the cache restores or saves (a prefill-only call can take minutes) and until the server opens its stream.
        A client with a short read timeout (e.g. 90 s) would otherwise give up and resend. A server error after this
        point arrives as one SSE event with the server's error object (the HTTP status is already 200)."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        done = threading.Event()

        def beat():
            while not done.wait(self.keepalive):
                try:
                    self.wfile.write(b": keep-alive\n\n")
                    self.wfile.flush()
                except Exception:
                    return

        t = threading.Thread(target=beat, daemon=True)
        t.start()
        with self.slots.lock:
            try:
                self._slots_check(body)
                headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
                req = urllib.request.Request(self.upstream + self.path, data=body, method=method, headers=headers)
                try:
                    r = urllib.request.urlopen(req, timeout=7200)
                except urllib.error.HTTPError as e:
                    raw = e.read()
                    done.set()
                    t.join()
                    self.wfile.write(self._sse_error(e.code, raw))
                    self.wfile.flush()
                    return
                except Exception as e:   # server gone (crash, restart): say so in the stream instead of a bare close
                    done.set()
                    t.join()
                    self.wfile.write(self._sse_error(502, repr(e)))
                    self.wfile.flush()
                    return
            finally:
                done.set()
                t.join()
            self._relay(r)

    def _relay(self, r):
        tail = b""                                 # the end of the stream: the last event carries timings.cache_n
        try:
            at_boundary = True                     # a comment may only go between two SSE events
            for chunk in self._keepalive_chunks(r):
                if chunk is None:
                    if at_boundary:
                        self.wfile.write(b": keep-alive\n\n")
                        self.wfile.flush()
                    continue
                tail = (tail + chunk)[-16384:]
                self.wfile.write(chunk)
                self.wfile.flush()
                at_boundary = chunk.endswith(b"\n\n") or chunk.endswith(b"\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            r.close()
            self._note_cache(tail)

    def _keepalive_chunks(self, r, lines=False):
        """Yield what the server sends (chunks, or lines when lines=True), and None after each keepalive seconds of
        silence. The read runs in a thread so that the wait can time out."""
        if self.keepalive <= 0:
            if lines:
                yield from r
            else:
                while True:
                    c = r.read1(65536)
                    if not c:
                        return
                    yield c
            return
        q = queue.Queue()

        def pump():
            try:
                if lines:
                    for line in r:
                        q.put(line)
                else:
                    while True:
                        c = r.read1(65536)
                        if not c:
                            break
                        q.put(c)
            except Exception:
                pass
            q.put(StopIteration)

        threading.Thread(target=pump, daemon=True).start()
        while True:
            try:
                item = q.get(timeout=self.keepalive)
            except queue.Empty:
                yield None
                continue
            if item is StopIteration:
                return
            yield item

    def _open_stream(self, body):
        self._slots_check(body)   # the interpreter-stream path holds the cache lock (see _chat)
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
        req = urllib.request.Request(self.upstream + self.path, data=json.dumps(body).encode(), method="POST", headers=headers)
        return urllib.request.urlopen(req, timeout=7200)

    def _stream_interpreter(self, body, client_tools, with_input=False, extra=None, stop_early=None):
        """The interpreter loop for a streamed request. Everything the model streams is relayed as it arrives except
        run_python tool-call deltas, which are collected, executed in the sandbox, and followed by the next round on
        the same client connection. Only used for requests without client tools."""
        msgs = list(body["messages"])
        body["tools"] = [tool_spec(with_input)]
        started = stop_early is not None   # the headers went out early (the cache is on); stop the keep-alive at the first stream
        # usage: ask the server for it on every round, sum the rounds, and emit one usage chunk at the end
        # when the client asked for one (stream_options.include_usage); otherwise none, as the client expects.
        client_usage = bool((body.get("stream_options") or {}).get("include_usage"))
        body["stream_options"] = dict(body.get("stream_options") or {}, include_usage=True)
        total = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}

        def send(line):
            self.wfile.write(line + b"\n\n")
            self.wfile.flush()

        cut_retry = False
        try:
            for rnd in range(self.max_rounds + 1):
                body["messages"] = msgs
                if cut_retry:                         # the last round was cut inside our tool call: the same messages,
                    body.pop("tools", None)           # without our tool, so the model answers in text
                    body.pop("tool_choice", None)
                if rnd == self.max_rounds:            # last round: no more code, answer now
                    body.pop("tools", None)
                    body.pop("tool_choice", None)
                    body["messages"] = msgs + [{"role": "user", "content": FINAL_NUDGE}]
                try:
                    r = self._open_stream(body)
                except urllib.error.HTTPError as e:
                    if not started:
                        return self._reply(e.code, e.headers.get("Content-Type", "application/json"), e.read())
                    if stop_early is not None:
                        stop_early()
                        self.wfile.write(self._sse_error(e.code, e.read()))
                        self.wfile.flush()
                    return
                except Exception as e:   # server gone (crash, restart)
                    if not started:
                        raise
                    if stop_early is not None:
                        stop_early()
                    self.wfile.write(self._sse_error(502, repr(e)))
                    self.wfile.flush()
                    return
                if stop_early is not None:
                    stop_early()
                if not started:
                    self.send_response(200)
                    self.send_header("Content-Type", r.headers.get("Content-Type", "text/event-stream"))
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.close_connection = True
                    started = True
                calls, held, content, reasoning, template = {}, [], [], [], None
                truncated = False
                with r:
                    for line in self._keepalive_chunks(r, lines=True):
                        if line is None:
                            send(b": keep-alive")
                            continue
                        line = line.rstrip(b"\r\n")
                        if not line.startswith(b"data:"):
                            continue
                        payload = line[5:].strip()
                        if payload == b"[DONE]":
                            held.append(line)
                            break
                        try:
                            ev = json.loads(payload)
                        except ValueError:
                            send(line)
                            continue
                        if isinstance(ev.get("timings"), dict):
                            self._note_cache(ev["timings"].get("cache_n"))
                        ch = (ev.get("choices") or [{}])[0]
                        delta = ch.get("delta") or {}
                        if template is None and ev.get("id"):
                            template = {k: ev[k] for k in ("id", "model", "created", "object", "system_fingerprint") if k in ev}
                        if ev.get("usage") and not ev.get("choices"):
                            for k in total:
                                total[k] += ev["usage"].get(k, 0) or 0
                            continue                   # replaced by one summed usage chunk at the end
                        if delta.get("tool_calls"):
                            for tc in delta["tool_calls"]:
                                c = calls.setdefault(tc.get("index", 0), {"id": "", "type": "function", "function": {"name": "", "arguments": ""}})
                                c["id"] = tc.get("id") or c["id"]
                                f = tc.get("function") or {}
                                c["function"]["name"] += f.get("name") or ""
                                c["function"]["arguments"] += f.get("arguments") or ""
                            held.append(line)
                            continue
                        if ch.get("finish_reason") == "length":
                            truncated = True       # cut by max_tokens: any held call is half-written
                        if ch.get("finish_reason") == "tool_calls" or (calls and (ch.get("finish_reason") == "length" or not ev.get("choices"))):
                            held.append(line)      # the finish chunk (and a trailing usage chunk) of a tool round
                            continue
                        if isinstance(delta.get("content"), str):
                            content.append(delta["content"])
                        if isinstance(delta.get("reasoning_content"), str):
                            reasoning.append(delta["reasoning_content"])
                        send(line)
                ordered = [calls[i] for i in sorted(calls)]
                ours = [c for c in ordered if c["function"]["name"] == TOOL_NAME]
                if (truncated and ours and len(ours) == len(ordered) and not "".join(content).strip() and not cut_retry
                        and rnd < self.max_rounds):
                    cut_retry = True               # cut inside our run_python call with no text sent: ask once more
                    if reasoning:                  # without our tool (the held call and finish chunk are dropped);
                        ev = dict(template or {"object": "chat.completion.chunk"},   # the cut round's reasoning went
                                  choices=[{"index": 0, "delta": {"reasoning_content": "\n\n"}, "finish_reason": None}])
                        send(b"data: " + json.dumps(ev).encode())   # out already: keep the two apart
                    continue
                if truncated or not ours or len(ours) != len(ordered) or rnd == self.max_rounds:
                    done = [l for l in held if l.strip() == b"data: [DONE]"]
                    our_idx = {i for i, c in calls.items() if c["function"]["name"] == TOOL_NAME}
                    for line in held:               # final answer (or a call that is not ours): hand everything back
                        if line.strip() == b"data: [DONE]":
                            continue
                        if truncated and our_idx and _is_our_call_delta(line, our_idx):
                            continue               # our half-written run_python call: never shown, never run
                        send(line)
                    if client_usage:
                        ev = dict(template or {"object": "chat.completion.chunk"}, choices=[], usage=total)
                        send(b"data: " + json.dumps(ev).encode())
                    for line in done:
                        send(line)
                    return
                am = {"role": "assistant", "content": "".join(content), "tool_calls": ordered}
                if reasoning:
                    am["reasoning_content"] = "".join(reasoning)
                msgs.append(am)
                for c in ours:
                    out = run_tool(c["function"]["arguments"], self.exec_timeout, extra)
                    msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": TOOL_NAME,
                                 "content": json.dumps({k: v for k, v in out.items() if k != "code"}, ensure_ascii=False)})
                    note = "[run_python: " + ("timed out" if out.get("timed_out") else "exit " + str(out.get("exit_code", "rejected"))) + "]"
                    ev = dict(template or {"object": "chat.completion.chunk"},
                              choices=[{"index": 0, "delta": {"reasoning_content": chr(10) + note + chr(10)}, "finish_reason": None}])
                    send(b"data: " + json.dumps(ev).encode())
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            return

    def _reply(self, status, ctype, data):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") == "/layer/slot-cache":   # for stop scripts and harnesses: wait while busy before a stop
            s = self.slots
            return self._reply(200, "application/json", json.dumps(
                {"on": s is not None, "after": bool(s and s.after_on), "busy": bool(s and s.busy)}).encode())
        self._reply(*self._forward("GET"))

    def _with_slots(self, body, fn, info=None):
        """Run fn (which sends body to the server) as a request that takes part in the saved-conversation cache: it passed
        the layer's key check. The cache lock is taken at each send (_forward, _stream_early) and around the whole
        interpreter-stream loop (_chat), so a streamed request can send its headers before it waits for the lock."""
        if self.slots is None:
            return fn()
        self._slot_info, self._slots_ok = info, True
        self.slots.enter()
        try:
            return fn()
        finally:
            self._slot_info, self._slots_ok = None, False
            try:
                if not self._prefill_only and self.slots.after_on:
                    self._slots_after()
            finally:
                self.slots.leave()

    def _slots_after(self):
        """Save after the answer (BONSAI_SLOT_CACHE_AFTER): the client has the whole answer first. A streamed reply ends
        with a closed connection, so the write side is shut before the save (a client that waits for the close is done)."""
        try:
            self.wfile.flush()
            if self.close_connection:
                self.connection.shutdown(socket.SHUT_WR)
        except Exception:
            pass
        with self.slots.lock:
            try:
                got = self.slots.after(self.headers.get("Authorization", ""))
                if got:
                    self.log_message("slot cache after the answer: %s", json.dumps(got))
            except Exception as e:   # the cache must never break a request
                self.log_message("slot cache after the answer failed: %r", e)

    def do_POST(self):
        self._slots_ok = False   # set by _with_slots only (after the key check); a keep-alive connection reuses the handler
        self._prefill_only = False
        self._slot_send = False
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.rstrip("/").endswith("/responses"):
            try:   # the Responses API: the same image handling as chat (see strip_images)
                rb = json.loads(raw)
                if self._drop_images(rb):
                    raw = json.dumps(rb).encode()
            except Exception:   # noqa: BLE001  (not JSON: the server answers it)
                pass
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._reply(*self._forward("POST", raw))
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            return self._reply(*self._forward("POST", raw))
        if self.api_key:
            given = self.headers.get("Authorization", "")
            if not hmac.compare_digest(given.encode("utf-8", "replace"), ("Bearer " + self.api_key).encode()):
                return self._reply(*self._forward("POST", raw))   # let the server produce its own 401; do no work here
        if self.prefix_log:
            self._log_prefix(body)
        images_removed = self._drop_images(body)   # no vision projector: images become a text note (issue #7)
        # Read ahead (#138 T1-d): "prefill_only": true reads the prompt into the server and saves it (the saved-conversation
        # cache), and answers with a short JSON object instead of generating. The request takes the normal path (cards,
        # notes, tools), so the saved tokens are the ones the later real request will render. It answers when the read is
        # done (minutes for a long cold prompt): a harness sends it in the background, e.g. when a large file is attached.
        if body.pop("prefill_only", False):
            if self.slots is None:   # nothing to save to: never generate for a read-ahead (review 2)
                return self._reply(200, "application/json", json.dumps(
                    {"object": "chat.completion", "prefill_only": True, "choices": [],
                     "slot_cache": {"status": "off (BONSAI_SLOT_SAVE_PATH not set)"}}).encode())
            self._prefill_only = True   # the request keeps its own route (stream or not), so its tools match the real one
        # a client that executes code blocks itself gets nothing changed (see client_runs_code)
        if not (body.get("tools") or []) and client_runs_code(body.get("messages") or []) \
                and body.get("code_interpreter") is not True:
            for k in ("code_interpreter", "input_file", "repair_note", "finish_note", "api_cards", "api_lint"):
                body.pop(k, None)
            if body.get("stream"):
                return self._with_slots(body, lambda: self._stream("POST", json.dumps(body).encode()))
            return self._with_slots(body, lambda: self._reply(*self._forward("POST", json.dumps(body).encode())))
        # server-side preprocessing for every chat request (streamed or not, with or without client tools)
        msgs0 = list(body.get("messages") or [])
        info = {"images_removed": images_removed} if images_removed else {}
        want_input = body.pop("input_file", None)
        with_input = self.input_file if want_input is None else bool(want_input)
        extra = {INPUT_FILE: user_text(msgs0)} if with_input else None
        try:
            if self.lint and body.pop("api_lint", True) is not False:
                msgs0, info["lint_notes"] = apply_lint(msgs0)
            if self.cards and body.pop("api_cards", True) is not False:
                msgs0, info["card_chars"] = apply_cards(body, msgs0)
            want_approx = body.pop("approx_note", None)
            if self.approx_note if want_approx is None else bool(want_approx):
                msgs0, info["approx_notes"] = apply_approx_note(msgs0)
            want_fin = body.pop("finish_note", None)
            if self.finish_note if want_fin is None else bool(want_fin):
                msgs0, info["finish_note"] = apply_finish_note(body, msgs0)
            want_note = body.pop("repair_note", None)
            if self.repair_note if want_note is None else bool(want_note):
                msgs0, info["repair_notes"] = apply_repair_note(msgs0)
        except Exception as e:   # preprocessing must never break a request
            self.log_message("preprocess failed: %r", e)
            msgs0 = list(body.get("messages") or [])
        body["messages"] = msgs0
        return self._with_slots(body, lambda: self._chat(body, info, with_input, extra), info)

    def _chat(self, body, info, with_input, extra):
        client_tools = body.get("tools") or []
        # Default: offer the interpreter only to requests without client tools. Measured (E4): with client tools the
        # data lives in paginated tool results, the model must retype it into code, and transcription errors cost
        # 2 of 15 tasks (1 rescued). Clients with tools can opt in with "code_interpreter": true.
        wanted = body.pop("code_interpreter", None)
        enabled = (not client_tools) if wanted is None else bool(wanted)
        if wanted is None and enabled and writing_request(body.get("messages") or []):
            enabled = False                    # story-think-20261021 G5: no run_python for writing requests
            info["writing_request"] = True
        ours_taken = any(t.get("function", {}).get("name") == TOOL_NAME for t in client_tools)
        if body.get("stream"):
            if enabled and not client_tools and not ours_taken:
                if self.slots is not None and self._slots_ok:
                    if self._prefill_only:   # the same body the first round sends: the run_python tool included
                        body["tools"] = [tool_spec(with_input)]
                        return self._prefill_sse(json.dumps(body).encode())
                    if self.keepalive <= 0:   # no comments wanted: the old path (headers at the first stream)
                        with self.slots.lock:
                            return self._stream_interpreter(body, client_tools, with_input, extra)
                    stop = self._early_headers()   # bytes before the lock: a read-ahead can hold it for minutes
                    try:
                        with self.slots.lock:   # several rounds on one client connection: hold the slot for all of them
                            return self._stream_interpreter(body, client_tools, with_input, extra, stop_early=stop)
                    finally:
                        stop()
                return self._stream_interpreter(body, client_tools, with_input, extra)
            return self._stream("POST", json.dumps(body).encode())
        if not enabled:
            return self._reply(*self._forward("POST", json.dumps(body).encode()))
        if any(t.get("function", {}).get("name") == TOOL_NAME for t in client_tools):
            return self._reply(*self._forward("POST", json.dumps(body).encode()))   # client owns that name
        body["tools"] = client_tools + [tool_spec(with_input)]
        msgs = list(body["messages"])
        trace, usage_total = [], {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        max_rounds = int(body.pop("interpreter_max_rounds", self.max_rounds) or self.max_rounds)   # E16 toggle
        final_msg = FINAL_REASON if body.pop("final_mode", None) == "reason" else FINAL_NUDGE    # E16 toggle
        cut_retry = False
        for rnd in range(max_rounds + 1):
            body["messages"] = msgs
            if cut_retry:                         # the last round was cut inside our tool call: the same messages,
                body["tools"] = client_tools or None  # without our tool, so the model answers in text
                if not client_tools:
                    body.pop("tools", None)
                    body.pop("tool_choice", None)
            if rnd == max_rounds:                 # last round: no more code, answer now
                body["tools"] = client_tools or None
                if not client_tools:
                    body.pop("tools", None)
                    body.pop("tool_choice", None)
                # E7 seed 411: with tools merely removed, the model can end without an answer. Say it plainly.
                body["messages"] = msgs + [{"role": "user", "content": final_msg}]
            status, ctype, data = self._forward("POST", json.dumps(body).encode())
            if status != 200:
                return self._reply(status, ctype, data)
            resp = json.loads(data)
            for k in usage_total:
                usage_total[k] += (resp.get("usage") or {}).get(k, 0)
            m = resp["choices"][0]["message"]
            calls = m.get("tool_calls") or []
            ours = [c for c in calls if c["function"]["name"] == TOOL_NAME]
            truncated = resp["choices"][0].get("finish_reason") == "length"   # half-written calls: hand back, never run
            if (truncated and ours and len(ours) == len(calls) and not (m.get("content") or "").strip() and not cut_retry
                    and rnd < max_rounds):
                # max_tokens cut the round inside our run_python call (the model was writing its answer into code):
                # handing back would give the client nothing. Ask once more without our tool so the answer is text.
                cut_retry = True
                info["cut_retry"] = True
                continue
            if truncated or not ours or len(ours) != len(calls):   # final answer, or a client tool call: hand back
                if ours:                               # mixed: drop our calls, keep the client's
                    m["tool_calls"] = [c for c in calls if c["function"]["name"] != TOOL_NAME]
                resp["usage"] = usage_total
                resp["interpreter_trace"] = trace
                resp["layer"] = info
                return self._reply(200, "application/json", json.dumps(resp).encode())
            am = {"role": "assistant", "content": m.get("content") or "", "tool_calls": calls}
            if m.get("reasoning_content"):
                am["reasoning_content"] = m["reasoning_content"]
            msgs.append(am)
            for c in ours:
                out = run_tool(c["function"]["arguments"], self.exec_timeout, extra)
                trace.append({"round": rnd, "exit_code": out.get("exit_code"), "timed_out": out.get("timed_out"),
                              "code_chars": out.get("code_chars"), "code": out.get("code"),
                              "stdout_head": (out.get("stdout") or "")[:200]})
                msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": TOOL_NAME,
                             "content": json.dumps({k: v for k, v in out.items() if k != "code"}, ensure_ascii=False)})
        return self._reply(500, "application/json", b'{"error":"interpreter loop ended without an answer"}')


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--upstream", default="http://127.0.0.1:8080")
    ap.add_argument("--max-rounds", type=int, default=12)
    ap.add_argument("--keepalive", type=float, default=15.0, help="seconds of server silence before an SSE comment (0 = off)")
    ap.add_argument("--no-cards", action="store_true")
    ap.add_argument("--no-lint", action="store_true")
    ap.add_argument("--no-finish-note", action="store_true", help="do not append the run-on-the-example sentence to coding requests")
    ap.add_argument("--repair-note", action="store_true", help="append a fixed sentence to failing tool results by default")
    ap.add_argument("--no-input-file", action="store_true", help="do not give run_python the user's text as input.txt")
    a = ap.parse_args()
    Proxy.api_key = os.environ.get("BONSAI_LAYER_KEY") or None
    Proxy.prefix_log = os.environ.get("BONSAI_LAYER_PREFIX_LOG", "1") != "0"
    Proxy.approx_note = os.environ.get("BONSAI_APPROX_NOTE", "1") != "0"
    Proxy.upstream, Proxy.max_rounds = a.upstream, a.max_rounds
    Proxy.keepalive = a.keepalive
    Proxy.cards, Proxy.lint = not a.no_cards, not a.no_lint
    Proxy.input_file = not a.no_input_file
    Proxy.repair_note = a.repair_note
    Proxy.finish_note = not a.no_finish_note
    Proxy.slots = slot_cache.SlotCache.from_env(a.upstream)
    if Proxy.slots:
        print(f"bonsai layer: saved conversations in {Proxy.slots.folder} ({len(Proxy.slots.index)} on disk)", flush=True)
    srv = http.server.ThreadingHTTPServer((a.host, a.port), Proxy)
    print(f"bonsai layer on {a.host}:{a.port} -> {a.upstream}", flush=True)
    srv.serve_forever()

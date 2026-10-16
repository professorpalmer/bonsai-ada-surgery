"""Example check (Plan G1, 2B): run the docstring examples of a coding request on the model's answer, in the sandbox.
When they fail, the layer sends one follow-up turn with the doctest report and returns the second answer.

G1 (results/<size>/dose_ladder/): on the 2B, a doctest report recovered 5 of 30 failed HumanEval answers against 2 of
30 for a plain "try again" (5 of 20 against 1 of 20 where the examples fail). Off by default; "example_check": true
per request or --example-check turns it on.
"""
import json
import re

BASE_MSG = "Your solution is not correct. Try again."

# Runs inside the sandbox (CPython on WASI). An example written as an expression (`f(x) == y`) with no expected
# output prints True when the answer is right; doctest calls that a failure ("Expected nothing, Got True"), so it
# counts as a pass here: a correct answer must never get the follow-up.
CHECKER = r'''
import ast, doctest, io, json, sys
JOB = json.loads(%s)
ns = {"__name__": "__main__"}
try:
    exec(JOB["header"], ns)       # the request's imports and helper functions: answers often leave them out
except BaseException:
    pass
try:
    exec(JOB["code"], ns)
except BaseException as e:
    print(json.dumps({"error": "the code does not run: %%s: %%s" %% (type(e).__name__, e)})); sys.exit()
ex = doctest.DocTestParser().get_examples(JOB["doc"])
if not ex:
    print(json.dumps({"n": 0})); sys.exit()
class Checker(doctest.OutputChecker):
    def check_output(self, want, got, optionflags):
        if not want.strip() and got.strip() == "True":
            return True
        try:                       # same value written another way ("21" and '21', 15 and 15.0)
            if ast.literal_eval(want.strip()) == ast.literal_eval(got.strip()):
                return True
        except Exception:
            pass
        return doctest.OutputChecker.check_output(self, want, got, optionflags)
test = doctest.DocTest(ex, ns, "docstring", None, 0, None)
out = io.StringIO()
runner = doctest.DocTestRunner(checker=Checker(), optionflags=doctest.NORMALIZE_WHITESPACE)
runner.run(test, out=out.write)
keep = [l for l in out.getvalue().splitlines() if not l.strip().startswith(("File ", "Traceback", "exec(", "^", "~", "*****"))
        and "doctest.py" not in l]
print(json.dumps({"n": len(ex), "failed": runner.failures, "report": "\n".join(keep)[:3000]}))
'''

_FENCE = re.compile(r"```(?:python|py)?[ \t]*\n(.*?)```", re.S)


def task(user_text):
    """(function name, docstring text with examples, header code) of the last function stub in the request, or None.
    The header is the code above the stub (imports, helper functions), from the first line that starts code."""
    i = user_text.rfind("\ndef ")
    if i < 0 and user_text.startswith("def "):
        i = 0
    if i < 0:
        return None
    stub = user_text[i:].lstrip("\n")
    m = re.match(r"def\s+([A-Za-z_]\w*)\s*\(", stub)
    if not m or ">>>" not in stub:
        return None
    # the stub ends inside the function: the closing quotes would join the last expected output
    doc = "\n".join(l for l in stub.splitlines() if l.strip() not in ('"' * 3, "'" * 3))
    above = user_text[:i].splitlines()
    start = next((k for k, l in enumerate(above) if re.match(r"(import |from \S+ import |def |class |@)", l)), len(above))
    return m.group(1), doc, "\n".join(above[start:])


def answer_code(content, name):
    """The last fenced code block of the answer that defines the function, or None."""
    blocks = [b for b in _FENCE.findall(content or "") if re.search(rf"\bdef\s+{re.escape(name)}\s*\(", b)]
    return blocks[-1] if blocks else None


def checker_program(code, doc, header=""):
    return CHECKER % repr(json.dumps({"code": code, "doc": doc, "header": header}))


def follow_up(result):
    """The follow-up message for a failed check (the G1 R2 text), or None when the answer passes or cannot be checked."""
    if result.get("error"):
        return BASE_MSG + f" The server ran your code: {result['error']}."
    if result.get("n") and result.get("failed"):
        return BASE_MSG + " The server ran the docstring examples on your code:\n\n" + (result.get("report") or "")
    return None

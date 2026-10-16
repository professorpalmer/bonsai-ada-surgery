"""API linter: check the names a Python program uses against the real runtime, without executing the program.

The candidate source is only parsed (ast). Imports of the modules it names happen inside the WASI sandbox.
Reports: syntax errors, modules that do not exist, module attributes that do not exist (with close matches),
names missing from `from x import y`, and keyword arguments a resolved callable does not accept.
Instance attributes (obj.attr where obj's type is unknown) are not checked, so there are no guesses.
"""
import hashlib
import json

import sandbox_path  # noqa: F401
import sandbox

_LINT = r'''
import ast, difflib, importlib, inspect, json, sys
src = open("/work/candidate.txt", encoding="utf-8").read()
warn = []
def add(line, msg):
    if len(warn) < 10 and (line, msg) not in warn:
        warn.append((line, msg))
try:
    tree = ast.parse(src)
except SyntaxError as e:
    print(json.dumps([[e.lineno or 0, f"SyntaxError: {e.msg}"]])); sys.exit(0)

alias = {}   # local name -> object, for names bound by import statements at any level
def imp(name, line):
    try:
        return importlib.import_module(name)
    except Exception:
        return None     # may be a local workspace module (e.g. "import solution"): say nothing
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for a in node.names:
            m = imp(a.name, node.lineno)
            if m is not None:
                alias[a.asname or a.name.split(".")[0]] = m if a.asname else importlib.import_module(a.name.split(".")[0])
    elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
        m = imp(node.module, node.lineno)
        if m is None:
            continue
        for a in node.names:
            if a.name == "*":
                continue
            if hasattr(m, a.name):
                alias[a.asname or a.name] = getattr(m, a.name)
            else:
                try:
                    alias[a.asname or a.name] = importlib.import_module(node.module + "." + a.name)
                except Exception:
                    close = difflib.get_close_matches(a.name, dir(m), 3)
                    add(node.lineno, f"'{node.module}' has no name '{a.name}'" + (f"; did you mean {', '.join(close)}?" if close else ""))

# names rebound by assignment / def / class / args shadow the import: do not check those
shadow = set()
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        shadow.add(node.name)
    elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
        shadow.add(node.id)
    elif isinstance(node, ast.arg):
        shadow.add(node.arg)

def qual(o):
    return getattr(o, "__name__", None) or type(o).__name__

def resolve(node):
    """Resolve Name / Attribute chains rooted at an imported name. Returns (obj, ok)."""
    if isinstance(node, ast.Name):
        if node.id in alias and node.id not in shadow:
            return alias[node.id], True
        return None, False
    if isinstance(node, ast.Attribute):
        base, ok = resolve(node.value)
        if not ok:
            return None, False
        if not (inspect.ismodule(base) or inspect.isclass(base)):
            return None, False          # instance or function attribute: type unknown, do not guess
        if hasattr(base, node.attr):
            return getattr(base, node.attr), True
        if inspect.isclass(base):
            # instance fields declared in __slots__ or set in __init__ are not class attributes: skip classes
            return None, False
        close = difflib.get_close_matches(node.attr, [n for n in dir(base) if not n.startswith("_")], 3)
        add(node.lineno, f"'{qual(base)}.{node.attr}' does not exist" + (f"; did you mean {', '.join(close)}?" if close else ""))
        return None, False
    return None, False

for node in ast.walk(tree):
    if isinstance(node, ast.Attribute):
        resolve(node)
    if isinstance(node, ast.Call):
        obj, ok = resolve(node.func)
        if ok and callable(obj) and node.keywords:
            try:
                sig = inspect.signature(obj)
            except (TypeError, ValueError):
                continue
            params = sig.parameters
            if any(p.kind == p.VAR_KEYWORD for p in params.values()):
                continue
            for kw in node.keywords:
                if kw.arg and kw.arg not in params:
                    names = [n for n, p in params.items() if p.kind in (p.POSITIONAL_OR_KEYWORD, p.KEYWORD_ONLY)]
                    add(node.lineno, f"'{qual(obj)}()' has no keyword argument '{kw.arg}'; it accepts: {', '.join(names) or '(none)'}")
print(json.dumps(sorted(warn)))
'''

_cache = {}


def lint(source):
    """Return a list of (line, message). Empty when nothing checkable is wrong or the check itself fails."""
    if not isinstance(source, str) or not source.strip():
        return []
    key = hashlib.sha256(source.encode("utf-8", "replace")).hexdigest()
    if key in _cache:
        return _cache[key]
    r = sandbox.run({"lint.py": _LINT, "candidate.txt": source}, ["/work/lint.py"], timeout=15, mem_mb=256)
    try:
        out = [(int(l), str(m)) for l, m in json.loads(r["stdout"].decode("utf-8"))]
    except (ValueError, UnicodeDecodeError, TypeError):
        out = []
    _cache[key] = out
    return out


def looks_like_python(name, value):
    if not isinstance(value, str) or len(value) < 20:
        return False
    if isinstance(name, str) and name.lower().endswith(".py"):
        return True
    head = value[:4000]
    return ("import " in head and ("def " in head or "\n" in head)) and not head.lstrip().startswith(("{", "<"))


def format_warnings(warnings):
    return ("[API check by the server, against the real Python runtime] " +
            "; ".join(f"line {l}: {m}" for l, m in warnings))

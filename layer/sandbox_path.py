import os
import sys

_P = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wasi-python")
if _P not in sys.path:
    sys.path.insert(0, _P)

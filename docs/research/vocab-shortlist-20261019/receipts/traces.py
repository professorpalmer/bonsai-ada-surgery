"""Save thinking traces from the serving model for the shortlist corpus.
python traces.py BASE KEYFILE OUT.jsonl
Prompts: 40 HumanEval tasks (every 4th), 40 general prompts, 20 tool-call prompts. Thinking on, medium, 3,072 tokens."""
import gzip, json, os, sys, time, urllib.request

BASE, KEYF, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
KEY = open(KEYF).read().strip()
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}

he = [json.loads(l) for l in gzip.open(os.path.join(os.environ["TEMP"], "human-eval", "data", "HumanEval.jsonl.gz"), "rt")]
prompts = [("he", "Complete this Python function so it passes its docstring examples. Reply with one python code block "
                  "containing only the function.\n\n" + t["prompt"]) for t in he[::4][:40]]
general = [
    "Explain why the sky is blue to a ten-year-old, then to a physics student.",
    "A train leaves at 9:40 and arrives at 13:05. The trip has two stops of 7 minutes. How long does it move?",
    "Write a short email to a landlord about a broken heater. Be polite and firm.",
    "What are the trade-offs between SQLite and PostgreSQL for a small web app?",
    "Summarize the causes of the French Revolution in five points.",
    "I have 3 red, 4 blue and 5 green balls. I draw 2 without replacement. What is P(same color)?",
    "Plan a three-day trip to Kyoto on a budget, with one rainy-day option.",
    "Write a haiku about a server room at night, then explain the imagery.",
    "How do I find a memory leak in a long-running Python process?",
    "Compare TCP and UDP for a multiplayer game. Which would you pick and why?",
    "Is 2^61 - 1 prime? Explain how you would check it.",
    "Rewrite this sentence in plain English: 'The utilization of the aforementioned methodology yielded suboptimal outcomes.'",
    "What is the difference between a mutex and a semaphore? Give an example of each.",
    "Explain how gradient descent works, with a small numeric example.",
    "Give me a recipe for a vegetarian chili for six people.",
    "My git branch has diverged from origin. How do I fix it without losing work?",
    "Write a limerick about a cat that learns to code.",
    "What happens, step by step, when I type a URL into a browser and press enter?",
    "A rectangle has perimeter 40 and area 96. Find its sides.",
    "Draft a short product description for noise-cancelling headphones.",
    "Explain the CAP theorem with a real-world analogy.",
    "What are good ways to learn a new language as an adult?",
    "Convert 72 degrees Fahrenheit to Celsius and explain the formula.",
    "Write a bash one-liner that finds the 10 largest files under the current directory.",
    "Explain the difference between 'affect' and 'effect' with examples.",
    "What is a Bloom filter, and when should I use one?",
    "Outline a 20-minute talk about renewable energy storage.",
    "Debug this: my React component re-renders forever after I added useEffect with a state setter.",
    "How many ways can 8 people sit at a round table?",
    "Write a short story opening (150 words) set on a generation ship.",
    "What should I check before buying a used car?",
    "Explain big-O notation and give the complexity of binary search.",
    "Translate 'Where is the train station?' into Spanish, French and German.",
    "Why does ice float on water?",
    "Design a REST API for a to-do app: endpoints, methods and status codes.",
    "What is the derivative of x^x? Show the steps.",
    "Give three arguments for and three against remote work.",
    "How does a hash map handle collisions?",
    "Write a SQL query that returns the top 3 salaries per department.",
    "Explain what a CUDA warp is and why divergence is slow.",
]
prompts += [("gen", p) for p in general]
TOOLS = [{"type": "function", "function": {"name": "run_shell", "description": "Run a shell command and return its output.",
          "parameters": {"type": "object", "properties": {"cmd": {"type": "string"}}, "required": ["cmd"]}}},
         {"type": "function", "function": {"name": "read_file", "description": "Read a text file.",
          "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}}]
tool_tasks = [
    "Find out how much disk space is free on this machine.", "Show me the first lines of README.md.",
    "Which Python version is installed?", "Count the lines of every .py file in src/.",
    "Read config.yaml and tell me which port the server uses.", "List the five newest files in logs/.",
    "Check whether port 8080 is in use.", "Find TODO comments in the project.",
    "Read requirements.txt and tell me which packages are pinned.", "Show the git log of the last 3 commits.",
    "How big is the models folder?", "Read setup.py and tell me the package name.",
    "Find files larger than 100 MB.", "Show the environment variable PATH.",
    "Read the file notes/todo.md and summarize it.", "Which processes use the most memory?",
    "Check if the file data/input.csv exists and count its rows.", "Read main.py and explain what it does.",
    "Show the current directory and its contents.", "Find all JSON files and read the smallest one.",
]
prompts += [("tool", p) for p in tool_tasks]

with open(OUT, "w", encoding="utf-8") as f:
    for i, (kind, p) in enumerate(prompts):
        body = {"messages": [{"role": "user", "content": p}], "max_tokens": 3072,
                "chat_template_kwargs": {"enable_thinking": True, "reasoning_effort": "medium"}}
        if kind == "tool":
            body["tools"] = TOOLS
        t0 = time.time()
        try:
            r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions",
                            data=json.dumps(body).encode(), headers=H), timeout=900).read())
            m = r["choices"][0]["message"]
            rec = {"i": i, "kind": kind, "reasoning": m.get("reasoning_content") or "", "content": m.get("content") or "",
                   "tool_calls": m.get("tool_calls") or [], "finish": r["choices"][0].get("finish_reason"),
                   "n": (r.get("usage") or {}).get("completion_tokens"), "wall": round(time.time() - t0, 1)}
        except Exception as e:  # noqa: BLE001
            rec = {"i": i, "kind": kind, "error": str(e)[:200]}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        f.flush()
        print(i, kind, rec.get("n"), rec.get("finish"), rec.get("error", ""), flush=True)

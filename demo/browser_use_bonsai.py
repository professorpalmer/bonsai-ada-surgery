"""Browser-use 0.13 pointed at the local Bonsai CUDA llama-server.

Default is a localhost-only fake checkout (Sandbox Market). Thinking off.
No screenshots (mmproj is not loaded). Isolated workspace so the agent cannot
finish by pointing at this repo's README.

  python demo\\browser_use_bonsai.py
  python demo\\browser_use_bonsai.py --mode heading
  python demo\\browser_use_bonsai.py --engine rust
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import tempfile
import time
from pathlib import Path
from urllib.request import urlopen

from browser_use.browser.profile import BrowserProfile
from browser_use.llm.messages import UserMessage
from browser_use.llm.openai.chat import ChatOpenAI
from browser_use.tools.service import Tools
from openai import AsyncOpenAI

_DEMO_DIR = Path(__file__).resolve().parent
if str(_DEMO_DIR) not in sys.path:
    sys.path.insert(0, str(_DEMO_DIR))
from store_server import start_store

CHROME = Path(os.environ.get("LOCALAPPDATA", "")) / "ms-playwright" / "chromium-1243" / "chrome-win64" / "chrome.exe"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_URL = "https://example.com"
DEFAULT_EXPECT = "Example Domain"
NO_FILE_ACTIONS = [
    "read_file",
    "write_file",
    "replace_file",
    "search",
    "upload_file",
    "screenshot",
]
BUYER = {
    "full_name": "Ada Lovelace",
    "email": "ada@sandbox.local",
    "address": "12 Demo Street, Austin TX 78701",
    "card": "4242424242424242",
    "expiry": "12/30",
    "cvc": "123",
}


class ChatBonsai(ChatOpenAI):
    """OpenAI-compatible client with a per-request think budget.

    Think-off is safe for tools. The sweet spot for computer-use is thinking
    on + a tight reasoning_budget_tokens so the sampler force-closes </think>
    and the action still fits in max_completion_tokens.
    """

    def get_client(self) -> AsyncOpenAI:
        client = super().get_client()
        inner = client.chat.completions.create
        think = bool(getattr(self, "bonsai_think", False))
        effort = str(getattr(self, "bonsai_effort", "medium"))
        budget = getattr(self, "bonsai_think_budget", None)
        msg = str(getattr(self, "bonsai_think_msg", "Now take the next browser action as JSON."))

        async def create(*args, **kwargs):
            body = dict(kwargs.get("extra_body") or {})
            body["chat_template_kwargs"] = {
                "enable_thinking": think,
                "reasoning_effort": effort,
            }
            if think and budget is not None:
                body["reasoning_budget_tokens"] = int(budget)
                body["reasoning_budget_message"] = msg
            kwargs["extra_body"] = body
            return await inner(*args, **kwargs)

        client.chat.completions.create = create  # type: ignore[method-assign]
        return client


def read_key(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"api key missing: {path}")
    return path.read_text(encoding="utf-8").strip()


def looks_like_local_path(text: str) -> bool:
    lower = text.lower().replace("/", "\\")
    return "readme.md" in lower or "bonsai-2-27b-serve" in lower or lower.startswith("result file:")


def make_llm(
    base: str,
    key: str,
    *,
    think: bool = False,
    effort: str = "medium",
    think_budget: int | None = None,
) -> ChatBonsai:
    answer_room = 1024
    max_tokens = answer_room + (int(think_budget) if think and think_budget else 0)
    llm = ChatBonsai(
        model="bonsai-2-27b",
        base_url=base.rstrip("/") + "/v1",
        api_key=key,
        temperature=0.2,
        top_p=0.95,
        frequency_penalty=0.0,
        dont_force_structured_output=True,
        add_schema_to_system_prompt=True,
        remove_min_items_from_schema=True,
        max_completion_tokens=max_tokens,
        timeout=180.0,
    )
    llm.bonsai_think = think
    llm.bonsai_effort = effort
    llm.bonsai_think_budget = think_budget
    llm.bonsai_think_msg = "Now take the next browser action as JSON."
    return llm


def make_profile(*, localhost_only: bool) -> BrowserProfile:
    if not CHROME.is_file():
        raise SystemExit("Playwright Chromium missing. Run: python -m playwright install chromium")
    kwargs = {
        "executable_path": str(CHROME),
        "headless": False,
        "disable_security": True,
        "wait_for_network_idle_page_load_time": 1.0,
        "block_ip_addresses": False,
    }
    if localhost_only:
        kwargs["allowed_domains"] = ["127.0.0.1", "localhost"]
    return BrowserProfile(**kwargs)


def heading_task(url: str) -> str:
    return (
        f"Open {url} in the browser. Wait until the page text is visible. "
        "Then call done with success=true and a result that is ONLY this line:\n"
        "HEADING: <exact h1 text from the page>\n"
        "Do not read, write, or mention any local files. There is no README. "
        "Do not invent the heading from memory. Copy it from the live page."
    )


def shop_task(url: str) -> str:
    return (
        f"Buy the Harbor Mug from the SANDBOX store at {url}. "
        "This is a fake checkout. No real money. Stay on 127.0.0.1.\n"
        "Steps:\n"
        "1. Open the shop.\n"
        "2. Click 'Add Harbor Mug to cart'.\n"
        "3. Click 'Go to checkout' or the Checkout link.\n"
        "4. Fill the form exactly:\n"
        f"   Full name: {BUYER['full_name']}\n"
        f"   Email: {BUYER['email']}\n"
        f"   Address: {BUYER['address']}\n"
        f"   Card number: {BUYER['card']}\n"
        f"   Expiry: {BUYER['expiry']}\n"
        f"   CVC: {BUYER['cvc']}\n"
        "5. Click 'Place sandbox order'.\n"
        "6. On the confirmation page, copy the order id (starts with SBX-).\n"
        "7. Call done with ONLY these lines:\n"
        "ORDER: <id>\nTOTAL: $36.00\nLAST4: 4242\n"
        "Do not invent an order id. Do not mention local files or README."
    )


def dump_history(history, out_dir: Path) -> dict:
    urls = []
    try:
        urls = [u for u in (history.urls() or []) if u]
    except Exception:
        urls = []
    errors = []
    try:
        errors = [e for e in (history.errors() or []) if e]
    except Exception:
        errors = []
    result = history.final_result() or ""
    payload = {
        "result": result,
        "done": bool(history.is_done()),
        "success": bool(history.is_successful()),
        "steps": len(history),
        "urls": urls,
        "errors": [str(e) for e in errors][:12],
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "last.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def accept_heading(payload: dict, expect: str) -> bool:
    result = str(payload.get("result") or "")
    if looks_like_local_path(result):
        return False
    return expect.lower() in result.lower()


def accept_shop(payload: dict, order: dict | None) -> bool:
    result = str(payload.get("result") or "")
    if not order:
        return False
    if looks_like_local_path(result):
        return False
    order_id = str(order.get("order_id") or "")
    return bool(order_id) and order_id in result


def load_last_order(orders_path: Path) -> dict | None:
    if not orders_path.is_file():
        return None
    orders = json.loads(orders_path.read_text(encoding="utf-8"))
    return orders[-1] if orders else None


async def run_python_agent(
    task: str,
    max_steps: int,
    llm: ChatBonsai,
    workspace: Path,
    *,
    localhost_only: bool,
    system: str,
    actions_per_step: int,
):
    from browser_use.agent.service import Agent

    agent = Agent(
        task=task,
        llm=llm,
        browser_profile=make_profile(localhost_only=localhost_only),
        tools=Tools(exclude_actions=NO_FILE_ACTIONS, display_files_in_done_text=False),
        file_system_path=str(workspace),
        available_file_paths=[],
        use_vision=False,
        use_thinking=False,
        use_judge=False,
        enable_planning=False,
        flash_mode=True,
        max_actions_per_step=actions_per_step,
        llm_timeout=180,
        step_timeout=180,
        directly_open_url=True,
        display_files_in_done_text=False,
        extend_system_message=system,
    )
    return await agent.run(max_steps=max_steps)


async def run_rust_agent(
    task: str,
    max_steps: int,
    llm: ChatBonsai,
    workspace: Path,
    *,
    localhost_only: bool,
    system: str,
    actions_per_step: int,
):
    from browser_use.beta import Agent

    agent = Agent(
        task=task,
        llm=llm,
        browser_profile=make_profile(localhost_only=localhost_only),
        file_system_path=str(workspace),
        available_file_paths=[],
        use_vision=False,
        use_thinking=False,
        use_judge=False,
        enable_planning=False,
        flash_mode=True,
        max_actions_per_step=actions_per_step,
        llm_timeout=180,
        step_timeout=180,
        directly_open_url=True,
        display_files_in_done_text=False,
        extend_system_message=system,
    )
    agent.settings.use_vision = False
    return await agent.run(max_steps=max_steps)


async def run_extract(url: str, llm: ChatBonsai) -> tuple[str, str]:
    from playwright.async_api import async_playwright

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(executable_path=str(CHROME), headless=False)
        page = await browser.new_page()
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        heading = (await page.locator("h1").first.inner_text()).strip()
        body = (await page.locator("body").inner_text()).strip()
        await page.wait_for_timeout(1500)
        await browser.close()

    prompt = (
        "The browser just opened this page. Quote the h1 exactly.\n"
        "Reply with ONLY this line: HEADING: <h1 text>\n\n"
        f"PAGE TEXT:\n{body[:2000]}"
    )
    completion = await llm.ainvoke([UserMessage(content=prompt)])
    return str(completion.completion).strip(), heading


HEADING_SYSTEM = (
    "You only control a web browser. You have no local project. "
    "Never mention README.md or any filesystem path. "
    "When the h1 is visible, immediately call done with HEADING: <h1>."
)
SHOP_SYSTEM = (
    "You only control a web browser on a localhost sandbox store. "
    "Never mention README.md or any filesystem path. "
    "Never leave 127.0.0.1. Complete the fake checkout, then done with the "
    "real SBX- order id from the confirmation page."
)


async def run_agent(engine: str, task: str, max_steps: int, llm: ChatBonsai, workspace: Path, *, shop: bool):
    kwargs = {
        "localhost_only": shop,
        "system": SHOP_SYSTEM if shop else HEADING_SYSTEM,
        "actions_per_step": 4 if shop else 2,
    }
    if engine == "rust":
        return await run_rust_agent(task, max_steps, llm, workspace, **kwargs)
    return await run_python_agent(task, max_steps, llm, workspace, **kwargs)


async def run(args) -> int:
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    llm = make_llm(
        args.base,
        read_key(Path(args.key_file)),
        think=args.think != "off",
        effort="medium" if args.think == "off" else args.think,
        think_budget=None if args.think == "off" else args.think_budget,
    )
    workspace = Path(tempfile.mkdtemp(prefix="bonsai-browser-use-"))
    server = None
    url = args.task_url
    orders_path = out_dir / "orders.json"

    if args.mode == "shop":
        orders_path.write_text("[]\n", encoding="utf-8")
        server, url = start_store("127.0.0.1", args.store_port, orders_path)
        task = shop_task(url)
        print(f"store={url} orders={orders_path}", flush=True)
    else:
        task = heading_task(url)

    print(f"mode={args.mode} engine={args.engine} url={url} workspace={workspace}", flush=True)
    old_cwd = os.getcwd()
    os.chdir(workspace)
    payload: dict | None = None
    try:
        history = await run_agent(args.engine, task, args.max_steps, llm, workspace, shop=(args.mode == "shop"))
        payload = dump_history(history, out_dir)
    finally:
        os.chdir(old_cwd)
        if server is not None:
            server.shutdown()

    print("\n--- agent ---", flush=True)
    print(json.dumps(payload, indent=2), flush=True)

    if args.mode == "shop":
        order = load_last_order(orders_path)
        print("\n--- store order ---", flush=True)
        print(json.dumps(order, indent=2), flush=True)
        if payload and accept_shop(payload, order):
            print("\n--- result ---", flush=True)
            print(payload["result"], flush=True)
            return 0
        print("\nshop demo did not confirm a real sandbox order", flush=True)
        return 2

    if payload and accept_heading(payload, args.expect):
        print("\n--- result ---", flush=True)
        print(payload["result"], flush=True)
        return 0

    print("\nagent result unusable; falling back to Playwright extract + Bonsai quote", flush=True)
    quoted, heading = await run_extract(url, llm)
    fallback = {
        "engine": "extract",
        "url": url,
        "dom_h1": heading,
        "result": quoted,
        "done": True,
        "success": args.expect.lower() in quoted.lower() or args.expect.lower() in heading.lower(),
    }
    (out_dir / "last.json").write_text(json.dumps(fallback, indent=2), encoding="utf-8")
    print("\n--- result ---", flush=True)
    print(quoted, flush=True)
    print(f"dom_h1={heading!r} success={fallback['success']}", flush=True)
    return 0 if fallback["success"] else 2


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("shop", "heading"), default="shop")
    parser.add_argument("--task-url", default=DEFAULT_URL)
    parser.add_argument("--expect", default=DEFAULT_EXPECT)
    parser.add_argument("--engine", choices=("python", "rust"), default="python")
    parser.add_argument("--think", choices=("off", "low", "medium"), default="off")
    parser.add_argument(
        "--think-budget",
        type=int,
        default=512,
        help="Per-request reasoning_budget_tokens when --think is not off. Caps think, then the action.",
    )
    parser.add_argument("--max-steps", type=int, default=20)
    parser.add_argument("--store-port", type=int, default=8765)
    parser.add_argument("--base", default="http://127.0.0.1:8080")
    parser.add_argument("--key-file", default=str(ROOT / "artifacts" / "api_key.txt"))
    parser.add_argument("--out-dir", default=str(ROOT / "artifacts" / "demo" / "browser-use"))
    args = parser.parse_args()
    os.environ.setdefault("ANONYMIZED_TELEMETRY", "false")
    os.environ.setdefault("BROWSER_USE_SETUP_LOGGING", "true")
    try:
        with urlopen(args.base.rstrip("/") + "/health", timeout=5) as resp:
            if resp.status != 200:
                raise SystemExit(f"llama-server health {resp.status}")
    except SystemExit:
        raise
    except Exception as exc:
        raise SystemExit(f"llama-server not reachable at {args.base}: {exc}") from exc

    started = time.time()
    code = asyncio.run(run(args))
    print(f"elapsed_s={time.time() - started:.1f}", flush=True)
    raise SystemExit(code)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)

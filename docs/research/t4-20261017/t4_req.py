"""One timed request at a depth (T4 gates): filler of ~depth tokens (bench/quick_tps.py) + the quick_tps code prompt.
Prints client wall time, server prompt_n / prompt_ms, decode rate and a hash of the answer text.
usage: python t4_req.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 128000 [--n 128] [--tag x]"""
import argparse, hashlib, json, os, sys, time, urllib.request

sys.path.insert(0, os.path.join(os.getcwd(), 'bench'))
import quick_tps as q  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', default='http://127.0.0.1:8080')
    ap.add_argument('--key-file', default=None)
    ap.add_argument('--depth', type=int, default=0)
    ap.add_argument('--n', type=int, default=128)
    ap.add_argument('--tag', default='')
    a = ap.parse_args()
    key = open(a.key_file).read().strip() if a.key_file else None
    name, prompt, _ = next(p for p in q.PROMPTS if p[0] == 'code')
    if a.depth:
        prompt = q.filler(a.base, key, a.depth) + prompt
    body = {'model': 'b', 'messages': [{'role': 'user', 'content': prompt}], 'max_tokens': a.n, 'temperature': 0,
            'chat_template_kwargs': {'enable_thinking': False}}
    req = urllib.request.Request(a.base.rstrip('/') + '/v1/chat/completions', data=json.dumps(body).encode(), headers=q._headers(key))
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=7200).read())
    wall = time.time() - t0
    t = r.get('timings', {})
    text = r['choices'][0]['message'].get('content') or ''
    h = hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]
    print(f"t4req {a.tag} depth {a.depth}: wall {wall:7.1f} s, prompt_n {t.get('prompt_n')}, prompt_ms {t.get('prompt_ms', 0)/1000:7.1f} s, "
          f"decode {t.get('predicted_per_second', 0):5.1f} tok/s ({t.get('predicted_n')} tok), answer {h} | {text[:70]!r}", flush=True)


if __name__ == '__main__':
    main()

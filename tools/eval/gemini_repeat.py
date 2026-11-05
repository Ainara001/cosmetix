"""Repeatability and speed of the photo analysis through the Cosmetix proxy.

Sends the SAME photo N times (default 3) to POST /v1/chat of server/ with the
exact prompt, JSON mode and temperature the app uses (the prompt is read from
lib/services/ai/vision_analyzer.dart, so it cannot drift), then reports:
  * latency of every call (wall clock, includes the proxy and Gemini),
  * whether the answer was valid JSON with the expected keys,
  * whether skinTone / undertone / colorType were identical in all N runs.

Only photos you are allowed to send (the licensed ones in photos_manifest.json)
should go through here: the image leaves this machine for Gemini.

    (cd server && GEMINI_API_KEY=... PORT=8799 HOST=127.0.0.1 node index.js) &
    tools/.venv/bin/python tools/eval/gemini_repeat.py p007 p014 p114 --runs 3
"""
import argparse
import base64
import json
import os
import re
import statistics
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
FIELDS = ['skinTone', 'undertone', 'colorType']
# the same accepted values and aliases as VisionAnalysis.parse in lib/models/ai_models.dart
TONE_ALIASES = {'very_light': 'very_light', 'fair': 'very_light', 'porcelain': 'very_light',
                'light': 'light', 'medium': 'medium', 'olive': 'medium',
                'tan': 'tan', 'dark': 'tan', 'deep': 'deep', 'very_dark': 'deep'}
ALLOWED = {'undertone': {'warm', 'cool', 'neutral'},
           'colorType': {'spring', 'summer', 'autumn', 'winter'}}


def norm(v):
    return re.sub(r'[\s-]+', '_', v.strip().lower()) if isinstance(v, str) else ''


def canon(obj):
    """Fields as the app would read them (aliases resolved); unsupported -> None."""
    return {'skinTone': TONE_ALIASES.get(norm(obj.get('skinTone'))),
            'undertone': norm(obj.get('undertone')) if norm(obj.get('undertone')) in ALLOWED['undertone'] else None,
            'colorType': norm(obj.get('colorType')) if norm(obj.get('colorType')) in ALLOWED['colorType'] else None}


def app_prompt() -> str:
    src = open(os.path.join(ROOT, 'lib', 'services', 'ai', 'vision_analyzer.dart'), encoding='utf-8').read()
    m = re.search(r"static const prompt = '''(.*?)''';", src, re.S)
    if not m:
        raise SystemExit('prompt not found in vision_analyzer.dart')
    return m.group(1).strip('\n')


def call(base, prompt, img_b64, timeout=90):
    body = json.dumps({'messages': [{'role': 'user', 'content': prompt, 'images': [img_b64]}],
                       'json': True, 'temperature': 0.2}).encode()
    req = urllib.request.Request(base + '/v1/chat', body, {'content-type': 'application/json'})
    t = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data, status = json.loads(r.read()), r.status
    except urllib.error.HTTPError as e:
        data, status = json.loads(e.read() or b'{}'), e.code
    except Exception as e:
        data, status = {'error': type(e).__name__, 'message': str(e)}, 0
    return status, data, (time.perf_counter() - t) * 1000


def parse(text):
    """Same tolerance as the app: a JSON object, maybe inside a code fence."""
    try:
        s = text.strip()
        s = re.sub(r'^```(?:json)?|```$', '', s, flags=re.M).strip()
        obj = json.loads(s)
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('photos', nargs='+', help='photo ids from photos_manifest.json, e.g. p007')
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--base', default='http://127.0.0.1:8799')
    ap.add_argument('--lang', default='Russian')
    ap.add_argument('--pause', type=float, default=3.5, help='seconds between calls (proxy limit: 20/min)')
    ap.add_argument('--out', default=os.path.join(HERE, 'out', 'gemini'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    prompt = app_prompt() + f'\nRequested language: {a.lang}.'
    health = json.loads(urllib.request.urlopen(a.base + '/health', timeout=10).read())
    print('proxy:', health)
    records = []
    for pid in a.photos:
        path = os.path.join(HERE, 'data', 'photos', pid + '.jpg')
        if not os.path.exists(path):
            raise SystemExit(f'no such photo: {path} (run fetch_photos.py)')
        raw = open(path, 'rb').read()
        b64 = base64.b64encode(raw).decode()
        for run in range(1, a.runs + 1):
            status, data, ms = call(a.base, prompt, b64)
            for attempt in range(3):          # polite retry on proxy rate limit / upstream 429
                if status != 429:
                    break
                time.sleep(15)
                status, data, ms = call(a.base, prompt, b64)
            obj = parse(data.get('text', '')) if status == 200 else None
            c = canon(obj) if obj else {}
            ok = bool(obj) and all(c.get(k) for k in FIELDS)     # all three fields usable
            rec = dict(photo=pid, run=run, status=status, ms=round(ms), valid=ok,
                       app_would_accept=bool(obj) and any(c.get(k) for k in FIELDS),
                       usage=data.get('usage'), error=data.get('error'),
                       **({**c, 'confidence': obj.get('confidence')} if obj else {}),
                       text=data.get('text') if status == 200 else data.get('message'))
            records.append(rec)
            print(pid, run, status, f'{ms:.0f} ms', 'valid' if ok else 'INVALID',
                  {k: rec.get(k) for k in FIELDS + ['confidence']})
            if not (pid == a.photos[-1] and run == a.runs):
                time.sleep(a.pause)
    json.dump(dict(proxy=health, runs=a.runs, prompt_chars=len(prompt), records=records),
              open(os.path.join(a.out, 'repeat.json'), 'w'), ensure_ascii=False, indent=1)

    lat = [r['ms'] for r in records if r['status'] == 200]
    print('\n== summary ==')
    print(f"calls {len(records)}, HTTP 200: {len(lat)}, valid JSON with allowed values: {sum(r['valid'] for r in records)}")
    if lat:
        print(f"latency ms: min {min(lat)}  median {statistics.median(lat):.0f}  mean {statistics.mean(lat):.0f}  max {max(lat)}")
    complete = [pid for pid in a.photos
                if len([r for r in records if r['photo'] == pid and r['valid']]) == a.runs]
    print(f'photos with all {a.runs} runs complete (all three fields usable): {len(complete)} of {len(a.photos)}')
    for f in FIELDS:
        same = sum(1 for pid in complete
                   if len({r.get(f) for r in records if r['photo'] == pid}) == 1)
        print(f'{f}: identical in all {a.runs} runs for {same} of {len(complete)} photos')
    full = sum(1 for pid in complete
               if all(len({r.get(f) for r in records if r['photo'] == pid}) == 1 for f in FIELDS))
    print(f'all three fields identical in all runs: {full} of {len(complete)} photos')


if __name__ == '__main__':
    main()

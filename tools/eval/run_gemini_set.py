"""Run the app's own photo prompt through the proxy on a whole folder, next to the quality gate.

For every photo: the gate verdict (photo_quality) and ONE Gemini answer (app prompt, JSON mode,
temperature 0.2): skinTone / undertone / colorType, the model's own `confidence`, the free-text
`observations` and `explanation`, and the latency. It then answers the question that matters
for the app: how many photos the gate would have refused did Gemini still answer with a
confidence the app accepts (BeautyProfileMerger.minConfidence = 0.6)?

    tools/.venv/bin/python tools/eval/run_gemini_set.py holdout [--manifest photos_holdout_manifest.json]

Only licensed photos from a manifest may be sent: the image leaves this machine.
"""
import argparse
import base64
import json
import os
import sys
import time

import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_zones as fz
import gemini_repeat as gr
import photo_quality as pq

HERE = os.path.dirname(os.path.abspath(__file__))
APP_MIN_CONFIDENCE = 0.6      # lib/services/ai/beauty_profile_merger.dart


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('set')
    ap.add_argument('--manifest', default='photos_manifest.json')
    ap.add_argument('--base', default='http://127.0.0.1:8799')
    ap.add_argument('--pause', type=float, default=3.5)
    ap.add_argument('--out', default=None)
    a = ap.parse_args()
    out = a.out or os.path.join(HERE, 'out', 'gemini_' + a.set + '.json')
    items = json.load(open(os.path.join(HERE, a.manifest), encoding='utf-8'))
    zoner = fz.FaceZoner()
    prompt = gr.app_prompt() + '\nRequested language: Russian.'
    recs = []
    for it in items:
        path = os.path.join(HERE, 'data', a.set, it['file'])
        raw = open(path, 'rb').read()
        bgr = cv2.imread(path)
        q = pq.assess(bgr, zoner)
        status, data, ms = gr.call(a.base, prompt, base64.b64encode(raw).decode())
        obj = gr.parse(data.get('text', '')) if status == 200 else None
        c = gr.canon(obj) if obj else {}
        conf = obj.get('confidence') if obj else None
        rec = dict(file=it['file'], tag=it.get('tag', ''), gate=q.verdict, gate_reasons=q.reasons,
                   status=status, ms=round(ms), app_would_accept=bool(obj) and any(c.values()),
                   confidence=conf, **c,
                   observations=(obj or {}).get('observations'), explanation=(obj or {}).get('explanation'),
                   error=None if status == 200 else (data.get('message') or data.get('error')))
        rec['enters_profile'] = bool(rec['app_would_accept'] and isinstance(conf, (int, float)) and conf >= APP_MIN_CONFIDENCE)
        recs.append(rec)
        print(it['file'], it.get('tag', ''), 'gate', q.verdict, '| gemini', status, c.get('skinTone'), c.get('undertone'),
              c.get('colorType'), 'conf', conf, '->', 'ENTERS PROFILE' if rec['enters_profile'] else 'not used')
        time.sleep(a.pause)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(recs, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    refused = [r for r in recs if r['gate'] == 'reject']
    print(f"\nphotos {len(recs)}; gate reject {len(refused)}; of those Gemini answered and the app would use it: "
          f"{sum(r['enters_profile'] for r in refused)}")


if __name__ == '__main__':
    main()

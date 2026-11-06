"""Parity of the phone check (Dart, real MediaPipe on a simulator) with the Python stand.

The Dart module is a port of `photo_quality.py`; this tells how close the port is on the SAME
photos. Input: the JSON written by `integration_test/photo_check_eval_test.dart` and the
`quality.csv` written by `run_face_eval.py`; optionally a judgement file to score the Dart verdicts.

    tools/.venv/bin/python tools/eval/compare_dart_python.py out/dart/eval.json out/eval/quality.csv [eval_judgement.json]
"""
import csv
import json
import math
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
KEYS = [('face_px', 'face_px'), ('sharpness', 'sharpness'), ('face_p95_luma', 'face_p95_luma'),
        ('skin_chroma', 'skin_chroma'), ('lr_asym', 'lr_asym'), ('yaw_offset', 'yaw_offset'),
        ('eye_dark_ratio', 'eye_dark_ratio'), ('eye_contrast', 'eye_contrast'), ('skin_visible', 'skin_visible')]


def main(argv):
    dart = {r['photo']: r for r in json.load(open(os.path.join(HERE, argv[0])))}
    py = {r['photo']: r for r in csv.DictReader(open(os.path.join(HERE, argv[1])))}
    j = json.load(open(os.path.join(HERE, argv[2]))) if len(argv) > 2 else None
    names = sorted(set(dart) & set(py))
    same = Counter()
    diffs = {k: [] for k, _ in KEYS}
    for n in names:
        d, p = dart[n]['verdict'], py[n]['verdict']
        same[d == p] += 1
        if d != p:
            print(f'verdict differs {n}: dart {d} {dart[n]["issues"]} | python {p} {py[n].get("reasons", "")[:80]}')
        m = dart[n].get('metrics')
        if not m or not py[n].get('face_px'):
            continue
        for k, pk in KEYS:
            try:
                pv, dv = float(py[n][pk]), float(m[k])
            except (KeyError, ValueError, TypeError):
                continue
            if not (math.isnan(pv) or math.isnan(dv)):
                diffs[k].append((dv - pv, pv, n))
    print(f'\nphotos compared: {len(names)}; same verdict: {same[True]}, different: {same[False]}')
    print('\n| metric | n | median abs diff | max abs diff | worst photo | median python value |')
    print('|---|---|---|---|---|---|')
    for k, xs in diffs.items():
        if not xs:
            continue
        a = sorted(abs(x[0]) for x in xs)
        worst = max(xs, key=lambda x: abs(x[0]))
        med = sorted(x[1] for x in xs)[len(xs) // 2]
        print(f'| {k} | {len(xs)} | {a[len(a) // 2]:.3f} | {a[-1]:.3f} | {worst[2]} | {med:.3f} |')
    if j:
        cells = Counter()
        for n, v in j.items():
            if n in dart:
                cells[(v['label'], dart[n]['verdict'])] += 1
        print('\n| my judgement \\ Dart verdict | ok | warn | reject | total |\n|---|---|---|---|---|')
        for lab, name in (('S', 'suitable'), ('M', 'marginal'), ('U', 'unsuitable')):
            row = [cells[(lab, v)] for v in ('ok', 'warn', 'reject')]
            print(f'| {name} | {row[0]} | {row[1]} | {row[2]} | {sum(row)} |')
        for n, v in sorted(j.items()):
            if n not in dart:
                continue
            if v['label'] == 'S' and dart[n]['verdict'] == 'reject':
                print('  false refusal:', n, v['why'], dart[n]['issues'])
            if v['label'] == 'U' and dart[n]['verdict'] != 'reject':
                print('  let through:', n, dart[n]['verdict'], v['why'], dart[n]['issues'])


if __name__ == '__main__':
    main(sys.argv[1:])

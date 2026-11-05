"""Markdown tables for the audit report, straight from the stand's output files.

    tools/.venv/bin/python tools/eval/summarize_results.py > tools/eval/out/summary.md
"""
import csv
import json
import os
import statistics
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = lambda *p: os.path.join(HERE, 'out', *p)


def holdout_gemini():
    recs = json.load(open(OUT('gemini_holdout.json')))
    judge = json.load(open(os.path.join(HERE, 'holdout_judgement.json')))
    print('### Gemini on the hold-out set (one answer per photo)\n')
    print(f'photos: {len(recs)}; HTTP 200: {sum(r["status"] == 200 for r in recs)}\n')
    print('| gate verdict | photos | Gemini answered with confidence >= 0.6 (the app would use it) | median confidence |')
    print('|---|---|---|---|')
    for v in ('ok', 'warn', 'reject'):
        rs = [r for r in recs if r['gate'] == v]
        conf = [r['confidence'] for r in rs if isinstance(r['confidence'], (int, float))]
        print(f"| {v} | {len(rs)} | {sum(r['enters_profile'] for r in rs)} | {statistics.median(conf):.2f} |" if conf else f'| {v} | 0 | 0 | n/a |')
    print('\n| my judgement of the photo | photos | the app would use the answer | median confidence |')
    print('|---|---|---|---|')
    for lab, name in (('S', 'suitable'), ('M', 'marginal'), ('U', 'unsuitable (no usable face)')):
        rs = [r for r in recs if judge[r['file'][:-4]]['label'] == lab]
        conf = [r['confidence'] for r in rs if isinstance(r['confidence'], (int, float))]
        print(f"| {name} | {len(rs)} | {sum(r['enters_profile'] for r in rs)} | {statistics.median(conf):.2f} |")
    print('\n| photo type | photos | used by the app | confidences |')
    print('|---|---|---|---|')
    by = defaultdict(list)
    for r in recs:
        by[r['tag']].append(r)
    for tag, rs in sorted(by.items()):
        print(f"| {tag} | {len(rs)} | {sum(r['enters_profile'] for r in rs)} | {', '.join(str(r['confidence']) for r in rs)} |")
    nf = [r for r in recs if r['tag'] in ('no_face', 'artwork')]
    print(f"\nlandscapes, buildings and drawings (no real face): {len(nf)}; the app would use the answer for {sum(r['enters_profile'] for r in nf)}")
    return recs


def wb_table(path, title):
    rows = list(csv.DictReader(open(path)))
    ok = lambda r: r.get('status', '200') == '200' and r.get('skinTone')
    base = {r['photo']: r for r in rows if r['condition'] == 'original' and ok(r)}
    conds = [c for c in dict.fromkeys(r['condition'] for r in rows) if c != 'original']
    print(f'\n### {title}\n')
    print('(only photos for which BOTH the original and the changed copy got a valid answer; n differs because the proxy daily budget ran out in the second run)\n')
    print('| change | n | median dL* | median db* (+ = warmer) | skinTone changed | undertone changed | colorType changed | any of the three |')
    print('|---|---|---|---|---|---|---|---|')
    for c in conds:
        rs = [r for r in rows if r['condition'] == c and ok(r) and r['photo'] in base]
        if not rs:
            print(f'| {c} | 0 | | | | | | |')
            continue
        n = len(rs)
        diff = lambda r, f: r.get(f) != base[r['photo']].get(f)
        ch = lambda f: sum(1 for r in rs if diff(r, f))
        anyc = sum(1 for r in rs if any(diff(r, f) for f in ('skinTone', 'undertone', 'colorType')))
        print(f"| {c} | {n} | {statistics.median(float(r['d_L']) for r in rs):+.1f} | {statistics.median(float(r['d_b']) for r in rs):+.1f} "
              f"| {ch('skinTone')} | {ch('undertone')} | {ch('colorType')} | {anyc} |")
    return rows


def wb_noise():
    f1, f2 = OUT('wb', 'wb_run1.csv'), OUT('wb', 'wb.csv')
    if not os.path.exists(f1):
        return
    r1 = {(r['photo'], r['condition']): r for r in csv.DictReader(open(f1))}
    r2 = {(r['photo'], r['condition']): r for r in csv.DictReader(open(f2))}
    pairs = [(r1[k], r2[k]) for k in r1 if k in r2 and r1[k].get('skinTone') and r2[k].get('skinTone')]
    diff = lambda a, b: [f for f in ('skinTone', 'undertone', 'colorType') if a.get(f) != b.get(f)]
    n = len(pairs)
    changed = [(a['photo'], a['condition'][:14], diff(a, b)) for a, b in pairs if diff(a, b)]
    print('\n### Noise control: the SAME image sent in two separate runs\n')
    print(f'identical inputs compared: {n}; answers that differ in any field: {len(changed)}  {changed}')


def wb():
    print('\n## White balance, light and filter: local measurement and Gemini')
    wb_table(OUT('wb', 'wb_run1.csv'), 'Run 1 (8 photos x 5 changes, complete)')
    wb_table(OUT('wb', 'wb.csv'), 'Run 2 (adds two stronger casts; partly cut off by the daily budget)')
    wb_noise()


def latency(recs):
    ms = [r['ms'] for r in recs if r['status'] == 200]
    rep = [r['ms'] for r in json.load(open(OUT('gemini', 'repeat.json')))['records'] if r['status'] == 200]
    allms = sorted(ms + rep)
    print(f"\n### Gemini latency (all {len(allms)} successful calls of repeatability + hold-out runs)\n")
    print(f"min {allms[0] / 1000:.1f} s, median {statistics.median(allms) / 1000:.1f} s, mean {statistics.mean(allms) / 1000:.1f} s, "
          f"p95 {allms[int(0.95 * (len(allms) - 1))] / 1000:.1f} s, max {allms[-1] / 1000:.1f} s")


if __name__ == '__main__':
    r = holdout_gemini()
    wb()
    latency(r)

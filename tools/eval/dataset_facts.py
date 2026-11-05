"""Counts from the PUBLIC METADATA files of SCIN and Fitzpatrick 17k (no images are downloaded).

    tools/.venv/bin/python tools/eval/dataset_facts.py

Downloads scin_cases.csv + scin_labels.csv (~2.2 MB, bucket dx-scin-public-data, SCIN Data Use
License) and fitzpatrick17k.csv (~4.1 MB, CC BY-NC-SA 3.0) into data/meta/, prints the tables
used in docs/skin-audit-report.md and writes out/dataset_facts.json.
Derived choices that are mine, not the datasets': "main label" = the condition with the largest
weight in SCIN's weighted_skin_condition_label; "eFST" = the median of the (up to 3)
dermatologist Fitzpatrick labels of a case.
"""
import ast
import collections
import csv
import hashlib
import json
import os
import statistics
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
META = os.path.join(HERE, 'data', 'meta')
FILES = {
    'scin_cases.csv': 'https://storage.googleapis.com/dx-scin-public-data/dataset/scin_cases.csv',
    'scin_labels.csv': 'https://storage.googleapis.com/dx-scin-public-data/dataset/scin_labels.csv',
    'fitzpatrick17k.csv': 'https://raw.githubusercontent.com/mattgroh/fitzpatrick17k/main/fitzpatrick17k.csv',
}


def fetch():
    os.makedirs(META, exist_ok=True)
    for name, url in FILES.items():
        dst = os.path.join(META, name)
        if not os.path.exists(dst):
            urllib.request.urlretrieve(url, dst)
        print(name, os.path.getsize(dst), 'bytes, sha256', hashlib.sha256(open(dst, 'rb').read()).hexdigest()[:16])


def scin():
    cases = {r['case_id']: r for r in csv.DictReader(open(os.path.join(META, 'scin_cases.csv'), encoding='utf-8'))}
    labels = {r['case_id']: r for r in csv.DictReader(open(os.path.join(META, 'scin_labels.csv'), encoding='utf-8'))}

    def wl(c):
        w = labels[c].get('weighted_skin_condition_label') or ''
        try:
            return ast.literal_eval(w) if w else {}
        except (ValueError, SyntaxError):
            return {}

    def efst(c):
        v = [labels[c].get(f'dermatologist_fitzpatrick_skin_type_label_{i}', '') for i in (1, 2, 3)]
        n = [int(x[3:]) for x in v if x.startswith('FST') and x[3:].isdigit()]
        return round(statistics.median(n)) if n else None

    yes = lambda r, k: r[k].upper() == 'YES'
    bp = [k for k in next(iter(cases.values())) if k.startswith('body_parts_')]
    head = {c for c, r in cases.items() if yes(r, 'body_parts_head_or_neck')}
    only_head = {c for c in head if not any(yes(cases[c], k) for k in bp if k != 'body_parts_head_or_neck')}
    out = {'cases': len(cases), 'head_or_neck': len(head), 'head_only': len(only_head),
           'no_derm_label': sum(1 for c in cases if not wl(c)),
           'efst': dict(sorted(collections.Counter(efst(c) for c in cases).items(), key=lambda x: (x[0] is None, x[0] or 0))),
           'labels': {}}
    for name in ['Acne', 'Scar Condition', 'Rosacea', 'Flushing', 'Post-Inflammatory hyperpigmentation', 'Melasma', 'Folliculitis']:
        anyl = {c for c in cases if name in wl(c)}
        top = {c for c in anyl if max(wl(c), key=wl(c).get) == name}
        out['labels'][name] = dict(any=len(anyl), top=len(top), top_head=len(top & head), top_head_only=len(top & only_head),
                                   top_head_efst=dict(sorted(collections.Counter(efst(c) for c in top & head).items(),
                                                             key=lambda x: (x[0] is None, x[0] or 0))))
    return out


def fitz():
    rows = list(csv.DictReader(open(os.path.join(META, 'fitzpatrick17k.csv'), encoding='utf-8')))
    lab = collections.Counter(r['label'] for r in rows)
    pick = lambda kw: {k: v for k, v in lab.items() if kw in k}
    return {'images': len(rows), 'conditions': len(lab), 'fst': dict(sorted(collections.Counter(r['fitzpatrick_scale'] for r in rows).items())),
            'acne': pick('acne'), 'scar': pick('scar'), 'rosacea': pick('rosacea'), 'keloid': pick('keloid'),
            'melasma': pick('melasma'), 'pigment': pick('pigment')}


def main():
    fetch()
    facts = {'scin': scin(), 'fitzpatrick17k': fitz()}
    os.makedirs(os.path.join(HERE, 'out'), exist_ok=True)
    json.dump(facts, open(os.path.join(HERE, 'out', 'dataset_facts.json'), 'w'), indent=1)
    print(json.dumps(facts, indent=1))


if __name__ == '__main__':
    main()

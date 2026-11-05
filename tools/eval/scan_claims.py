"""Does the model say things about the SKIN's condition that nothing measured?

The app prompt asks Gemini for tone, undertone, colour type and 'observations: short strings
about visible cosmetic characteristics', and forbids describing diseases or skin conditions.
The observations are shown to the user (lib/screens/beauty/color_result_screen.dart). This
script scans the saved model answers for statements about texture, redness, pigmentation,
acne, scars, wrinkles, oiliness / dryness, shine and 'healthy' skin, and prints how often they
appear and the verbatim examples. The keyword list is a heuristic of mine; read the examples.

    tools/.venv/bin/python tools/eval/scan_claims.py out/gemini/repeat.json out/gemini_holdout.json
"""
import json
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CATEGORIES = {
    'texture': r'текстур',
    'redness': r'покраснен|красн\w* (?:кож|пятен|участ)',
    'pigmentation': r'пигмент',
    'acne': r'акне|прыщ|высыпан|воспал|угр[еиь]|комедон',
    'scars': r'рубц|шрам|постакне',
    'wrinkles': r'морщин',
    'oil_dry_shine': r'сух\w* кож|жирн|блеск|сияни|увлажн|матов',
    'healthy': r'здоров',
    'freckles_pores': r'веснушк|\bпор[аыуе]\w*\b',
}


def records(path):
    data = json.load(open(path, encoding='utf-8'))
    if isinstance(data, dict) and 'records' in data:                      # gemini_repeat.py
        for r in data['records']:
            try:
                obj = json.loads(r['text'])
            except (TypeError, ValueError, KeyError):
                continue
            yield f"{r['photo']}#{r['run']}", obj.get('observations') or [], obj.get('explanation') or ''
    else:                                                                  # run_gemini_set.py
        for r in data:
            if r.get('status') == 200 and (r.get('observations') or r.get('explanation')):
                yield r['file'], r.get('observations') or [], r.get('explanation') or ''


def main(paths):
    n = 0
    runs_with = {'observations': 0, 'explanation': 0}
    per_cat = defaultdict(Counter)
    examples = defaultdict(list)
    for p in paths:
        for rid, obs, expl in records(p if os.path.isabs(p) else os.path.join(HERE, p)):
            n += 1
            hit_o = hit_e = False
            for field, texts in (('observations', obs), ('explanation', [expl])):
                for t in texts:
                    for cat, rx in CATEGORIES.items():
                        if re.search(rx, str(t), re.I):
                            per_cat[field][cat] += 1
                            if len(examples[cat]) < 4 and str(t) not in examples[cat]:
                                examples[cat].append(str(t))
                            if field == 'observations':
                                hit_o = True
                            else:
                                hit_e = True
            runs_with['observations'] += hit_o
            runs_with['explanation'] += hit_e
    print(f'answers scanned: {n}')
    print(f"answers whose OBSERVATIONS (shown to the user) contain at least one statement about skin condition: {runs_with['observations']}")
    print(f"answers whose EXPLANATION (not shown in the app) does: {runs_with['explanation']}")
    print('per category (statement count): observations', dict(per_cat['observations']), '| explanation', dict(per_cat['explanation']))
    for cat, ex in examples.items():
        print(f'  [{cat}]', ' || '.join(ex))
    json.dump({'answers': n, 'runs_with': runs_with, 'per_category': {k: dict(v) for k, v in per_cat.items()}, 'examples': examples},
              open(os.path.join(HERE, 'out', 'claims_scan.json'), 'w'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main(sys.argv[1:])

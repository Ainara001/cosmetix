"""Gate verdicts on the hold-out set against a person's judgement (holdout_judgement.json).

The judgement is ONE rater (the author of the stand), made by eye before looking at the
gate numbers of that photo: S = suitable for analysis, M = marginal, U = unsuitable
(turned > ~30 degrees, face too small / cut off / absent, black and white, blown out,
sunglasses plus dark, not a real face). It is not an independent ground truth.

    tools/.venv/bin/python tools/eval/holdout_agreement.py
    tools/.venv/bin/python tools/eval/holdout_agreement.py out/eval/quality.csv eval_judgement.json
"""
import csv
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))


def table(quality_csv=None, judgement=None):
    quality_csv = quality_csv or os.path.join(HERE, 'out', 'holdout', 'quality.csv')
    judgement = judgement or os.path.join(HERE, 'holdout_judgement.json')
    q = {r['photo']: r for r in csv.DictReader(open(quality_csv))}
    j = json.load(open(judgement))
    cells = Counter()
    for k, v in j.items():
        cells[(v['label'], q[k]['verdict'])] += 1
    return cells, q, j


def main():
    args = sys.argv[1:]
    cells, q, j = table(*(os.path.join(HERE, a) for a in args[:2]))
    print('| my judgement \\ gate | ok | warn | reject | total |')
    print('|---|---|---|---|---|')
    names = {'S': 'suitable', 'M': 'marginal', 'U': 'unsuitable'}
    for lab in 'SMU':
        row = [cells[(lab, v)] for v in ('ok', 'warn', 'reject')]
        print(f'| {names[lab]} | {row[0]} | {row[1]} | {row[2]} | {sum(row)} |')
    s_ref = cells[('S', 'reject')]
    s_n = sum(cells[('S', v)] for v in ('ok', 'warn', 'reject'))
    u_acc = cells[('U', 'ok')] + cells[('U', 'warn')]
    u_n = sum(cells[('U', v)] for v in ('ok', 'warn', 'reject'))
    print(f'\nsuitable photos refused by the gate (false refusal): {s_ref} of {s_n}')
    print(f'unsuitable photos let through (miss): {u_acc} of {u_n}')
    for k, v in j.items():
        if v['label'] == 'U' and q[k]['verdict'] != 'reject':
            print('  let through:', k, q[k]['verdict'], v['why'], '|', q[k]['reasons'])
        if v['label'] == 'S' and q[k]['verdict'] == 'reject':
            print('  refused:', k, v['why'], '|', q[k]['reasons'])


if __name__ == '__main__':
    main()

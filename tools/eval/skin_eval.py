"""Evaluation scaffold: labelled set + predictions -> confusion matrices and metrics.

Classes: acne, scar, redness (presence of the sign on the photo, 0/1). An
optional multi-class column (for example ACNE04 severity 0-3) gets a full
confusion matrix, accuracy, macro-F1 and quadratic-weighted kappa.

    labels.csv       image,acne,scar,redness[,severity][,source][,licence]
    predictions.csv  image,acne,scar,redness[,severity]

A blank cell means "no label" (labels) or "no answer" (predictions). Predictions
without an answer are counted as no_answer and are NOT silently dropped:
coverage is reported next to every metric.

    tools/.venv/bin/python tools/eval/skin_eval.py labels.csv predictions.csv [--md report.md]

The metrics come from the files you give it. With no labelled data of your own
there is nothing real to measure, and this script does not make numbers up.
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import Counter

CLASSES = ['acne', 'scar', 'redness']
MIN_POS_FOR_TRUST = 30     # below this many positives (or negatives) the numbers are marked unreliable


def read_csv(path, key='image'):
    with open(path, newline='', encoding='utf-8') as fh:
        rows = list(csv.DictReader(fh))
    out = {}
    for r in rows:
        if r.get(key) in out:
            raise ValueError(f'{path}: duplicate image {r[key]!r}')
        out[r[key]] = r
    return out


def to_bin(v):
    v = (v or '').strip().lower()
    if v == '':
        return None
    if v in ('1', 'true', 'yes'):
        return 1
    if v in ('0', 'false', 'no'):
        return 0
    raise ValueError(f'expected 0/1, got {v!r}')


def wilson(k: int, n: int, z: float = 1.96):
    """95% Wilson interval for a proportion k/n."""
    if n == 0:
        return (float('nan'), float('nan'))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def _div(a, b):
    return a / b if b else float('nan')


def binary_metrics(pairs):
    """pairs: list of (truth, pred) with pred in {0, 1, None}."""
    tp = sum(1 for t, p in pairs if t == 1 and p == 1)
    fn = sum(1 for t, p in pairs if t == 1 and p == 0)
    fp = sum(1 for t, p in pairs if t == 0 and p == 1)
    tn = sum(1 for t, p in pairs if t == 0 and p == 0)
    na = sum(1 for _, p in pairs if p is None)
    pos = sum(1 for t, _ in pairs if t == 1)
    neg = sum(1 for t, _ in pairs if t == 0)
    prec, rec, spec = _div(tp, tp + fp), _div(tp, tp + fn), _div(tn, tn + fp)
    f1 = _div(2 * prec * rec, prec + rec) if tp else (0.0 if (tp + fp + fn) else float('nan'))
    return dict(
        n=len(pairs), positives=pos, negatives=neg, no_answer=na,
        coverage=_div(len(pairs) - na, len(pairs)),
        tp=tp, fp=fp, fn=fn, tn=tn,
        precision=prec, recall=rec, specificity=spec, f1=f1,
        accuracy=_div(tp + tn, tp + tn + fp + fn),
        balanced_accuracy=(rec + spec) / 2 if rec == rec and spec == spec else float('nan'),
        recall_ci=wilson(tp, tp + fn), precision_ci=wilson(tp, tp + fp),
        specificity_ci=wilson(tn, tn + fp),
        unreliable=(pos < MIN_POS_FOR_TRUST or neg < MIN_POS_FOR_TRUST),
    )


def confusion_matrix(pairs, labels):
    """Rows = truth, columns = prediction (+ 'no answer')."""
    cm = {t: Counter() for t in labels}
    for t, p in pairs:
        cm[t]['no answer' if p is None else p] += 1
    return cm


def multiclass_metrics(pairs, labels):
    answered = [(t, p) for t, p in pairs if p is not None]
    n = len(answered)
    acc = _div(sum(1 for t, p in answered if t == p), n)
    f1s, per = [], {}
    for c in labels:
        tp = sum(1 for t, p in answered if t == c and p == c)
        fp = sum(1 for t, p in answered if t != c and p == c)
        fn = sum(1 for t, p in answered if t == c and p != c)
        pr, rc = _div(tp, tp + fp), _div(tp, tp + fn)
        f1 = _div(2 * pr * rc, pr + rc) if tp else (0.0 if (tp + fp + fn) else float('nan'))
        per[c] = dict(precision=pr, recall=rc, f1=f1, support=tp + fn)
        if tp + fn:
            f1s.append(f1)
    return dict(n=len(pairs), answered=n, accuracy=acc,
                macro_f1=sum(f1s) / len(f1s) if f1s else float('nan'),
                kappa_qw=weighted_kappa(answered, labels), per_class=per)


def weighted_kappa(answered, labels):
    """Quadratic-weighted Cohen's kappa for ordered labels (severity 0..3)."""
    idx = {c: i for i, c in enumerate(labels)}
    k, n = len(labels), len(answered)
    if n == 0 or k < 2:
        return float('nan')
    O = [[0.0] * k for _ in range(k)]
    for t, p in answered:
        O[idx[t]][idx[p]] += 1
    rows = [sum(O[i]) for i in range(k)]
    cols = [sum(O[i][j] for i in range(k)) for j in range(k)]
    num = den = 0.0
    for i in range(k):
        for j in range(k):
            w = ((i - j) / (k - 1)) ** 2
            num += w * O[i][j]
            den += w * rows[i] * cols[j] / n
    return 1 - num / den if den else float('nan')


def evaluate(labels, preds):
    """labels/preds: dicts image -> row. Returns a dict with everything."""
    missing = [i for i in labels if i not in preds]
    extra = [i for i in preds if i not in labels]
    result = dict(n_labelled=len(labels), n_missing_pred=len(missing), n_extra_pred=len(extra),
                  classes={}, severity=None)
    for c in CLASSES:
        pairs = []
        for img, row in labels.items():
            t = to_bin(row.get(c))
            if t is None:
                continue
            pairs.append((t, to_bin(preds.get(img, {}).get(c))))
        if pairs:
            m = binary_metrics(pairs)
            m['cm'] = confusion_matrix(pairs, [0, 1])
            result['classes'][c] = m
    if any((r.get('severity') or '').strip() for r in labels.values()):
        pairs = []
        for img, row in labels.items():
            t = (row.get('severity') or '').strip()
            if not t:
                continue
            p = (preds.get(img, {}).get('severity') or '').strip()
            pairs.append((int(t), int(p) if p else None))
        lab = sorted({t for t, _ in pairs} | {p for _, p in pairs if p is not None})
        mm = multiclass_metrics(pairs, lab)
        mm['labels'] = lab
        mm['cm'] = confusion_matrix(pairs, lab)
        result['severity'] = mm
    return result


def _f(x, pct=True):
    if x != x:
        return 'n/a'
    return f'{100 * x:.1f}%' if pct else f'{x:.3f}'


def render_md(res) -> str:
    out = [f"Labelled images: {res['n_labelled']}, without prediction row: {res['n_missing_pred']}, "
           f"predictions for unknown images: {res['n_extra_pred']}", '']
    for c, m in res['classes'].items():
        warn = ' **UNRELIABLE: too few positives or negatives (<%d)**' % MIN_POS_FOR_TRUST if m['unreliable'] else ''
        out += [f"### {c}{warn}", '',
                f"n={m['n']} (positives {m['positives']}, negatives {m['negatives']}), "
                f"no answer {m['no_answer']} (coverage {_f(m['coverage'])})", '',
                '| truth \\ prediction | 0 | 1 | no answer |', '|---|---|---|---|']
        for t in (0, 1):
            out.append(f"| {t} | {m['cm'][t][0]} | {m['cm'][t][1]} | {m['cm'][t]['no answer']} |")
        ci = lambda k: '[%s; %s]' % tuple(_f(v) for v in m[k])
        out += ['', '| metric | value | 95% CI (Wilson) |', '|---|---|---|',
                f"| precision | {_f(m['precision'])} | {ci('precision_ci')} |",
                f"| recall (sensitivity) | {_f(m['recall'])} | {ci('recall_ci')} |",
                f"| specificity | {_f(m['specificity'])} | {ci('specificity_ci')} |",
                f"| F1 | {_f(m['f1'])} | |", f"| accuracy | {_f(m['accuracy'])} | |",
                f"| balanced accuracy | {_f(m['balanced_accuracy'])} | |", '']
    s = res['severity']
    if s:
        out += ['### severity', '', f"n={s['n']}, answered {s['answered']}, accuracy {_f(s['accuracy'])}, "
                f"macro-F1 {_f(s['macro_f1'])}, quadratic-weighted kappa {_f(s['kappa_qw'], False)}", '',
                '| truth \\ prediction | ' + ' | '.join(map(str, s['labels'])) + ' | no answer |',
                '|---|' + '---|' * (len(s['labels']) + 1)]
        for t in s['labels']:
            out.append(f'| {t} | ' + ' | '.join(str(s['cm'][t][p]) for p in s['labels'])
                       + f" | {s['cm'][t]['no answer']} |")
        out.append('')
    return '\n'.join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('labels')
    ap.add_argument('predictions')
    ap.add_argument('--md', help='write the markdown report here')
    a = ap.parse_args(argv)
    res = evaluate(read_csv(a.labels), read_csv(a.predictions))
    md = render_md(res)
    print(md)
    if a.md:
        open(a.md, 'w', encoding='utf-8').write(md + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())

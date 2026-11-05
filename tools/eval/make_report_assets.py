"""Charts for docs/skin-audit-report.md, drawn from the CSV/JSON files the stand writes.

    tools/.venv/bin/python tools/eval/make_report_assets.py [out_dir]
Default out_dir: docs/skin-audit-assets. Every number in a chart comes from out/ files.
"""
import csv
import json
import os
import sys
from collections import Counter, defaultdict

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = lambda *p: os.path.join(HERE, 'out', *p)
BLUE, ORANGE, GREEN, RED, GRAY = '#2b6cb0', '#dd8452', '#55a868', '#c44e52', '#8c8c8c'
plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False, 'figure.dpi': 130})


def verdict_chart(dst):
    main = Counter(r['verdict'] for r in csv.DictReader(open(OUT('face', 'quality.csv'))))
    j = json.load(open(os.path.join(HERE, 'holdout_judgement.json')))
    q = {r['photo']: r['verdict'] for r in csv.DictReader(open(OUT('holdout', 'quality.csv')))}
    rows = [('main set (24 photos)', main)]
    names = {'S': 'hold-out: suitable (my judgement)', 'M': 'hold-out: marginal', 'U': 'hold-out: unsuitable'}
    for lab in 'SMU':
        rows.append((f"{names[lab]}", Counter(q[k] for k, v in j.items() if v['label'] == lab)))
    fig, ax = plt.subplots(figsize=(7.5, 3.2))
    y = np.arange(len(rows))[::-1]
    left = np.zeros(len(rows))
    for verdict, color in (('ok', GREEN), ('warn', ORANGE), ('reject', RED)):
        vals = np.array([c[verdict] for _, c in rows], float)
        tot = np.array([sum(c.values()) for _, c in rows], float)
        w = 100 * vals / tot
        ax.barh(y, w, left=left, color=color, label=verdict)
        for yi, wi, li, v in zip(y, w, left, vals):
            if v:
                ax.text(li + wi / 2, yi, int(v), ha='center', va='center', color='white', fontsize=9)
        left += w
    ax.set_yticks(y)
    ax.set_yticklabels([f'{n}  (n={sum(c.values())})' for n, c in rows])
    ax.set_xlabel('% of photos')
    ax.set_title('Quality gate verdicts (numbers in bars = photos)', fontsize=10)
    ax.legend(ncol=3, loc='lower center', bbox_to_anchor=(0.5, -0.45), frameon=False)
    fig.tight_layout()
    fig.savefig(dst)
    plt.close(fig)


def synthetic_chart(dst):
    rows = list(csv.DictReader(open(OUT('face', 'quality_synthetic.csv'))))
    kinds = list(dict.fromkeys(r['kind'] for r in rows))
    fig, axes = plt.subplots(1, 2, figsize=(9, 3.4), sharey=True)
    for ax, key, title in ((axes[0], 'flagged', 'flagged (warn or reject)'), (axes[1], 'rejected', 'rejected')):
        for kind, color in zip(kinds, (BLUE, ORANGE, GREEN, RED)):
            rs = [r for r in rows if r['kind'] == kind]
            ax.plot([int(r['level']) for r in rs], [100 * int(r[key]) / int(r['n']) for r in rs], marker='o', color=color,
                    label=kind.split(' (')[0])
        ax.set_xticks([1, 2, 3, 4])
        ax.set_xlabel('strength of the defect (1 = weakest)')
        ax.set_title(title)
        ax.set_ylim(-3, 103)
    axes[0].set_ylabel('% of degraded copies')
    axes[1].legend(frameon=False, fontsize=8, loc='lower right')
    fig.suptitle(f"Synthetic defects on {rows[0]['n']} photos the gate had passed", y=1.02)
    fig.tight_layout()
    fig.savefig(dst, bbox_inches='tight')
    plt.close(fig)


def wb_chart(dst):
    rows = list(csv.DictReader(open(OUT('wb', 'wb.csv'))))
    conds = [c for c in dict.fromkeys(r['condition'] for r in rows) if c != 'original']
    has_g = 'colorType' in rows[0]
    fig, axes = plt.subplots(1, 2 if has_g else 1, figsize=(10 if has_g else 6, 3.6))
    axes = np.atleast_1d(axes)
    for i, c in enumerate(conds):
        d = [float(r['d_b']) for r in rows if r['condition'] == c]
        axes[0].scatter([i] * len(d), d, color=BLUE, alpha=0.8)
        axes[0].plot([i - 0.25, i + 0.25], [np.median(d)] * 2, color='black')
    axes[0].axhline(0, color=GRAY, lw=0.8)
    axes[0].set_xticks(range(len(conds)))
    axes[0].set_xticklabels([c.split(' (')[0] for c in conds], rotation=25, ha='right')
    axes[0].set_ylabel('change of skin b* (+ = warmer)')
    axes[0].set_title('Local skin measurement vs the original\n(dots = photos, line = median)', fontsize=10)
    if has_g:
        base = {r['photo']: r for r in rows if r['condition'] == 'original'}
        for k, (f, color) in enumerate((('skinTone', BLUE), ('undertone', ORANGE), ('colorType', GREEN))):
            share = []
            for c in conds:
                rs = [r for r in rows if r['condition'] == c and r.get(f) and base[r['photo']].get(f)]
                share.append(100 * sum(r[f] != base[r['photo']][f] for r in rs) / max(1, len(rs)))
            axes[1].bar(np.arange(len(conds)) + (k - 1) * 0.27, share, 0.27, color=color, label=f)
        axes[1].set_xticks(range(len(conds)))
        axes[1].set_xticklabels([c.split(' (')[0] for c in conds], rotation=25, ha='right')
        ns = [sum(1 for r in rows if r['condition'] == c and r.get('skinTone') and base.get(r['photo'], {}).get('skinTone')) for c in conds]
        for i, n in enumerate(ns):
            axes[1].text(i, 52, f'n={n}', ha='center', fontsize=8)
        axes[1].set_ylim(0, 58)
        axes[1].set_ylabel('% of photos where the answer changed')
        axes[1].set_title('Gemini: answer differs from the original photo\n(run 2, partly cut off by the daily budget)', fontsize=10)
        axes[1].legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(dst)
    plt.close(fig)


def latency_chart(dst):
    ms = [r['ms'] for r in json.load(open(OUT('gemini', 'repeat.json')))['records'] if r['status'] == 200]
    if os.path.exists(OUT('gemini_holdout.json')):
        ms += [r['ms'] for r in json.load(open(OUT('gemini_holdout.json'))) if r['status'] == 200]
    s = np.array(ms) / 1000
    fig, ax = plt.subplots(figsize=(6, 3))
    ax.hist(s, bins=np.arange(0, max(s) + 2, 1.0), color=BLUE)
    ax.axvline(np.median(s), color=RED)
    ax.text(np.median(s) + 0.2, ax.get_ylim()[1] * 0.9, f'median {np.median(s):.1f} s', color=RED)
    ax.set_xlabel('seconds per photo analysis through the proxy')
    ax.set_ylabel('calls')
    ax.set_title(f'Gemini latency, {len(s)} calls (max {s.max():.0f} s)')
    fig.tight_layout()
    fig.savefig(dst)
    plt.close(fig)


def tone_chart(dst):
    f = json.load(open(OUT('dataset_facts.json')))
    scin = {k: v for k, v in f['scin']['efst'].items() if k not in ('None', 'null')}
    fz = {k: v for k, v in f['fitzpatrick17k']['fst'].items() if k != '-1'}
    fig, ax = plt.subplots(figsize=(6.5, 3.2))
    for k, (d, name, color) in enumerate(((scin, 'SCIN (dermatologist eFST, median)', BLUE), (fz, 'Fitzpatrick 17k (annotators)', ORANGE))):
        tot = sum(d.values())
        ax.bar(np.arange(1, 7) + (k - 0.5) * 0.38, [100 * d.get(str(i), 0) / tot for i in range(1, 7)], 0.38, color=color,
               label=f'{name}, n={tot}')
    ax.set_xlabel('Fitzpatrick skin type')
    ax.set_ylabel('% of images with a type label')
    ax.set_title('Skin-tone coverage of the open datasets')
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(dst)
    plt.close(fig)


def zones_chart(dst):
    d = json.load(open(OUT('old_vs_new_zones.json')))
    zs = ['forehead', 'cheek_right', 'cheek_left', 'nose', 'chin']
    fig, ax = plt.subplots(figsize=(6.5, 3.2))
    ax.bar(np.arange(5) - 0.2, [d[z]['old_mean'] for z in zs], 0.4, color=GRAY, label='draft (convex hulls)')
    ax.bar(np.arange(5) + 0.2, [d[z]['new_mean'] for z in zs], 0.4, color=BLUE, label='current')
    ax.set_xticks(range(5))
    ax.set_xticklabels(zs)
    ax.set_ylabel('% of the face oval (mean)')
    ax.set_title(f"Zone size on {d['photos']} frontal photos")
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(dst)
    plt.close(fig)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'docs', 'skin-audit-assets')
    os.makedirs(out, exist_ok=True)
    for name, fn in (('fig1_gate_verdicts.png', verdict_chart), ('fig2_synthetic_defects.png', synthetic_chart),
                     ('fig3_white_balance.png', wb_chart), ('fig4_gemini_latency.png', latency_chart),
                     ('fig5_skin_tone_coverage.png', tone_chart), ('fig6_zone_sizes.png', zones_chart)):
        try:
            fn(os.path.join(out, name))
            print('wrote', name)
        except FileNotFoundError as e:
            print('skipped', name, '- missing', e.filename)


if __name__ == '__main__':
    main()

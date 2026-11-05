"""Markdown tables from the results.json of integration_test/virtual_makeup_eval_test.dart.

    python3 tools/eval/summarize_tryon.py results.json [before_fix_results.json]

Prints, for the photos where exactly one face was found: the checks that must be
zero, the spread (min / median / max) of every measured number, the colour
numbers by skin lightness group, and one row per photo. No number here is an
accuracy: there are no labelled zones, only measurements on these photos.
"""
import json
import statistics as st
import sys


def load(path):
    return [x for x in json.load(open(path)) if x.get('faces') == 1]


def spread(rows, key, skip=(None, -1)):
    v = [x[key] for x in rows if x.get(key) not in skip]
    if not v:
        return '-'
    return f'{min(v):.1f} / {st.median(v):.1f} / {max(v):.1f}'


def main():
    rows = load(sys.argv[1])
    before = load(sys.argv[2]) if len(sys.argv) > 2 else None
    print(f'Photos with exactly one face: {len(rows)}\n')
    print('| Check (must be 0) | Result |\n|---|---|')
    print(f"| pixels changed outside every zone | {sum(x['changed_outside_zones_px'] for x in rows)} |")
    print(f"| protected pixels checked (all three kinds on) | {sum(x['protected_px'] for x in rows)} |")
    print(f"| protected pixels that changed | {sum(x['protected_changed_px'] for x in rows)} |\n")

    leak = [
        ('eye_core_changed_pct', '% of the deep inside of the open eye that changed'),
        ('shadow_paint_in_eye_pct', '% of the eyeshadow paint that lies on the open eye'),
        ('mouth_core_changed_pct', '% of the deep inside of the open mouth that changed (photos with an open mouth only)'),
        ('lips_paint_in_mouth_pct', '% of the lipstick paint that lies inside the mouth'),
        ('shadow_on_brow_pct', '% of the eyeshadow paint on the eyebrow ring'),
        ('detail_lips_pct', 'fine detail kept in the lips, %'),
        ('detail_blush_pct', 'fine detail kept in the blush area, %'),
        ('detail_shadow_pct', 'fine detail kept in the eyeshadow area, %'),
    ]
    head = '| Measure (min / median / max) | after the fix |' + (' before the fix |' if before else '')
    print(head)
    print('|---|---|' + ('---|' if before else ''))
    for k, label in leak:
        line = f'| {label} | {spread(rows, k)} |'
        if before:
            line += f' {spread(before, k)} |'
        print(line)

    print('\nColour, by skin lightness group (L* of the visible skin: light >= 65, medium 50-65, dark < 50;')
    print('thresholds are mine and arbitrary). dE00 = CIEDE2000, min / median / max.\n')
    print('| Product on | group | n | start: lips vs product | 60 %: result vs product | 100 %: result vs product | 100 %: dL of the zone |')
    print('|---|---|---|---|---|---|---|')
    for tag, label in [('lips_berry', 'lips, Happy Berry'), ('lips_rose', 'lips, Rose In Mind'),
                       ('blush_cheek', 'blush, Better Than Cheek'), ('shadow_hand', 'eyeshadow, hand-picked mauve')]:
        for g in ['light', 'medium', 'dark']:
            r = [x for x in rows if x['tone_group'] == g]
            print(f"| {label} | {g} | {len(r)} | {spread(r, tag + '_dE00_start_to_product')} | "
                  f"{spread(r, tag + '_60_dE00_to_product')} | {spread(r, tag + '_100_dE00_to_product')} | "
                  f"{spread(r, tag + '_100_dL')} |")

    print('\nSpeed on the machine that ran it (ms, min / median / max):\n')
    print('| Step | ms |\n|---|---|')
    for k, label in [('t_detect_ms', 'find the face (MediaPipe)'), ('t_prepare_ms', 'zone masks'),
                     ('t_render_first_ms', 'first render (colours prepared)'),
                     ('t_render_cached_ms', 'render again'), ('t_switch_shade_ms', 'render another shade')]:
        print(f'| {label} | {spread(rows, k)} |')

    print('\nPer photo:\n')
    print('| photo | licence | size | skin L* | group | warnings | open mouth % fw | eye core changed % | lips-on-mouth % | lips dE00 to Happy Berry (100 %) | lips detail kept % |')
    print('|---|---|---|---|---|---|---|---|---|---|---|')
    for x in rows:
        print(f"| {x['file']} | {x.get('licence')} | {x['size']} | {x['skin_L']:.0f} | {x['tone_group']} | "
              f"{x['issues'] or '-'} | {x['mouth_open_pct_fw']:.1f} | {x['eye_core_changed_pct']:.0f} | "
              f"{x['lips_paint_in_mouth_pct']:.1f} | {x['lips_berry_100_dE00_to_product']:.1f} | {x['detail_lips_pct']:.0f} |")


if __name__ == '__main__':
    main()

"""Markdown comparison of two engines on the same photos.

    python3 tools/eval/compare_engines.py old_results.json new_results.json

Both files come from integration_test/virtual_makeup_eval_test.dart (run once per
engine with --dart-define=EVAL_ENGINE=transfer|pigment). Only photos with exactly
one face are used. min / median / max over the photos; no accuracy is claimed.
"""
import json
import statistics as st
import sys


def load(p):
    return [x for x in json.load(open(p)) if x.get('faces') == 1]


def sp(rows, k, skip=(None, -1)):
    v = [x[k] for x in rows if x.get(k) not in skip]
    return f'{min(v):.1f} / {st.median(v):.1f} / {max(v):.1f}' if v else '-'


def med(rows, k):
    v = [x[k] for x in rows if x.get(k) is not None]
    return f'{st.median(v):.1f}' if v else '-'


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    ea, eb = a[0].get('engine', 'old'), b[0].get('engine', 'new')
    print(f'Engines: old = `{ea}`, new = `{eb}`; photos: {len(a)}\n')
    print('| Check (must be 0) | old | new |\n|---|---|---|')
    print(f"| pixels changed outside every zone | {sum(x['changed_outside_zones_px'] for x in a)} | {sum(x['changed_outside_zones_px'] for x in b)} |")
    print(f"| protected pixels that changed (of {sum(x['protected_px'] for x in b)}) | {sum(x['protected_changed_px'] for x in a)} | {sum(x['protected_changed_px'] for x in b)} |\n")
    rows = [
        ('lips_dark_turned_blue_pct', '% of the dark pixels of the lips that BECAME blue'),
        ('lips_bright_colourless_painted_pct', '% of the bright colourless pixels of the lips (teeth, nail, highlight) that were painted'),
        ('eye_core_changed_pct', '% of the deep inside of the open eye that changed'),
        ('mouth_core_changed_pct', '% of the deep inside of the open mouth that changed (open mouths only)'),
        ('lips_paint_in_mouth_pct', '% of the lipstick paint inside the mouth'),
        ('detail_lips_pct', 'fine detail of the lips, L* contrast kept, %'),
        ('detail_blush_pct', 'fine detail of the blush area (L*), %'),
        ('detail_shadow_pct', 'fine detail of the eyeshadow area (L*), %'),
        ('detaillog_lips_pct', 'relative (log-luminance) contrast of the lips kept, %'),
        ('detaillog_blush_pct', 'relative contrast of the blush area kept, %'),
        ('detaillog_shadow_pct', 'relative contrast of the eyeshadow area kept, %'),
        ('blush_result_b', 'blush zone b* after (yellow-blue; the skin before is in the next row)'),
        ('blush_skin_b', 'blush zone b* of the skin before'),
        ('t_render_first_ms', 'first render, ms (colours prepared)'),
        ('t_render_cached_ms', 'render again, ms'),
        ('t_switch_shade_ms', 'render another shade, ms'),
    ]
    print('| Measure (min / median / max) | old | new |\n|---|---|---|')
    for k, label in rows:
        print(f'| {label} | {sp(a, k)} | {sp(b, k)} |')

    print('\nMedian dE00 between the zone colour after the makeup and the product colour, by skin lightness group'
          ' (L* of the visible skin: light >= 65, medium 50-65, dark < 50; my arbitrary thresholds). Chroma = % of the'
          ' product chroma left in the zone (low = greyed).\n')
    print('| Product on | group | n | 60 %: old | 60 %: new | 100 %: old | 100 %: new | chroma at 100 %: old | new |')
    print('|---|---|---|---|---|---|---|---|---|')
    for tag, label in [('lips_berry', 'lips, Happy Berry (estimate)'), ('lips_rose', 'lips, Rose In Mind (estimate)'),
                       ('blush_cheek', 'blush, Better Than Cheek (estimate)'), ('shadow_hand', 'eyeshadow, mauve (test colour)'),
                       ('shadow_teal', 'eyeshadow, teal (test colour)'), ('shadow_violet', 'eyeshadow, violet (test colour)'),
                       ('shadow_peach', 'eyeshadow, peach (test colour)')]:
        for g in ['light', 'medium', 'dark']:
            ra = [x for x in a if x['tone_group'] == g]
            rb = [x for x in b if x['tone_group'] == g]
            print(f"| {label} | {g} | {len(ra)} | {med(ra, tag + '_60_dE00_to_product')} | {med(rb, tag + '_60_dE00_to_product')} | "
                  f"{med(ra, tag + '_100_dE00_to_product')} | {med(rb, tag + '_100_dE00_to_product')} | "
                  f"{med(ra, tag + '_100_chroma_pct')} | {med(rb, tag + '_100_chroma_pct')} |")

    print('\nPhotos where the lips texture (L* contrast kept) leaves 80-120 % in the new engine:\n')
    print('| photo | group | old % | new % |\n|---|---|---|---|')
    ia = {x['file']: x for x in a}
    for x in b:
        v = x.get('detail_lips_pct')
        if v is not None and not 80 <= v <= 120:
            print(f"| {x['file']} | {x['tone_group']} | {ia[x['file']]['detail_lips_pct']:.0f} | {v:.0f} |")


if __name__ == '__main__':
    main()

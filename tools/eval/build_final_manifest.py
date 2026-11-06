"""Draw the INDEPENDENT final set (round 2): photos used neither to choose a threshold nor in the
first evaluation set. Seed 2028; skips every photo of photos_manifest.json, photos_holdout_manifest.json
and photos_eval_manifest.json. More skin tones and more occlusions (hands on the face, masks of
faces: wax figures, mannequins, statues, paintings).

    python3 tools/eval/build_final_manifest.py
    python3 tools/eval/fetch_photos.py photos_final_manifest.json final --record-hashes

A person then looks at the raw photos, removes minors and writes final_judgement.json BEFORE the gate
is run. The thresholds are not touched after that.
"""
import build_eval_manifest as e

PLAN = [
    ('selfie', 'Selfies', 10), ('selfie', 'Selfies of women', 6), ('selfie', 'Selfies of men', 6),
    ('sunglasses', 'Women wearing sunglasses', 3), ('sunglasses', 'Men wearing sunglasses', 3),
    ('makeup', 'Women wearing make-up', 3), ('group', 'Group portraits', 3),
    ('beard', 'Men with beards', 4), ('glasses', 'Women wearing glasses', 3),
    ('glasses', 'Men wearing glasses', 3), ('elderly', 'Portrait photographs of old women', 3),
    ('hand', 'Facepalms', 5), ('hat', 'Women with hats', 3), ('camera', 'Self-portrait photographs', 3),
    ('not_real', 'Portrait paintings', 4), ('not_real', 'Wax figures', 3), ('not_real', 'Mannequins', 3),
    ('not_real', 'Statues of people', 2), ('backlight', 'Silhouettes of people', 1),
    ('no_face', 'Featured pictures of landscapes', 2), ('no_face', 'Featured pictures of buildings', 2),
] + [('portrait', f'Portrait photographs of {c}', n) for c, n in
     [('Ethiopia', 4), ('Iran', 3), ('Japan', 3), ('Brazil', 3), ('Bangladesh', 3), ('Armenia', 3),
      ('Nigeria', 3), ('Turkey', 3), ('Peru', 2), ('Russia', 3), ('India', 3), ('Cuba', 3)]]

if __name__ == '__main__':
    e.main(seed=2028, plan=PLAN, prefix='f', out_name='photos_final_manifest.json',
           skip=('photos_manifest.json', 'photos_holdout_manifest.json', 'photos_eval_manifest.json'))

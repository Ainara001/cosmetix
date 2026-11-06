"""Draw the FINAL EVALUATION set: fresh licensed photos never used to choose a threshold.

Same method as build_holdout_manifest.py with a different seed, and with portrait categories of
several countries added so that many skin tones are in the set. Photos already in
photos_manifest.json (development) or photos_holdout_manifest.json (development) are skipped.

    python3 tools/eval/build_eval_manifest.py
    python3 tools/eval/fetch_photos.py photos_eval_manifest.json eval --record-hashes

After that a person looks at the raw photos (not at any gate output), removes minors and unsuitable
images and writes eval_judgement.json BEFORE the gate is run on the set.
"""
import json
import os
import random

import build_holdout_manifest as b

HERE = os.path.dirname(os.path.abspath(__file__))
SEED = 2027
COUNTRIES = ['Ethiopia', 'India', 'Madagascar', 'Iran', 'Japan', 'Mexico', 'Brazil', 'Bangladesh',
             'Kazakhstan', 'Cuba', 'Egypt', 'Armenia']
PLAN = [
    ('selfie', 'Selfies', 8),
    ('selfie', 'Selfies of women', 5),
    ('selfie', 'Selfies of men', 5),
    ('sunglasses', 'Women wearing sunglasses', 3),
    ('sunglasses', 'Men wearing sunglasses', 3),
    ('makeup', 'Women wearing make-up', 3),
    ('group', 'Group portraits', 3),
    ('backlight', 'Silhouettes of people', 1),
    ('beard', 'Men with beards', 3),
    ('glasses', 'Women wearing glasses', 3),
    ('glasses', 'Men wearing glasses', 3),
    ('elderly', 'Portrait photographs of old women', 3),
    ('no_face', 'Featured pictures of landscapes', 2),
    ('no_face', 'Featured pictures of buildings', 2),
] + [('portrait', f'Portrait photographs of {c}', 3) for c in COUNTRIES]


def main():
    b.SEED = SEED
    b.PLAN = PLAN
    seen = set()
    for name in ('photos_manifest.json', 'photos_holdout_manifest.json'):
        seen |= {x['commons_title'] for x in json.load(open(os.path.join(HERE, name), encoding='utf-8'))}
    rng = random.Random(SEED)
    out, taken = [], set(seen)
    for tag, cat, n in PLAN:
        files = b.members(cat)
        rng.shuffle(files)
        got = 0
        for i in range(0, len(files), 20):
            if got >= n:
                break
            d = b.api(action='query', titles='|'.join(files[i:i + 20]), prop='imageinfo',
                      iiprop='extmetadata|size|mime', iiextmetadatafilter='LicenseShortName|Artist')
            for pg in d['query']['pages'].values():
                ii = (pg.get('imageinfo') or [{}])[0]
                lic = ii.get('extmetadata', {}).get('LicenseShortName', {}).get('value', '')
                if got >= n or pg['title'] in taken or ii.get('mime') != 'image/jpeg':
                    continue
                if min(ii['width'], ii['height']) < 700 or not b.OK.match(lic):
                    continue
                taken.add(pg['title'])
                artist = b.re.sub(r'\s+', ' ', b.re.sub('<[^>]+>', '', ii['extmetadata'].get('Artist', {}).get('value', ''))).strip()
                out.append(dict(file=f'e{len(out):03d}.jpg', tag=tag, commons_category=cat,
                                commons_title=pg['title'], license=lic, author=artist[:120],
                                page='https://commons.wikimedia.org/wiki/' + b.urllib.parse.quote(pg['title'].replace(' ', '_'))))
                got += 1
        print(tag, cat, got, 'of', n)
    json.dump(out, open(os.path.join(HERE, 'photos_eval_manifest.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('written', len(out))


if __name__ == '__main__':
    main()

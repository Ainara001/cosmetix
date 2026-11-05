"""Draw a hold-out / stress set of licensed photos from Wikimedia Commons categories.

The thresholds of photo_quality.py were chosen on the 24 photos of photos_manifest.json.
To see how they behave on photos they were NOT tuned on, this script draws a random
sample (fixed seed) from Commons categories that match real selfie problems: selfies,
sunglasses, make-up, group photos, silhouettes / backlight, beards, glasses, elderly
faces, and non-face pictures. Only CC0 / CC BY / CC BY-SA / public domain JPEGs of at
least 700 px are kept. The result is photos_holdout_manifest.json; after that a person
looks at the sheet and removes minors and anything unsuitable (the only manual step,
done by eye and by reason of privacy, not by how the photo scores).

    python3 tools/eval/build_holdout_manifest.py
    python3 tools/eval/fetch_photos.py photos_holdout_manifest.json holdout --record-hashes
"""
import json
import os
import random
import re
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = {'User-Agent': 'cosmetix-eval/0.2 (student project; face-zone evaluation)'}
SEED = 2026
OK = re.compile(r'^(CC0|CC BY( |-SA )?[\d.]*|Public domain|PDM.*)', re.I)
# (tag, commons category, how many)
PLAN = [
    ('selfie', 'Selfies', 10),
    ('selfie', 'Selfies of women', 5),
    ('selfie', 'Selfies of men', 5),
    ('sunglasses', 'Women wearing sunglasses', 3),
    ('sunglasses', 'Men wearing sunglasses', 3),
    ('makeup', 'Women wearing make-up', 5),
    ('group', 'Group portraits', 4),
    ('backlight', 'Silhouettes of people', 4),
    ('beard', 'Men with beards', 5),
    ('glasses', 'Women wearing glasses', 3),
    ('glasses', 'Men wearing glasses', 3),
    ('elderly', 'Portrait photographs of old women', 4),
    ('no_face', 'Featured pictures of landscapes', 3),
    ('no_face', 'Featured pictures of buildings', 3),
]


def api(**p):
    p['format'] = 'json'
    for k in range(5):
        try:
            r = json.load(urllib.request.urlopen(urllib.request.Request(
                'https://commons.wikimedia.org/w/api.php?' + urllib.parse.urlencode(p), headers=UA), timeout=40))
            time.sleep(1.5)       # be polite: Commons answers 429 to fast clients
            return r
        except Exception as e:
            print('  retry', e)
            time.sleep(15 * (k + 1))
    raise SystemExit('Commons API failed')


def members(cat, limit=1500):
    files, cont = [], {}
    while len(files) < limit:
        d = api(action='query', list='categorymembers', cmtitle='Category:' + cat,
                cmlimit=500, cmtype='file', **cont)
        files += [m['title'] for m in d['query']['categorymembers']]
        if 'continue' not in d:
            break
        cont = d['continue']
    return files


def main():
    rng = random.Random(SEED)
    out, seen = [], set()
    for tag, cat, n in PLAN:
        files = members(cat)
        rng.shuffle(files)
        got = 0
        for i in range(0, len(files), 20):
            if got >= n:
                break
            d = api(action='query', titles='|'.join(files[i:i + 20]), prop='imageinfo',
                    iiprop='extmetadata|size|mime', iiextmetadatafilter='LicenseShortName|Artist')
            for pg in d['query']['pages'].values():
                ii = (pg.get('imageinfo') or [{}])[0]
                lic = ii.get('extmetadata', {}).get('LicenseShortName', {}).get('value', '')
                if got >= n or pg['title'] in seen or ii.get('mime') != 'image/jpeg':
                    continue
                if min(ii['width'], ii['height']) < 700 or not OK.match(lic):
                    continue
                seen.add(pg['title'])
                artist = re.sub(r'\s+', ' ', re.sub('<[^>]+>', '', ii['extmetadata'].get('Artist', {}).get('value', ''))).strip()
                out.append(dict(file=f'h{len(out):03d}.jpg', tag=tag, commons_category=cat,
                                commons_title=pg['title'], license=lic, author=artist[:120],
                                page='https://commons.wikimedia.org/wiki/' + urllib.parse.quote(pg['title'].replace(' ', '_'))))
                got += 1
        print(tag, cat, got, 'of', n)
    json.dump(out, open(os.path.join(HERE, 'photos_holdout_manifest.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('written', len(out))


if __name__ == '__main__':
    main()

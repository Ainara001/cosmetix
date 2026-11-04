"""Builds data/fragrance_allergens.json from the consolidated Cosmetics Regulation.

Source: Regulation (EC) No 1223/2009, Annex III, consolidated version of
2023-08-16 (it already contains the amendments of Regulation (EU) 2023/1545).
The entries kept are the ones whose conditions say that the substance must be
indicated in the list of ingredients (the labelling of fragrance allergens).

    curl -sL -H "Accept: application/xhtml+xml" -H "Accept-Language: en" \
      -o cons.xhtml https://publications.europa.eu/resource/celex/02009R1223-20230816
    python3 tools/build_allergen_list.py cons.xhtml data/fragrance_allergens.json

The consolidated text is a documentation tool and has no legal effect; the
Official Journal is authoritative.
"""
import html, json, re, sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8', errors='ignore').read()
a, b = s.find('ANNEX III'), s.find('ANNEX IV')
rows = re.findall(r'<tr>(.*?)</tr>', s[a:b], flags=re.S)
out = []
current = None
for r in rows:
    cells = re.findall(r'<td[^>]*>(.*?)</td>', r, flags=re.S)
    txt = [re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', c))).strip() for c in cells]
    if txt and re.fullmatch(r'\d{1,4}', txt[0]) and len(txt) >= 5:
        current = None
        wording = ' '.join(txt[5:])
        if 'list of ingredients' not in wording or 'indicated' not in wording:
            continue
        inci = [x.strip(' ;') for x in re.split(r';', txt[2]) if x.strip(' ;')]
        cas = re.findall(r'\d{2,7}-\d\d-\d', txt[3])
        current = {'ref': int(txt[0]), 'inci': inci, 'cas': cas, 'chemical': txt[1]}
        out.append(current)
    elif current is not None and len(txt) == 4 and re.search(r'\d{2,7}-\d\d-\d', txt[2]):
        # an isomer row under the same entry (no reference number of its own)
        name = txt[1].strip(' ;')
        if name and name not in current['inci']:
            current['inci'].append(name)
        current['cas'] += re.findall(r'\d{2,7}-\d\d-\d', txt[2])
    elif txt and not (txt[0].startswith('\u25bc') or txt[0].startswith('(')):
        current = None
doc = {
    'about': 'Fragrance allergens and other substances that the EU requires to be '
             'named in the ingredient list (Annex III of Regulation (EC) 1223/2009).',
    'source': 'https://publications.europa.eu/resource/celex/02009R1223-20230816',
    'amended_by': 'https://eur-lex.europa.eu/eli/reg/2023/1545/oj',
    'note': 'Consolidated text, no legal effect. Thresholds: 0.001 % leave-on, 0.01 % rinse-off.',
    'count': len(out),
    'entries': out,
}
json.dump(doc, open(dst, 'w'), ensure_ascii=False, indent=1)
print(len(out), 'entries ->', dst)

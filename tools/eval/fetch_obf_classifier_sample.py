"""Builds an independent evaluation sample for the product classifier from
Open Beauty Facts (https://world.openbeautyfacts.org), through its official
search API.

Licence: the Open Beauty Facts database is under the Open Database Licence
(ODbL 1.0); each product's contents under the Database Contents Licence.
Attribution: "Data from Open Beauty Facts, openbeautyfacts.org, ODbL".
Only the product code, brand, English name, ingredient list and categories
are kept: no photos, no descriptions.

Labels come from the Open Beauty Facts CATEGORIES (crowd-sourced, not checked
by us) through the fixed table CATEGORY_LABELS below, written before running
the classifier. A product whose categories map to two different forms is
dropped as ambiguous. The classifier is given the English name, the INCI list
and only the coarse app category (makeup / perfume / care) that every product
of the app has; never the Open Beauty Facts category.

Usage: python3 tools/eval/fetch_obf_classifier_sample.py > tool/eval_classifier_obf.json
Polite: one request every 7 s (the API allows 10 searches a minute).
"""
from __future__ import annotations

import datetime as dt
import json
import re
import sys
import subprocess
import time
import urllib.parse

API = 'https://world.openbeautyfacts.org/api/v2/search'
UA = 'Cosmetix-eval/1.0'
PER_CATEGORY = 15
PAGE_SIZE = 100
PAUSE_S = 7

# OBF category tag -> (form, rinse-off or None, purpose or None, app category)
CATEGORY_LABELS = {
    'shampoos': ('shampoo', True, None, 'Уход'),
    'shower-gels': ('cleanser', True, None, 'Уход'),
    'cleansers': ('cleanser', True, 'cleansing', 'Уход'),
    'micellar-waters': ('micellar', False, 'cleansing', 'Уход'),
    'sunscreens': ('sunscreen', False, 'sunProtection', 'Уход'),
    'face-creams': ('cream', False, None, 'Уход'),
    'day-creams': ('cream', False, None, 'Уход'),
    'night-creams': ('cream', False, None, 'Уход'),
    'face-masks': ('mask', None, None, 'Уход'),
    'lip-balms': ('lipCare', False, None, 'Уход'),
    'lipsticks': ('makeup', False, None, 'Макияж'),
    'mascaras': ('makeup', False, None, 'Макияж'),
    'foundations': ('makeup', False, None, 'Макияж'),
    'perfumes': ('perfume', False, None, 'Парфюмерия'),
}

_INCI = re.compile(r'\b(aqua|water|eau|alcohol|parfum|glycerin)\b', re.I)


def search(tag: str, page: int) -> list[dict]:
    q = urllib.parse.urlencode({
        'categories_tags_en': tag,
        'fields': 'code,product_name_en,brands,ingredients_text_en,'
                  'ingredients_text,categories_tags',
        'page_size': PAGE_SIZE,
        'page': page,
        'sort_by': 'code',  # stable order: the sample can be rebuilt
    })
    # curl: the system certificates (a python.org build may not have them)
    out = subprocess.run(['curl', '-sS', '--fail', '-m', '60', '-A', UA, f'{API}?{q}'],
                         check=True, capture_output=True).stdout
    return json.loads(out).get('products', [])


def looks_like_inci(text: str) -> bool:
    return text.count(',') >= 5 and bool(_INCI.search(text)) and len(text) < 3000


def forms_of(tags: list[str]) -> set[str]:
    return {CATEGORY_LABELS[t[3:]][0] for t in tags
            if t.startswith('en:') and t[3:] in CATEGORY_LABELS}


def main() -> None:
    items, seen = [], set()
    for tag, (form, rinse, purpose, app_cat) in CATEGORY_LABELS.items():
        taken = 0
        for page in (1, 2, 3):
            if taken >= PER_CATEGORY:
                break
            products = search(tag, page)
            time.sleep(PAUSE_S)
            if not products:
                break
            for p in products:
                code = p.get('code')
                name = (p.get('product_name_en') or '').strip()
                inci = (p.get('ingredients_text_en') or p.get('ingredients_text') or '').strip()
                if not code or code in seen or not name or not looks_like_inci(inci):
                    continue
                if len(forms_of(p.get('categories_tags') or [])) != 1:
                    continue  # ambiguous: e.g. a "2 in 1 shower & shampoo"
                seen.add(code)
                item = {
                    'name': name,
                    'brand': (p.get('brands') or '').split(',')[0].strip(),
                    'category': app_cat,
                    'inci': inci,
                    'trueForm': form,
                    'obfCategory': tag,
                    'source': f'https://world.openbeautyfacts.org/product/{code}',
                }
                if rinse is not None:
                    item['trueRinseOff'] = rinse
                if purpose is not None:
                    item['truePurpose'] = purpose
                items.append(item)
                taken += 1
                if taken >= PER_CATEGORY:
                    break
        print(f'{tag}: {taken}', file=sys.stderr)
    json.dump({
        'source': 'Open Beauty Facts, https://world.openbeautyfacts.org',
        'licence': 'ODbL 1.0 (database), Database Contents Licence (contents)',
        'attribution': 'Data from Open Beauty Facts, openbeautyfacts.org, ODbL',
        'fetched': dt.date.today().isoformat(),
        'labels': 'from Open Beauty Facts categories (crowd-sourced) via CATEGORY_LABELS',
        'items': items,
    }, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()

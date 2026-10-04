"""Prints Russian strings used with tr()/trf() that the translation maps lack."""
import re, glob, sys
sys.path.insert(0, 'tool')
CYR = re.compile('[А-Яа-яЁё]')
keys = {}
for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
    if '/i18n/' in f: continue
    s = open(f).read()
    for m in re.finditer(r"\btrf?\(\s*((?:'(?:[^'\\\n]|\\.)*'\s*)+)", s):
        k = ''.join(re.findall(r"'((?:[^'\\\n]|\\.)*)'", m.group(1)))
        if CYR.search(k): keys.setdefault(k, f)
have = open('lib/core/i18n/translations_en.dart').read()
new = [k for k in keys if ("'" + k + "':") not in have and ("\n  '" + k + "':") not in have]
import json
json.dump(new, open('tool/new_keys.json', 'w'), ensure_ascii=False, indent=0)
for i, k in enumerate(new): print(i, '|', k)
print(len(new), 'new')

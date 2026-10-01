"""One-off: wrap Cyrillic single-quoted string literals in tr(...). Interpolated ones are only listed."""
import re, sys, glob, json
CYR = re.compile('[А-Яа-яЁё]')

def literals(s):
    """yield (start, end, raw_inner) of single-quoted, non-raw, non-triple string literals"""
    i, n = 0, len(s); out = []
    def skip_str(i, q):
        # i at opening quote; returns index after closing; handles ${} nesting
        triple = s.startswith(q*3, i)
        i += 3 if triple else 1
        while i < n:
            c = s[i]
            if c == '\\': i += 2; continue
            if c == '$' and i+1 < n and s[i+1] == '{':
                depth = 1; i += 2
                while i < n and depth:
                    if s[i] in '\'"': i = skip_str(i, s[i]); continue
                    if s[i] == '{': depth += 1
                    elif s[i] == '}': depth -= 1
                    i += 1
                continue
            if triple:
                if s.startswith(q*3, i): return i+3
            elif c == q: return i+1
            i += 1
        return i
    while i < n:
        c = s[i]
        if s.startswith('//', i):
            i = s.find('\n', i); i = n if i < 0 else i; continue
        if s.startswith('/*', i):
            i = s.find('*/', i); i = n if i < 0 else i+2; continue
        if c == 'r' and i+1 < n and s[i+1] in '\'"' and (i == 0 or not (s[i-1].isalnum() or s[i-1] == '_')):
            i = skip_str(i+1, s[i+1]); continue
        if c in '\'"':
            q = c; st = i
            e = skip_str(i, q)
            if q == "'" and not s.startswith("'''", st):
                out.append((st, e, s[st+1:e-1]))
            i = e; continue
        i += 1
    return out

def process(path, apply):
    s = open(path).read()
    lits = literals(s)
    # merge adjacent
    merged = []
    for L in lits:
        if merged and re.fullmatch(r'\s*', s[merged[-1][1]:L[0]]) and not re.search(r'^\s*(import|export|part)\b', s[s.rfind('\n',0,merged[-1][0])+1:merged[-1][0]+8]):
            p = merged[-1]; merged[-1] = (p[0], L[1], p[2] + L[2], True)
        else:
            merged.append((L[0], L[1], L[2], False))
    edits = []; inter = []
    for st, e, raw, m in merged:
        line = s[s.rfind('\n',0,st)+1:s.find('\n',st)]
        if line.lstrip().startswith(('import ', 'export ', 'part ')): continue
        if not CYR.search(raw): continue
        if '$' in re.sub(r'\\\$', '', raw):
            inter.append(raw); continue
        edits.append((st, e, raw))
    if apply and edits:
        for st, e, raw in sorted(edits, reverse=True):
            s = s[:st] + "tr('" + raw + "')" + s[e:]
        # import
        imp = "import 'package:cosmetix/core/i18n/tr.dart';\n"
        if imp not in s:
            m = re.search(r"^import .*;\n", s, re.M)
            s = (s[:m.start()] + imp + s[m.start():]) if m else imp + s
        open(path, 'w').write(s)
    return [e[2] for e in edits], inter

if __name__ == '__main__':
    apply = sys.argv[1] == 'apply'
    files = []
    for pat in ['lib/screens/**/*.dart', 'lib/widgets/*.dart', 'lib/providers/*.dart', 'lib/routes/*.dart',
                'lib/core/utils/*.dart', 'lib/models/safety_models.dart', 'lib/models/product.dart', 'lib/models/social_models.dart']:
        files += glob.glob(pat, recursive=True)
    allk, alli = set(), []
    for f in sorted(files):
        k, i = process(f, apply)
        allk.update(k); alli += [(f, x) for x in i]
    json.dump(sorted(allk), open('tool/keys.json', 'w'), ensure_ascii=False, indent=0)
    json.dump(alli, open('tool/interp.json', 'w'), ensure_ascii=False, indent=0)
    print(len(allk), 'static keys;', len(alli), 'interpolated')

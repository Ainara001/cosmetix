import re, sys, glob, json
sys.path.insert(0,'tool')
from wrap_tr import literals, CYR

def split_interp(raw):
    """-> (template, [(name, expr)]) ; raw is the inner text of a single-quoted literal"""
    out=[]; names=[]; i=0; n=len(raw); k=0
    while i<n:
        c=raw[i]
        if c=='\\': out.append(raw[i:i+2]); i+=2; continue
        if c=='$' and i+1<n and raw[i+1]=='{':
            depth=1; j=i+2
            while j<n and depth:
                if raw[j]=='{': depth+=1
                elif raw[j]=='}': depth-=1
                elif raw[j] in '\'"':
                    q=raw[j]; j+=1
                    while j<n and raw[j]!=q:
                        j+= 2 if raw[j]=='\\' else 1
                j+=1
            expr=raw[i+2:j-1]
            simple=re.fullmatch(r'[A-Za-z_]\w*',expr)
            name=expr if simple else f'v{k}'; k+=1
            names.append((name,expr)); out.append('{'+name+'}'); i=j; continue
        if c=='$' and i+1<n and re.match(r'[A-Za-z_]',raw[i+1]):
            m=re.match(r'[A-Za-z_]\w*',raw[i+1:]); name=m.group(0)
            names.append((name,name)); out.append('{'+name+'}'); i+=1+len(name); continue
        out.append(c); i+=1
    return ''.join(out), names

def process(path):
    s=open(path).read(); lits=literals(s); merged=[]
    for L in lits:
        if merged and re.fullmatch(r'\s*', s[merged[-1][1]:L[0]]):
            p=merged[-1]; merged[-1]=(p[0],L[1],p[2]+L[2])
        else: merged.append((L[0],L[1],L[2]))
    edits=[]; keys=[]
    for st,e,raw in merged:
        line=s[s.rfind('\n',0,st)+1:s.find('\n',st)]
        if line.lstrip().startswith(('import ','export ','part ')): continue
        if not CYR.search(raw) or '$' not in re.sub(r'\\\$','',raw): continue
        tpl,names=split_interp(raw)
        keys.append(tpl)
        def wrap(name,expr):
            if re.search(r'\.(name|storeName|productName)$',expr) and 'blacklistHits' not in expr: return f"tr({expr})"
            return expr
        args=', '.join(f"'{nm}': {wrap(nm,ex)}" for nm,ex in names)
        edits.append((st,e,f"trf('{tpl}', {{{args}}})"))
    if edits:
        for st,e,rep in sorted(edits,reverse=True): s=s[:st]+rep+s[e:]
        imp="import 'package:cosmetix/core/i18n/tr.dart';\n"
        if imp not in s:
            m=re.search(r"^import .*;\n",s,re.M); s=(s[:m.start()]+imp+s[m.start():]) if m else imp+s
        open(path,'w').write(s)
    return keys
allk=[]
for pat in ['lib/screens/**/*.dart','lib/widgets/*.dart','lib/providers/*.dart','lib/models/product.dart','lib/models/safety_models.dart']:
    for f in sorted(glob.glob(pat,recursive=True)): allk+=process(f)
json.dump(allk,open('tool/interp_keys.json','w'),ensure_ascii=False,indent=0)
print(len(allk))

import re, subprocess, collections
for it in range(12):
    out = subprocess.run(['flutter','analyze','--no-pub'],capture_output=True,text=True).stdout
    errs = re.findall(r"error • (.*?) • (lib/[^:]+):(\d+):(\d+) •", out)
    errs = [e for e in errs if "constant" in e[0].lower()]
    print('iter',it,len(errs))
    if not errs: break
    byfile = collections.defaultdict(set)
    for msg,f,l,c in errs: byfile[f].add((int(l),int(c)))
    manual=[]
    for f,locs in byfile.items():
        lines = open(f).read().split('\n')
        offs=[0]
        for ln in lines: offs.append(offs[-1]+len(ln)+1)
        s='\n'.join(lines)
        removals=set()
        for l,c in locs:
            pos = offs[l-1]+c-1
            m=None
            for mm in re.finditer(r'\bconst\b ?', s[:pos]): m=mm
            if not m: manual.append((f,l)); continue
            pre = s[max(0,m.start()-8):m.start()]
            if re.search(r'static\s*$', pre) or re.search(r'(^|\n)\s*$', pre) and re.match(r'const \w+ ?=', s[m.start():m.start()+60]) or re.match(r'const\s+[\w<>?,\s]*\s*=', s[m.start():m.start()+80]):
                manual.append((f,l)); continue
            removals.add((m.start(), m.end()))
        for a,b in sorted(removals, reverse=True):
            s = s[:a] + s[b:]
        open(f,'w').write(s)
    if manual: print('MANUAL', sorted(set(manual)))

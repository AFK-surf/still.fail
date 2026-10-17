#!/usr/bin/env python3
# Worklets that read a worklet function or a constant defined after them in the same file: a worklet takes what it
# reads when it is made, and a "worklet" function is not hoisted (the plugin makes it a const), so it gets undefined.
# Run in apps/mobile-rn: python3 scripts/worklets.py (prints nothing when there are none).
import re,glob,sys
for f in glob.glob('src/**/*.ts*',recursive=True):
    s=open(f).read()
    decl={}
    for m in re.finditer(r'^\s*(?:export\s+)?function\s+(\w+)\s*(?:<[^>]*>)?\([^)]*\)[^{]*\{\s*\n?\s*["\']worklet["\'];',s,re.M):
        decl[m.group(1)]=m.start()
    # every worklet-ish body: function declarations with worklet, arrow fns/objects with worklet, useAnimatedStyle/useDerivedValue callbacks
    for m in re.finditer(r'["\']worklet["\'];',s):
        # find enclosing function start: search back for 'function' or '=>' with '{'
        start=m.start()
        # body extent: from the '{' before start to its matching '}'
        b=s.rfind('{',0,start)
        depth=0; i=b
        while i<len(s):
            if s[i]=='{': depth+=1
            elif s[i]=='}':
                depth-=1
                if depth==0: break
            i+=1
        body=s[b:i]
        for name,pos in decl.items():
            if pos>b and re.search(r'\b%s\s*\('%name, body) and pos> b:
                if pos>i or pos>start:
                    ln=s.count('\n',0,start)+1
                    print(f'{f}:{ln}: uses worklet {name} defined later (line {s.count(chr(10),0,pos)+1})')
# top-level consts/lets defined after a worklet that reads them (captured when the worklet is made)
for f in glob.glob('src/**/*.ts*',recursive=True):
    s=open(f).read()
    consts={m.group(1):m.start() for m in re.finditer(r'^(?:export\s+)?(?:const|let)\s+(\w+)',s,re.M)}
    for m in re.finditer(r'["\']worklet["\'];',s):
        b=s.rfind('{',0,m.start()); d=0; i=b
        while i<len(s):
            if s[i]=='{': d+=1
            elif s[i]=='}':
                d-=1
                if d==0: break
            i+=1
        body=s[b:i]
        for n,pos in consts.items():
            if pos>i and re.search(r'(?<![\w.])%s\b'%n, body):
                print(f'{f}:{s.count(chr(10),0,m.start())+1}: worklet reads {n} defined later (line {s.count(chr(10),0,pos)+1})')

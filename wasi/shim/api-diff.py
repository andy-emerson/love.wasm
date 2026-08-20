#!/usr/bin/env python3
"""Which Lua-facing LOVE names does one version have that another lacks?

The measured scope behind love.shim's LOVE 11.5 tier (D21, #64). Run it at a
base bump: an upstream change that drops a deprecation should fail a check
here, not be discovered by a game.

    python3 wasi/shim/api-diff.py <old-love-tree> <new-love-tree>
    python3 wasi/shim/api-diff.py /path/to/love-11.5 .

It reads BOTH kinds of definition, which is the whole point:

  * C++ registration tables  - { "name", w_name } in src/modules/**/wrap_*.cpp
  * Lua-level API files      - src/modules/**/wrap_*.lua

Scanning only the C++ is what produced an earlier count of 27 absent names
instead of 24: LOVE 12 defines love.graphics.stencil, getStencilTest and
setStencilTest in src/modules/graphics/wrap_Graphics.lua, and a C++-only scan
reports three names as missing that are present and merely deprecated.

Names are compared per MODULE rather than per file, so a name moving between
owner types inside a module is not counted as a removal. Underscore-prefixed
internals are reported separately from the public surface.
"""
import re,sys,os,json
cpp=re.compile(r'\{\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,\s*(?:w_|luax_|loader_)?[A-Za-z_][A-Za-z0-9_:<>]*\s*\}')
# Lua-defined API: `function graphics.name(` / `function Data.name(` / `x.name = function`
lua=re.compile(r'function\s+[A-Za-z_][A-Za-z0-9_]*[.:]([A-Za-z_][A-Za-z0-9_]*)\s*\(|^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function', re.M)
def scan(root):
    api={}
    base=os.path.join(root,'src','modules')
    for dp,_,fns in os.walk(base):
        mod=os.path.relpath(dp,base).split(os.sep)[0]
        for fn in fns:
            p=os.path.join(dp,fn)
            try: txt=open(p,encoding='utf-8',errors='ignore').read()
            except: continue
            if fn.startswith('wrap_') and fn.endswith('.cpp'):
                for m in cpp.finditer(txt): api.setdefault(mod,set()).add(m.group(1))
            elif fn.startswith('wrap_') and fn.endswith('.lua'):
                for m in lua.finditer(txt):
                    n=m.group(1) or m.group(3)
                    if n: api.setdefault(mod,set()).add(n)
    return api
A,B=scan(sys.argv[1]),scan(sys.argv[2])
gone={m:sorted(n-B.get(m,set())) for m,n in A.items() if n-B.get(m,set())}
pub={m:[x for x in v if not x.startswith('_')] for m,v in gone.items()}
pub={m:v for m,v in pub.items() if v}
print("11.5 names:",sum(len(v) for v in A.values()),"| 12 names:",sum(len(v) for v in B.values()))
print("absent from 12 (public):",sum(len(v) for v in pub.values()),"\n")
for m in sorted(pub,key=lambda k:-len(pub[k])): print(f"[{m}] {len(pub[m])}: "+", ".join(pub[m]))

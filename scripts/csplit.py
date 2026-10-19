#!/usr/bin/env python3
"""Split the one C file moonc generates for a program into translation units
that compile in parallel (scripts/android.sh), as the same program.

    csplit.py IN.c OUTDIR [-n N]        writes OUTDIR/{decls.h, externs.h, data.c, init.c, f0.c … f<N-1>.c}

moonc's file is: a runtime prelude (its own text: includes, inline helpers, macros, under #if), then moonc's items
at file scope: struct declarations and definitions, function prototypes, #defines (FFI names), global data
(string literals, closures, constant constructors: mostly `struct { … } const NAME = { … };`), the function
definitions, `moonbit_init` (every global's initialisation, one function of tens of thousands of lines, run once)
and `main`. The split:

  decls.h    the prelude and every declaration (types, prototypes, #defines), in moonc's order
  externs.h  an `extern` declaration of each global (its type as moonc wrote it: anonymous structs are compatible
             across translation units)
  data.c     decls.h and the globals' definitions, in moonc's order (data.c alone sees each global's definition,
             so an anonymous struct type is never declared twice in one unit)
  init.c     decls.h, externs.h and moonbit_init alone (built with less optimisation: it runs once)
  f<k>.c     decls.h, externs.h and the other functions, balanced by size (largest first into the lightest unit),
             each unit in moonc's order

`static` on moonc's items (moonc 0.10.16 makes most functions static) becomes CSPLIT_INTERNAL (hidden visibility:
not exported, still the link's to drop or inline), so that what one unit defines the others can call; the
prelude's own statics stay in decls.h (inline helpers, a copy per unit, as any header's), and what it defines that is
not static (the software clz, sqrt… of a compiler without those builtins: MSVC) data.c alone defines. Files whose text did
not change keep their mtime, so a build can skip the units it compiled already.

Anything this does not recognise stops it (exit 2) rather than guess: an item it cannot classify, a #if among
moonc's items, a #define after a function body, an item that does not end its line, a name defined twice, an
empty result. It prints what it made (units, sizes, counts) on stderr; --json writes that as a manifest.
"""
import argparse
import hashlib
import json
import os
import re
import sys

IDENT = r'[A-Za-z_$][A-Za-z0-9_$]*'
# what the scan of an item looks at: comments, literals (a lone quote is one that does not end on its line), braces,
# parentheses, brackets and semicolons
# inside braces only braces, literals and comments matter (an item ends at file scope)
BODY_TOKEN = re.compile(r'//|/\*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|["\']|[{}]')
TOKEN = re.compile(r'//|/\*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|["\']|[{}()\[\];]')


class SplitError(Exception):
    pass


def fail(msg):
    raise SplitError(msg)


def items_of(lines, start):
    """moonc's file-scope items from line `start` on: (kind, text, first line). kind is 'pp' for a preprocessor
    line, 'func' for a function definition, 'decl' for anything ending in `;` at file scope."""
    out = []
    buf = []
    first = None
    depth = 0          # braces
    paren = 0          # parentheses and brackets
    in_comment = False
    func_head = None   # the text before an item's first file-scope `{`
    i = start
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.lstrip()
        if not buf and not in_comment:
            if stripped == '' or stripped == '\n':
                i += 1
                continue
            if stripped.startswith('#'):
                text = line
                while text.rstrip('\n').endswith('\\') and i + 1 < n:
                    i += 1
                    text += lines[i]
                out.append(('pp', text, i + 1))
                i += 1
                continue
        if not buf:
            first = i + 1
            func_head = None
        buf.append(line)
        if stripped.startswith('#') and not in_comment:
            # a directive inside an item (moonc's #line in function bodies): no braces of the program in it
            i += 1
            continue
        if depth > 0 and not in_comment and '"' not in line and "'" not in line and '/' not in line:
            # inside braces (most lines: function bodies), no literal or comment: only the braces count, and when the
            # depth cannot come back to the item's end on this line, their totals do
            closes = line.count('}')
            if depth - closes > 0:
                depth += line.count('{') - closes
                i += 1
                continue
        j = 0
        ended = None
        while True:
            if in_comment:
                e = line.find('*/', j)
                if e < 0:
                    break
                in_comment = False
                j = e + 2
                continue
            m = (TOKEN if depth == 0 else BODY_TOKEN).search(line, j)
            if not m:
                break
            t = m.group()
            j = m.end()
            if t == '//':
                break
            if t == '/*':
                in_comment = True
            elif t[0] in '"\'':
                if len(t) == 1:
                    fail(f'line {i + 1}: a literal that does not end on its line')
            elif t == '{':
                if depth == 0 and paren == 0 and func_head is None:
                    func_head = ''.join(buf[:-1]) + line[:m.start()]
                depth += 1
            elif t == '}':
                depth -= 1
                if depth < 0:
                    fail(f'line {i + 1}: an unmatched }}')
                if depth == 0 and paren == 0 and func_head is not None and func_head.rstrip().endswith(')'):
                    ended = ('func', m.start())
                    break
            elif t in '([':
                paren += 1
            elif t in ')]':
                paren -= 1
                if paren < 0:
                    fail(f'line {i + 1}: an unmatched {t}')
            elif t == ';' and depth == 0 and paren == 0:
                ended = ('decl', m.start())
                break
        if ended:
            rest = line[ended[1] + 1:].strip()
            if rest and not rest.startswith('//'):
                fail(f'line {i + 1}: an item that does not end its line ({rest[:40]!r} after it)')
            out.append((ended[0], ''.join(buf), first))
            buf = []
        i += 1
    if buf and ''.join(buf).strip():
        fail(f'line {first}: the file ends inside an item')
    if in_comment:
        fail('the file ends inside a comment')
    return out


def strip_static(text, mark=''):
    """`text` without its leading `static`/`inline` (`mark` in their place), and whether it had them."""
    t = text.lstrip()
    lead = text[:len(text) - len(t)]
    changed = False
    while True:
        m = re.match(r'(static|inline)\b\s*', t)
        if not m:
            break
        t = t[m.end():]
        changed = True
    return lead + (mark if changed and mark else '') + t, changed


# what a static of moonc's becomes: a global hidden from outside the program (as a static was), so that the link can
# still drop or inline it (moonc 0.10.16 makes most functions static)
INTERNAL = ('#if defined(__GNUC__) || defined(__clang__)\n#define CSPLIT_INTERNAL __attribute__((visibility("hidden")))\n'
            '#else\n#define CSPLIT_INTERNAL\n#endif\n')


BLANK = re.compile(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|^[ \t]*#[^\n]*', re.S | re.M)


def blank(text):
    """`text` with its comments, directives and what is inside its literals replaced by spaces (positions kept)."""
    def sub(m):
        t = m.group()
        if t[0] in '"\'':
            return t[0] + re.sub(r'[^\n]', ' ', t[1:-1]) + t[-1]
        return re.sub(r'[^\n]', ' ', t)
    return BLANK.sub(sub, text)


def top_level(text):
    """`text` with its comments, literals' insides and what is inside braces, parentheses and brackets replaced by
    spaces (positions kept)."""
    out = []
    depth = 0
    for c in blank(text):
        if c in '{([':
            depth += 1
            out.append(c if depth == 1 else ' ')
        elif c in '})]':
            out.append(c if depth == 1 else ' ')
            depth -= 1
        else:
            out.append(c if depth == 0 else ' ')
    return ''.join(out)


def func_name(text, line):
    head = text[:text.index('{')] if '{' in text else text
    flat = top_level(head)
    p = flat.find('(')
    if p < 0:
        fail(f'line {line}: no parameter list in {head[:60]!r}')
    m = re.search(r'(' + IDENT + r')\s*$', head[:p])
    if not m:
        fail(f'line {line}: no function name in {head[:60]!r}')
    return m.group(1)


def classify(text, line):
    """For a 'decl' item: ('type', None) | ('proto', name) | ('data', (name, extern_text))."""
    t = text.strip()
    if re.match(r'typedef\b', t):
        return 'type', None
    flat = top_level(t)
    # struct/union/enum declarations and definitions without a declarator
    if re.match(r'(struct|union|enum)\s+' + IDENT + r'\s*(\{\s*\}\s*)?;$', flat):
        return 'type', None
    eq = flat.find('=')
    decl = t[:eq] if eq >= 0 else t[:-1]
    flat_decl = flat[:eq] if eq >= 0 else flat[:-1]
    if ',' in flat_decl:
        fail(f'line {line}: more than one declarator in {t[:80]!r}')
    if eq < 0 and '(' in flat_decl and flat_decl.rstrip().endswith(')'):
        p = flat_decl.find('(')
        m = re.search(r'(' + IDENT + r')\s*$', decl[:p])
        if not m:
            fail(f'line {line}: a prototype without a name: {t[:80]!r}')
        return 'proto', m.group(1)
    # a global: its name is the last identifier at file scope of the declarator (before any [size])
    d = flat_decl.rstrip()
    while d.endswith(']'):
        d = d[:d.rindex('[')].rstrip()
    m = re.search(r'(' + IDENT + r')$', d)
    if not m or m.group(1) in ('const', 'volatile'):
        fail(f'line {line}: a global without a name: {t[:80]!r}')
    name = m.group(1)
    ext = decl.rstrip()
    ext, _ = strip_static(ext)
    if re.match(r'\s*extern\b', ext):
        return 'proto', name  # a declaration already
    return 'data', (name, 'extern ' + ext.lstrip() + ';\n')


def name_of(text):
    """The name an item defines or declares (for the manifest)."""
    t = text.strip()
    if t.endswith('}'):
        return func_name(t, 0)
    what, info = classify(t, 0)
    return info if what == 'proto' else info[0] if what == 'data' else ''


def package_of(name):
    """The package in a name moonc mangled (_M0FP24mbui2ui3run: mbui/ui; _M0MPC15array…: core/array; …PB…: the
    builtins), '' when it has none."""
    m = re.match(r'_M0[A-Z]*?P(B|C\d|\d)', name)
    if not m:
        return ''
    g, i = m.group(1), m.end()
    if g == 'B':
        return 'core/builtin'
    comps = []
    for _ in range(int(g[1:]) if g[0] == 'C' else int(g)):
        d = re.match(r'\d+', name[i:])
        if not d:
            return ''
        i += len(d.group())
        comps.append(name[i:i + int(d.group())])
        i += int(d.group())
    return ('core/' if g[0] == 'C' else '') + '/'.join(comps)


def prelude_definitions(prelude):
    """The prelude with each definition of its own that is not static (the software clz/ctz/popcnt, sqrt… a compiler
    without the builtins gets: MSVC) made `#ifdef CSPLIT_DEFS` (data.c, which defines it) `#else` a declaration:
    defined once, declared in every unit. Its #ifdef __cplusplus blocks stay as they are."""
    lines = prelude.splitlines(keepends=True)
    out = []
    seg = []
    count = 0

    def flush():
        nonlocal count
        if not seg:
            return
        try:
            items = items_of(seg, 0)
        except SplitError:
            out.extend(seg)  # as it was: a definition twice is the link's to find (mbc.py check)
            seg.clear()
            return
        for kind, text, _ in items:
            b = blank(text)
            lead = b.lstrip()
            if kind == 'pp' or lead.startswith(('static', 'typedef', 'extern', '#')):
                out.append(text)
                continue
            code = text[len(b) - len(lead):]  # past the comments before it
            if kind == 'func':
                decl = code[:code.index('{')].rstrip() + ';\n'
            else:
                try:
                    what, info = classify(code, 0)
                except SplitError:
                    out.append(text)
                    continue
                if what != 'data':
                    out.append(text)
                    continue
                decl = info[1]
            count += 1
            out.append('#ifdef CSPLIT_DEFS\n' + text + ('' if text.endswith('\n') else '\n') + '#else\n' + decl + '#endif\n')
        seg.clear()

    depth = 0  # inside #ifdef __cplusplus … #endif
    for line in lines:
        d = line.strip()
        if depth:
            out.append(line)
            if re.match(r'#\s*(if|ifdef|ifndef)\b', d):
                depth += 1
            elif re.match(r'#\s*endif\b', d):
                depth -= 1
            continue
        if re.match(r'#\s*ifdef\s+__cplusplus\b', d):
            flush()
            out.append(line)
            depth = 1
            continue
        seg.append(line)
    flush()
    return ''.join(out), count


def split(src, nunits, group='size'):
    lines = src.splitlines(keepends=True)
    # the prelude: moonc's own text up to its first item, a declaration of one of its structs
    start = None
    for k, line in enumerate(lines):
        if re.match(r'struct _M0' + r'[A-Za-z0-9_$]*;\s*$', line):
            start = k
            break
    if start is None:
        fail('no `struct _M0…;` declaration: not the file moonc generates (or its layout changed)')
    prelude = ''.join(lines[:start])
    if prelude.count('#if') != prelude.count('#endif'):
        fail('the prelude ends inside a #if')
    prelude, prelude_defs = prelude_definitions(prelude)
    items = items_of(lines, start)

    decls, externs, data, funcs = [], [], [], []
    seen = {}
    protos = set()
    made_global = []
    stats = {'statics_dropped': 0, 'pp': 0, 'types': 0, 'protos': 0, 'data': 0, 'funcs': 0,
             'prelude_definitions': prelude_defs}
    first_func = None
    pp_open = 0
    for kind, text, line in items:
        if kind == 'pp':
            d = text.strip()
            if re.match(r'#\s*(if|ifdef|ifndef)\b', d):
                pp_open += 1
            elif re.match(r'#\s*endif\b', d):
                pp_open -= 1
            elif not re.match(r'#\s*(define|undef|line|pragma)\b', d) and not re.match(r'#\s*else\b', d):
                fail(f'line {line}: a directive the split does not know: {d[:60]!r}')
            if first_func is not None:
                fail(f'line {line}: {d[:60]!r} after the first function definition (line {first_func}): '
                     'it would move before code that came before it')
            decls.append(text)
            stats['pp'] += 1
            continue
        if pp_open:
            # only `#ifndef X / #define X Y / #endif` guards are allowed among moonc's items
            fail(f'line {line}: an item inside a #if')
        text, dropped = strip_static(text, 'CSPLIT_INTERNAL ')
        stats['statics_dropped'] += dropped
        if dropped:
            made_global.append(text)
        if kind == 'func':
            name = func_name(text, line)
            if name in seen and seen[name] != 'proto':
                fail(f'line {line}: {name} defined twice')
            seen[name] = 'func'
            funcs.append((name, text, line))
            stats['funcs'] += 1
            if first_func is None:
                first_func = line
            continue
        what, info = classify(text, line)
        if what == 'type':
            decls.append(text)
            stats['types'] += 1
        elif what == 'proto':
            decls.append(text)
            seen.setdefault(info, 'proto')
            protos.add(info)
            stats['protos'] += 1
        else:
            name, ext = info
            if name in seen and seen[name] in ('data', 'func'):
                fail(f'line {line}: {name} defined twice')
            seen[name] = 'data'
            data.append(text)
            externs.append(ext)
            stats['data'] += 1
    if pp_open:
        fail('moonc\'s items end inside a #if')
    if not funcs:
        fail('no function definitions')
    # a function moonc defined before its callers without a prototype: one from its definition, for the other units
    synth = []
    for name, text, line in funcs:
        if name not in protos and name != 'main':
            synth.append(text[:text.index('{')].rstrip() + ';\n')
    stats['prototypes_added'] = len(synth)
    decls.extend(synth)
    inits = [f for f in funcs if f[0] == 'moonbit_init']
    if len(inits) != 1:
        fail(f'{len(inits)} definitions of moonbit_init (expected 1)')
    if not any(f[0] == 'main' for f in funcs):
        fail('no main')
    rest = [f for f in funcs if f[0] != 'moonbit_init']
    nunits = max(1, min(nunits, len(rest)))
    # what goes together: each function alone (group 'size'), or a package's functions in moonc's order, in pieces of
    # at most a unit's share (group 'package': a package's calls within itself can be inlined without LTO)
    if group == 'package':
        share = sum(len(f[1]) for f in rest) / nunits
        by_pkg = {}
        for idx, f in enumerate(rest):
            by_pkg.setdefault(package_of(f[0]), []).append(idx)
        pieces = []
        for idxs in by_pkg.values():
            piece, size = [], 0
            for idx in idxs:
                if piece and size + len(rest[idx][1]) > share:
                    pieces.append(piece)
                    piece, size = [], 0
                piece.append(idx)
                size += len(rest[idx][1])
            pieces.append(piece)
    elif group == 'size':
        pieces = [[idx] for idx in range(len(rest))]
    else:
        fail(f'no grouping {group!r} (size, package)')
    # largest first into the lightest unit; each unit then in moonc's order
    load = [0] * nunits
    unit_of = {}
    for piece in sorted(pieces, key=lambda p: -sum(len(rest[k][1]) for k in p)):
        u = min(range(nunits), key=lambda k: load[k])
        for idx in piece:
            unit_of[idx] = u
            load[u] += len(rest[idx][1])
    units = [[] for _ in range(nunits)]
    for idx, f in enumerate(rest):
        units[unit_of[idx]].append(f)

    head = '/* scripts/csplit.py: one unit of the program moonc generated */\n'
    files = {
        'decls.h': '#ifndef CSPLIT_DECLS\n#define CSPLIT_DECLS\n' + INTERNAL + prelude + '\n' + ''.join(d if d.endswith('\n') else d + '\n' for d in decls) + '#endif\n',
        'externs.h': '#ifndef CSPLIT_EXTERNS\n#define CSPLIT_EXTERNS\n' + ''.join(externs) + '#endif\n',
        'data.c': head + '#define CSPLIT_DEFS\n#include "decls.h"\n\n' + '\n'.join(data) + '\n',
        'init.c': head + '#include "decls.h"\n#include "externs.h"\n\n' + inits[0][1] + '\n',
    }
    for k, u in enumerate(units):
        files[f'f{k}.c'] = head + '#include "decls.h"\n#include "externs.h"\n\n' + '\n'.join(f[1] for f in u) + '\n'

    # every one of moonc's items in exactly one place
    accounted = len(data) + len(funcs) + (len(decls) - stats['pp'] - len(synth))
    if accounted != len(items) - stats['pp']:
        fail(f'{len(items) - stats["pp"]} items, {accounted} placed')
    manifest = {
        'units': {name: len(text) for name, text in files.items()},
        'functions': len(funcs),
        'globals': len(data),
        'stats': stats,
        'init_bytes': len(inits[0][1]),
        'unit_loads': load,
        'largest_function': max((len(f[1]), f[0]) for f in rest)[1],
        'made_global': sorted({name_of(t) for t in made_global}),
    }
    return files, manifest


def write_if_changed(path, text):
    data = text.encode()
    try:
        with open(path, 'rb') as f:
            if hashlib.sha1(f.read()).digest() == hashlib.sha1(data).digest():
                return False
    except FileNotFoundError:
        pass
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('src')
    ap.add_argument('outdir')
    ap.add_argument('-n', type=int, default=os.cpu_count() or 4, help='units for the functions (default: cores)')
    ap.add_argument('--json', help='write the manifest (units, sizes, counts) here')
    a = ap.parse_args()
    with open(a.src, encoding='utf-8', errors='surrogateescape') as f:
        src = f.read()
    try:
        files, manifest = split(src, a.n)
    except SplitError as e:
        print(f'csplit: {a.src}: {e}', file=sys.stderr)
        sys.exit(2)
    os.makedirs(a.outdir, exist_ok=True)
    keep = set(files)
    for old in os.listdir(a.outdir):
        if (old.endswith('.c') or old.endswith('.h')) and old not in keep:
            os.remove(os.path.join(a.outdir, old))
    changed = [name for name, text in files.items() if write_if_changed(os.path.join(a.outdir, name), text)]
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(manifest, f, indent=1)
    s = manifest['stats']
    print(f'csplit: {manifest["functions"]} functions, {manifest["globals"]} globals, {s["types"]} types, '
          f'{s["protos"]} prototypes, {s["pp"]} directives -> {len(files) - 2} units '
          f'(functions {min(manifest["unit_loads"]) // 1024}-{max(manifest["unit_loads"]) // 1024} KB each, '
          f'moonbit_init {manifest["init_bytes"] // 1024} KB, decls.h {manifest["units"]["decls.h"] // 1024} KB); '
          f'{len(changed)} changed', file=sys.stderr)


if __name__ == '__main__':
    main()

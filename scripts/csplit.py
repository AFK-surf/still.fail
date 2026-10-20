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
             each unit in moonc's order (groups 'size' and 'package')
  <pkg>.c    with group 'stable' (scripts/mbc.py's default): moonc's made-up names made stable, a package's functions
             (or a piece of them, s<k>.c: small packages together), with the prelude and only the declarations and
             externs they use (a struct they only pass by pointer declared, not defined: defined_needed), in
             moonc's order: see split_stable; and moonbit_init in its packages' pieces
             (init_pieces), each package's in init.<package>.c (small ones together, init.s<k>.c), init.c calling
             them in order

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
import zlib

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


def split(src, nunits, group='size', unit_bytes=None):
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
    # (for the stable split: what each declaration is, each global's name, what moonc made static by name)
    decl_kinds, data_names, static_names = [], [], set()
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
            decl_kinds.append(('pp', None))
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
            if dropped:
                static_names.add(name)
            funcs.append((name, text, line))
            stats['funcs'] += 1
            if first_func is None:
                first_func = line
            continue
        what, info = classify(text, line)
        if what == 'type':
            decls.append(text)
            decl_kinds.append(('type', None))
            stats['types'] += 1
        elif what == 'proto':
            decls.append(text)
            decl_kinds.append(('proto', info))
            if dropped:
                static_names.add(info)
            seen.setdefault(info, 'proto')
            protos.add(info)
            stats['protos'] += 1
        else:
            name, ext = info
            if name in seen and seen[name] in ('data', 'func'):
                fail(f'line {line}: {name} defined twice')
            seen[name] = 'data'
            if dropped:
                static_names.add(name)
            data.append(text)
            data_names.append(name)
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
            decl_kinds.append(('proto', name))
    stats['prototypes_added'] = len(synth)
    decls.extend(synth)
    inits = [f for f in funcs if f[0] == 'moonbit_init']
    if len(inits) != 1:
        fail(f'{len(inits)} definitions of moonbit_init (expected 1)')
    if not any(f[0] == 'main' for f in funcs):
        fail('no main')
    rest = [f for f in funcs if f[0] != 'moonbit_init']
    nunits = max(1, min(nunits, len(rest)))
    if group == 'stable':
        return split_stable(prelude, decls, decl_kinds, externs, data, data_names, funcs, inits, rest, static_names,
                            stats, items, unit_bytes)
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



# ---------------------------------------------------------------- the stable split (group 'stable', the default)
#
# moonc numbers what it makes up across the whole program: locals (_M0L6_2atmpS211545), labels (joinlet_4512),
# anonymous functions and their types (…anon__u204945__l405__, …C1234l56), constructors' objects (…constrS17$object).
# One test more and 90 000 of the names in still.fail's sfapp test change, in mbui's and core's functions too, and with
# them every unit (2026-10-20). The stable split names them by what they are instead: a local by its place among the
# function's own, a global by its name with the numbers left out and its place among the globals so named; units are
# packages (a big one in pieces by a hash of each function's name, small ones together by a hash of the package's),
# each with only the declarations it uses. A function unchanged is then the same text in the same unit, whatever else
# changed: its object is kept (scripts/mbc.py), and the same package compiled into another program the same way is
# the same unit there.

# what a pass over C text looks at: comments and literals (left as they are), identifiers, numbers (so that 0x1f's
# x1f is not taken for a name)
SCAN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|([A-Za-z_$][A-Za-z0-9_$]*)|\d[A-Za-z0-9_.]*',
                  re.S)
IDENT_RE = re.compile(IDENT)
DIGITS = re.compile(r'\d+')
# a local moonc made up: its own (_M0L…) or a label's, a temporary's (joinlet_12, _if__result_3, _2afor_7); not the
# runtime's (moonbit_…)
LOCAL = re.compile(r'_M0L[A-Za-z0-9_$]*\d$|(?!moonbit|Moonbit|MOONBIT)[A-Za-z_][A-Za-z0-9_$]*_\d+$')
TAG = re.compile(r'\b(?:struct|union|enum)\s+(' + IDENT + r')')
FWD = re.compile(r'\s*(?:struct|union|enum)\s+' + IDENT + r'\s*;\s*$')
# a member of a struct type that is not a pointer to it: what its definition needs defined before it
BY_VALUE = re.compile(r'\b(?:struct|union|enum)\s+(' + IDENT + r')\b(?!\s*\*)')
LINE_DIRECTIVE = re.compile(r'^[ \t]*#[ \t]*line\b[^\n]*\n', re.M)
LINE_FILE = re.compile(r'^\s*#\s*line\s+\d+\s+"([^"]*)"', re.M)
LAYOUT_RE = re.compile(r'(Moonbit_make_regular_object_header\(\s*MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED\s*,\s*)(\d+)(\s*,)')


def idents(text):
    """The identifiers in `text` outside its comments and literals."""
    return {m.group(1) for m in SCAN.finditer(text) if m.group(1)}


def content_hash(text):
    """The part of a name that says what it names (a string literal's, a layout's): 64 bits of its content's SHA-1.
    Two contents that come out the same are named apart (by_content)."""
    return hashlib.sha1(text.encode('utf-8', 'surrogateescape')).hexdigest()[:16]


def by_content(contents, prefix):
    """{content: name} for `contents`, each named by its content_hash; contents whose hashes are the same numbered
    apart in the order of their text, so that each content keeps its name whatever else the program has (unless
    another of the same hash comes or goes)."""
    groups = {}
    for c in set(contents):
        groups.setdefault(content_hash(c), []).append(c)
    out = {}
    for h, cs in groups.items():
        for k, c in enumerate(sorted(cs)):
            out[c] = prefix + h + (f'_{k}' if k else '')
    return out


FN_TYPE = re.compile(r'\b(_M0TW[A-Za-z0-9_$]*)\b')


def fn_type_names(defs):
    """{name: its stable name} for moonc's function types (struct _M0TW…: a closure's code pointer, the arguments
    after it), by their definitions: moonc makes one struct of the function types that are the same in C ((Unit) ->
    Unit and (Int) -> Unit both int32_t) and names it after the first it meets, so that a new one met earlier anywhere
    in the program renamed it in every unit."""
    keys = {}

    def key(n, stack):
        if n in keys:
            return keys[n]
        if n in stack:
            return 'cycle'

        def sub(m):
            t = m.group(1)
            return 'self' if t == n else key(t, stack | {n}) if t in defs else t
        k = content_hash(FN_TYPE.sub(sub, defs[n]))
        keys[n] = k
        return k
    for n in defs:
        key(n, frozenset())
    named = by_content([keys[n] for n in sorted(defs)], '_Mw')
    out, seen = {}, {}
    for n in sorted(defs, key=lambda n: (keys[n], n)):
        w = named[keys[n]]
        seen[w] = seen.get(w, 0) + 1
        out[n] = w if seen[w] == 1 else f'{w}_x{seen[w]}'
    return out


def stable_names(names, data_text, fn_defs=None):
    """{name: its stable name} for moonc's globals `names` (in moonc's order): those whose names differ only in their
    numbers in one group, numbered in the order of their numbers; a string literal by its content."""
    groups = {}
    out = {}
    literals = []
    for name in names:
        if name.startswith('moonbit_string_literal_') and name in data_text:
            literals.append((name, data_text[name].replace(name, '')))
            continue
        groups.setdefault(DIGITS.sub('#', name), []).append(name)
    for stem, members in groups.items():
        members.sort(key=lambda n: [int(d) for d in DIGITS.findall(n)])
        flat = stem.replace('#', '0')
        for k, name in enumerate(members):
            out[name] = f'_Mz{k}_{flat}'
    # a string literal by its content (two the same, which moonc does not make: numbered apart, in its order)
    out.update(fn_type_names({n: fn_defs[n] for n in fn_defs if n in out}) if fn_defs else {})
    named = by_content([c for _, c in literals], '_Ms')
    seen = {}
    for name, c in literals:
        n = named[c]
        seen[n] = seen.get(n, 0) + 1
        out[name] = n if seen[n] == 1 else f'{n}_x{seen[n]}'
    return out


def rename(text, names, local_ok=None, scan=None):
    """`text` with `names` renamed; with local_ok (the identifiers that are not locals), its locals too, by the order
    they first come in it. Returns (text, the identifiers in the result: with `scan`, only those it looks at)."""
    used = set()
    locals_ = {}

    def sub(m):
        t = m.group(1)
        if not t:
            return m.group()
        n = names.get(t)
        if n is None and local_ok is not None and t not in local_ok and LOCAL.match(t):
            # (a struct's member after . or -> is not a local)
            i = m.start() - 1
            while i >= 0 and text[i] in ' \t':
                i -= 1
            if not (i >= 0 and (text[i] == '.' or (text[i] == '>' and i > 0 and text[i - 1] == '-'))):
                n = locals_.get(t)
                if n is None:
                    n = locals_[t] = f'_Ml{len(locals_)}'
        if n is None:
            n = t
        used.add(n)
        return n
    return (scan or SCAN).sub(sub, text), used


def flatten(text):
    """A function's text with its lines as moonc broke them joined (a directive and what ends in a // comment keep
    theirs): moonc breaks a line by its length, which its made-up names' lengths changed, so that one function came
    out differently from one program to the next."""
    out, cur = [], []
    for line in text.split('\n'):
        st = line.strip()
        if not st:
            continue
        if st.startswith('#'):
            if cur:
                out.append(' '.join(cur))
                cur = []
            out.append(st)
            continue
        cur.append(st)
        if '//' in st or st.endswith('\\'):
            out.append(' '.join(cur))
            cur = []
    if cur:
        out.append(' '.join(cur))
    return '\n'.join(out) + '\n'


INIT_DECL = re.compile(r'\s*(?:const\s+)?(?:struct\s+|union\s+|enum\s+)?' + IDENT + r'(?:\s*\*\s*|\s+)(?:\*\s*)*('
                       + IDENT + r')\s*;\s*$')
# a package's pieces of moonbit_init under this many bytes: with the other small ones in a unit
INIT_SMALL = 16 * 1024
INIT_OWNER = re.compile(r'\s*(?:Moonbit_object_header\s*\(\s*)?(_M0F' + r'[A-Za-z0-9_$]*)')


def init_pieces(text):
    """moonbit_init (moonc's names) in pieces, each a run of it that is one package's: [(package, declarations,
    statements)], in its order, or None when it is not as this expects. A statement setting a global (moonc's _M0F…,
    or its object's header) is the global's package's, with what came before it since the one before (its
    temporaries); the locals moonc declares at the start go to the piece that uses them, and pieces between two that
    share a local are one. Each piece, its own function, is then the same text while its package's globals are."""
    b = blank(text)
    start = b.find('{')
    end = b.rfind('}')
    if start < 0 or end <= start:
        return None
    stmts = []
    depth = paren = 0
    s = start + 1
    i = s
    while i < end:
        c = b[i]
        if c in '([':
            paren += 1
        elif c in ')]':
            paren -= 1
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0 and paren == 0:
                # (a block's end ends its statement, unless what follows goes on with it: else, a do's while, the ;
                # of an initialiser)
                j = i + 1
                while j < end and b[j].isspace():
                    j += 1
                nxt = re.match(r'[A-Za-z_]+', b[j:j + 8])
                go_on = b[j] in ';,)' or (nxt and (nxt.group() == 'else' or
                                                   (nxt.group() == 'while' and b[s:i].lstrip().startswith('do'))))
                if not go_on:
                    stmts.append(text[s:i + 1])
                    s = i + 1
        elif c == ';' and depth == 0 and paren == 0:
            stmts.append(text[s:i + 1])
            s = i + 1
        i += 1
    if depth or paren or text[s:end].strip() or not stmts:
        return None
    # the locals moonc declares (no initial value), and the statements in runs by the package they set
    floating = {}  # local: its declaration
    runs = []  # [package, [statements], {locals}]
    pending, pending_locals = [], set()
    for st in stmts:
        bst = blank(st)
        m = INIT_DECL.match(bst)
        if m and LOCAL.match(m.group(1)) and '=' not in bst:
            floating[m.group(1)] = st
            continue
        loc = {n for n in idents(bst) if LOCAL.match(n)}
        o = INIT_OWNER.match(bst)
        if not o and not pending and runs and loc <= runs[-1][2]:
            # (right after a global set, what lets its temporaries go or goes on with it: the global's too)
            runs[-1][1].append(st)
            continue
        pending.append(st)
        pending_locals |= loc
        if o:
            p = package_of(o.group(1))
            if runs and runs[-1][0] == p:
                runs[-1][1].extend(pending)
                runs[-1][2] |= pending_locals
            else:
                runs.append([p, pending, pending_locals])
            pending, pending_locals = [], set()
    if pending:
        if not runs:
            runs.append(['', [], set()])
        runs[-1][1].extend(pending)
        runs[-1][2] |= pending_locals
    # pieces sharing a local are one, and the pieces between them (the order kept)
    last = {}
    for k, r in enumerate(runs):
        for n in r[2]:
            last[n] = k
    merged = []
    k = 0
    while k < len(runs):
        p, sts, locs = runs[k][0], list(runs[k][1]), set(runs[k][2])
        reach = max([last[n] for n in locs] + [k])
        while k < reach:
            k += 1
            sts.extend(runs[k][1])
            locs |= runs[k][2]
            reach = max([last[n] for n in runs[k][2]] + [reach])
        if merged and merged[-1][0] == p:
            merged[-1][1].extend(sts)
            merged[-1][2] |= locs
        else:
            merged.append([p, sts, locs])
        k += 1
    out = []
    for p, sts, locs in merged:
        decls = ''.join(floating[n].strip('\n') + '\n' for n in floating if n in locs)
        out.append((p, decls, ''.join(sts)))
    return out


# a variable of a struct type or a pointer to one, where it is declared (a parameter, a local, an extern)
DECL_VAR = re.compile(r'\b(?:struct|union)\s+(' + IDENT + r')\s*(\**)\s*(' + IDENT + r')\s*(?=[;,)=\[])')
SIZEOF = re.compile(r'\bsizeof\s*\(\s*(?:struct|union)\s+(' + IDENT + r')\s*\)')
VAR_USE = re.compile(r'(?<![A-Za-z0-9_$])([A-Za-z_$][A-Za-z0-9_$]*)(?![A-Za-z0-9_$])\s*(->|\[|\.)')
CAST_ACCESS = re.compile(r'\(\s*\(\s*(?:struct|union)\s+(' + IDENT + r')\s*\*\s*\)\s*' + IDENT + r'\s*\)\s*->')
HEADER_OF = re.compile(r'Moonbit_object_header\s*\([^()]*\)\s*->')


ACCESS = re.compile(r'(?<![A-Za-z0-9_$])([A-Za-z_$][A-Za-z0-9_$]*)(?![A-Za-z0-9_$])((?:\s*(?:->|\.)\s*[A-Za-z_$][A-Za-z0-9_$]*(?![A-Za-z0-9_$]))+)')
STEP = re.compile(r'(->|\.)\s*(' + IDENT + r')')


def defined_needed(texts, globals_, fields=None):
    """The struct types that functions' `texts` need defined, not only declared: by value (a local, a parameter, a
    compound literal), sizeof, a member or an element through a variable declared as one or a pointer to one (moonc
    reaches a member only through a variable); None when that cannot be told (a member through anything else).
    `globals_`: {name: (type, pointers)} of the externs. A unit that holds a struct by pointer only then has its
    declaration alone, and its members changed (mbui's Ctx: two more) do not change the unit."""
    need = set()
    for t in texts:
        b = HEADER_OF.sub('', blank(t))
        # (a member through a cast: ((struct X*)v)->$0, an enum's case's)
        need |= set(CAST_ACCESS.findall(b))
        if re.search(r'[)\]]\s*(->|\.)', CAST_ACCESS.sub('', b)):
            return None
        need |= set(SIZEOF.findall(b))
        need |= {n for n in BY_VALUE.findall(b) if not re.match(r'\s*enum\b', n)}
        local = {}
        for m in DECL_VAR.finditer(b):
            local[m.group(3)] = (m.group(1), len(m.group(2)))

        def type_of(n):
            return local.get(n) or globals_.get(n)
        for m in VAR_USE.finditer(b):
            v = type_of(m.group(1))
            if v and (v[1] == 0 or (v[1] == 1 and m.group(2) in ('->', '['))):
                need.add(v[0])
        # (a member's member: through the struct's definition, the member's type)
        for m in ACCESS.finditer(b):
            v = type_of(m.group(1))
            for op, member in STEP.findall(m.group(2)):
                if not v or (op == '->') != (v[1] == 1):
                    break
                need.add(v[0])
                v = (fields or {}).get(v[0], {}).get(member)
    return need


def unit_label(pkg):
    return re.sub(r'[^A-Za-z0-9]+', '_', pkg).strip('_') or 'main'


def split_stable(prelude, decls, decl_kinds, externs, data, data_names, funcs, inits, rest, static_names, stats, items,
                 unit_bytes=None):
    # a unit's functions (MBC_UNIT_KB): a package under half of it is with the other small ones
    target = unit_bytes or max(1, int(os.environ.get('MBC_UNIT_KB', '768'))) * 1024
    # moonc's names that are the program's own: its types and typedefs (no linkage), and what it made static (no one
    # outside calls them; what is not static keeps its name: an export, main)
    prelude_ids = idents(prelude)
    statics = static_names - {'', 'main', 'moonbit_init'}
    own = []
    seen_own = set()

    def add(n):
        if n not in seen_own and n not in prelude_ids:
            seen_own.add(n)
            own.append(n)
    data_text = dict(zip(data_names, data))
    for d in decls:
        if d.lstrip().startswith('#'):
            continue
        for tag in TAG.findall(blank(d)):
            if tag.startswith('_M0'):
                add(tag)
        if re.match(r'\s*typedef\b', d):
            m = re.search(r'(' + IDENT + r')\s*;\s*$', blank(d))
            if m and m.group(1).startswith('_M0'):
                add(m.group(1))
    for d in data:
        for tag in TAG.findall(blank(d)):
            if tag.startswith('_M0'):
                add(tag)
    for n in [f[0] for f in funcs] + list(data_text):
        if n in statics:
            add(n)
    fn_defs = {}
    for d in decls:
        m = re.match(r'\s*struct\s+(_M0TW[A-Za-z0-9_$]*)\s*\{', blank(d))
        if m:
            fn_defs[m.group(1)] = d
    names = stable_names(own, data_text, fn_defs)
    stats['renamed'] = len(names)

    # the declarations (and the externs) renamed, each with what it declares and what it uses
    file_ids = set(prelude_ids)
    ditems = []  # (text, declares, uses, always)
    for d, (kind, info) in zip(decls, decl_kinds):
        t, used = rename(d, names)
        file_ids |= used
        if kind == 'pp':
            ditems.append((t, set(), used, True))
            continue
        declares = set()
        if kind == 'proto':
            declares.add(names.get(info, info))
        else:
            b = blank(t)
            m = re.match(r'\s*typedef\b.*?(' + IDENT + r')\s*;\s*$', b, re.S) if b.lstrip().startswith('typedef') else \
                re.match(r'\s*(?:struct|union|enum)\s+(' + IDENT + r')', b)
            if m:
                declares.add(m.group(1))
        # a struct's definition uses what is in its braces; its declaration alone (struct X;) only declares X
        ditems.append((t, declares, used - declares, False))
    typedef_names = set()
    for t, declares, _, always in ditems:
        if not always and t.lstrip().startswith('typedef'):
            typedef_names |= declares
    eitems = []
    for e, n in zip(externs, data_names):
        t, used = rename(e, names)
        file_ids |= used
        n = names.get(n, n)
        eitems.append((t, {n}, used - {n}))
    data_r = [rename(d, names)[0] for d in data]
    for d in data_r:
        file_ids |= idents(d)
    by_name = {}
    for k, (_, declares, _, _) in enumerate(ditems):
        for n in declares:
            by_name.setdefault(n, []).append(('d', k))
    # moonc's directives in groups (an #ifndef X … #define X Y … #endif, or a #define alone), a unit taking a group
    # when it uses a name the group defines (an FFI name: the test driver's is each test program's own, and in every
    # unit it made every unit each program's); a group defining nothing, in every unit
    always_pp = set()
    group, depth = [], 0
    for k, (kind, _) in enumerate(decl_kinds):
        if kind != 'pp':
            continue
        d = ditems[k][0].strip()
        group.append(k)
        if re.match(r'#\s*(if|ifdef|ifndef)\b', d):
            depth += 1
        elif re.match(r'#\s*endif\b', d):
            depth -= 1
        if depth == 0:
            defined = {m.group(1) for j in group for m in [re.match(r'#\s*define\s+(' + IDENT + r')', ditems[j][0].strip())] if m}
            if defined:
                for n in defined:
                    by_name.setdefault(n, []).extend(('d', j) for j in group)
            else:
                always_pp.update(group)
            group = []
    always_pp.update(group)
    for k, (_, declares, _) in enumerate(eitems):
        for n in declares:
            by_name.setdefault(n, []).append(('e', k))

    # an object's layout is an offset into moonc's table of them (moonbit_layout_table_data), numbered across the
    # program as the names are: a function's header for one (Moonbit_make_regular_object_header(…INDEXED, 13098, 0))
    # names the layout instead, by its content, a constant data.c defines (one load where an immediate was; with
    # ThinLTO's link the value again)
    layouts = {}  # name: offset
    # (its words as moonc wrote them, renamed: sizeof(struct …) / 4, the count, offsetof(struct …, $0) / 4 * 2, …)
    table = None
    if 'moonbit_layout_table_data' in data_text:
        body = data_r[data_names.index('moonbit_layout_table_data')]
        b = blank(body)
        start = b.find('{', b.find('='))
        if start >= 0:
            table, depth, k = [], 0, start + 1
            for i in range(start + 1, len(b)):
                c = b[i]
                if c in '([{':
                    depth += 1
                elif c in ')]}':
                    if depth == 0:
                        table.append(body[k:i].strip())
                        break
                    depth -= 1
                elif c == ',' and depth == 0:
                    table.append(body[k:i].strip())
                    k = i + 1
            if table and table[-1] == '':
                table.pop()

    def layout_words(off):
        # an entry is [size; child count; tagged child…] (runtime.c): by its words, which name its type and its
        # members, two the same are the same layout (the runtime reads one only through the table:
        # Moonbit_header_layout), the first of them the constant's value
        if table is not None and off + 1 < len(table) and re.fullmatch(r'\d+[uU]?', table[off + 1]):
            end = off + 2 + int(table[off + 1].rstrip('uU'))
            if end <= len(table):
                return '\0'.join(re.sub(r'\s+', ' ', w) for w in table[off:end])
        return None
    offsets = sorted({int(m.group(2)) for t in [f[1] for f in rest] + [inits[0][1]] for m in LAYOUT_RE.finditer(t)})
    first = {}  # a layout's words: its first offset
    key_of = {}
    for off in offsets:
        w = layout_words(off)
        k = w if w is not None else f'(at {off})'
        key_of[off] = k
        first.setdefault(k, off)
    layout_named = by_content(list(first), 'csplit_layout_')
    for k, off in first.items():
        layouts[layout_named[k]] = off

    def layout_name(off):
        return layout_named[key_of[off]]

    def name_layouts(text):
        used = set()

        def sub(m):
            n = layout_name(int(m.group(2)))
            used.add(n)
            return m.group(1) + n + m.group(3)
        return LAYOUT_RE.sub(sub, text), used

    # (a function's scan looks only at what may be renamed or declared for it: moonc's names (_…), what ends in a
    # number (a string literal, a local), and what the declarations declare otherwise; not int32_t, moonbit_incref…)
    # (by_name: what the declarations, the externs and the directives' groups declare or define)
    plain = sorted({n for n in set(by_name) | set(names) if not n.startswith('_') and not n[-1:].isdigit()},
                   key=lambda n: (-len(n), n))
    body_scan = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|(?<![A-Za-z0-9_$])('
                           + '|'.join([r'_[A-Za-z0-9_$]*', r'[A-Za-z$][A-Za-z0-9_$]*\d'] + [re.escape(n) for n in plain])
                           + r')(?![A-Za-z0-9_$])', re.S)

    # the functions renamed (their locals by their own order), each in its package's unit
    fun = []  # (unit, text, used)
    sizes = {}
    pk = [package_of(f[0]) for f in rest]
    for p, f in zip(pk, rest):
        sizes[p] = sizes.get(p, 0) + len(f[1])
    small = sum(v for v in sizes.values() if v < target // 2)
    nsmall = 1
    while nsmall * target < small:
        nsmall *= 2

    def pieces(v):
        k = 1
        while k * target < v:
            k *= 2
        return k
    for p, (name, text, line) in zip(pk, rest):
        t, used = rename(text, names, file_ids, body_scan)
        t, lused = name_layouts(t)
        t = flatten(t)
        used |= lused
        new = names.get(name, name)
        if sizes[p] < target // 2:
            unit = f's{zlib.crc32(p.encode()) % nsmall}'
        else:
            # a big package in pieces by source file (its #line's), as C is compiled: an edit moves the lines of the
            # functions after it in its file, and only that file's piece changes
            k = pieces(sizes[p])
            m = LINE_FILE.search(text)
            key = (os.path.basename(m.group(1)) if m else new).encode('utf-8', 'surrogateescape')
            unit = unit_label(p) + (f'_{zlib.crc32(key) % k}' if k > 1 else '')
        fun.append((unit, t, used, new))
    def init_part(text):
        # (moonbit_init too: what it makes, the layouts its objects have, then the same each time it is)
        t, used = rename(text, names, file_ids, body_scan)
        t, lused = name_layouts(t)
        # (and without its #line's: every global's initialiser says where it is in its file, so a line added anywhere
        # above one changed moonbit_init, the slowest unit to compile (15-30 s on macos-15); it runs once, at the start)
        return flatten(LINE_DIRECTIVE.sub('', t)), used | lused
    # moonbit_init in its packages' pieces (init_pieces), each a function in its package's init unit (init.<package>.c;
    # those under INIT_SMALL together, init.s<k>.c): a package changed compiles its own again, not every global's
    # initialiser of the program; moonbit_init itself (init.c) calls them in order. MBC_INIT_SPLIT=0: one unit, as it was
    pieces = init_pieces(inits[0][1]) if os.environ.get('MBC_INIT_SPLIT', '1') != '0' else None
    init_units = {}  # unit: [[(name, text)], used]
    init_calls = []
    if pieces:
        psize = {}
        for p, d, body in pieces:
            psize[p] = psize.get(p, 0) + len(d) + len(body)
        small = [p for p, v in psize.items() if v < INIT_SMALL]
        nsmall_i = 1
        while nsmall_i * INIT_SMALL * 4 < sum(psize[p] for p in small):
            nsmall_i *= 2
        count = {}
        for p, d, body in pieces:
            label = unit_label(p)
            k = count[label] = count.get(label, -1) + 1
            fname = f'csplit_init_{label}_{k}x'
            t, used = init_part(d + body)
            unit = f'init.s{zlib.crc32(p.encode()) % nsmall_i}' if p in small else f'init.{label}'
            u = init_units.setdefault(unit, [[], set()])
            u[0].append((fname, f'CSPLIT_INTERNAL void {fname}(void) {{\n{t}}}\n'))
            u[1] |= used
            init_calls.append(fname)
        stats['init_pieces'] = len(pieces)
    else:
        init_text, init_used = init_part(inits[0][1])

    units = {}
    for unit, t, used, new in fun:
        u = units.setdefault(unit, [[], set()])
        u[0].append((new, t))
        u[1] |= used

    # what the prelude's own macros name of moonc's (MSVC's Moonbit_v128_*: functions moonc declares, a unit calling
    # them through the macro alone; MSVC takes a call to one undeclared for an int's), and what the directives in every
    # unit name
    pp_uses = prelude_ids & set(by_name)
    for k in always_pp:
        pp_uses |= ditems[k][2]

    def closure(used, need=None):
        # (need: the struct types to define, by defined_needed; None: every one used. With it, what they hold by
        # value too, and the others declared only: struct X;)
        if need is not None:
            need = set(need)
            for n in used:
                for kind, k in by_name.get(n, ()):
                    if kind == 'd' and kinds[k] == 'proto':
                        need |= {t for t in BY_VALUE.findall(blank(ditems[k][0])) if t in struct_tags}
            for n in used & typedef_names:
                need |= typedef_of.get(n, set())
            todo = list(need)
            while todo:
                for k in type_of.get(todo.pop(), ()):
                    for j in needs[k]:
                        for t in ditems[j][1] - need:
                            need.add(t)
                            todo.append(t)
        want_d, want_e, declared = set(), set(), set()
        todo = list(used | pp_uses)
        seen = set()
        while todo:
            n = todo.pop()
            if n in seen:
                continue
            seen.add(n)
            for kind, k in by_name.get(n, ()):
                if kind == 'd' and k not in want_d:
                    if need is not None and k in struct_defs and not ditems[k][1] & need:
                        declared |= ditems[k][1]
                        continue
                    want_d.add(k)
                    todo.extend(ditems[k][2])
                elif kind == 'e' and k not in want_e:
                    want_e.add(k)
                    todo.extend(eitems[k][2])
        want_d |= always_pp
        if need is not None:
            # (a type defined holds by value what it holds by value, defined too: again with those)
            held = {t for k in want_d if k in needs for j in needs[k] for t in ditems[j][1]}
            # (and an extern's type, a struct written out (a closure's object), what it holds by value)
            held |= {t for k in want_e for t in extern_by_value[k]}
            held -= need
            if held:
                return closure(used, need | held)
        fwd_made = sorted(n for n in declared if not any(kinds[k] == 'fwd' for _, k in by_name.get(n, ())))
        return want_d, want_e, fwd_made

    # a unit's declarations in an order of their own, not moonc's (which moves its types about as the program
    # changes): the directives (in moonc's order: #define's FFI names before what they rename), the structs declared,
    # the types (each after those it holds by value, else by name), the prototypes by name
    def kind_of(k):
        t, declares, _, always = ditems[k]
        if always:
            return 'pp'
        if decl_kinds_r[k] == 'proto':
            return 'proto'
        if FWD.match(blank(t)):
            return 'fwd'
        return 'type'
    decl_kinds_r = [kind for kind, _ in decl_kinds]
    kinds = [kind_of(k) for k in range(len(ditems))]
    type_of = {}
    for k, kind in enumerate(kinds):
        if kind == 'type':
            for n in ditems[k][1]:
                type_of.setdefault(n, []).append(k)
    needs = {}
    for k, kind in enumerate(kinds):
        if kind == 'type':
            b = blank(ditems[k][0])
            if b.lstrip().startswith('typedef') and '{' not in b:
                needs[k] = set()  # (a name for a type: complete or not, as it may be)
                continue
            held = set(BY_VALUE.findall(b))
            held |= {n for n in ditems[k][2] & typedef_names if re.search(r'\b' + re.escape(n) + r'\b(?!\s*\*)', b)}
            needs[k] = {j for n in held for j in type_of.get(n, ()) if j != k}

    # (struct and union definitions, which a unit may have as a declaration alone; what a typedef names)
    struct_defs = {k for k, kind in enumerate(kinds) if kind == 'type' and '{' in ditems[k][0]
                   and re.match(r'\s*(?:struct|union)\b', blank(ditems[k][0]))}
    struct_tags = {n for k in struct_defs for n in ditems[k][1]}
    typedef_of = {}
    for k, kind in enumerate(kinds):
        if kind == 'type' and blank(ditems[k][0]).lstrip().startswith('typedef'):
            for n in ditems[k][1]:
                typedef_of[n] = ditems[k][2] & struct_tags
    fields = {}
    for k in struct_defs:
        b = blank(ditems[k][0])
        inner = b[b.find('{') + 1:b.rfind('}')]
        f = {}
        for m in DECL_VAR.finditer(inner):
            f[m.group(3)] = (m.group(1), len(m.group(2)))
        for n in ditems[k][1]:
            fields[n] = f
    extern_by_value = [{t for t in BY_VALUE.findall(blank(e)) if t in struct_tags} for e, _, _ in eitems]
    globals_ = {}
    for t, declares, _ in eitems:
        for m in DECL_VAR.finditer(blank(t)):
            globals_[m.group(3)] = (m.group(1), len(m.group(2)))

    def canonical(want):
        import heapq
        key = lambda k: (min(ditems[k][1]) if ditems[k][1] else '', ditems[k][0])
        pp = [k for k in sorted(want) if kinds[k] == 'pp']
        fwd = sorted((k for k in want if kinds[k] == 'fwd'), key=key)
        protos = sorted((k for k in want if kinds[k] == 'proto'), key=key)
        types = [k for k in want if kinds[k] == 'type']
        tset = set(types)
        deps = {k: needs[k] & tset for k in types}
        users = {}
        for k, ds in deps.items():
            for j in ds:
                users.setdefault(j, []).append(k)
        heap = [(key(k), k) for k in types if not deps[k]]
        heapq.heapify(heap)
        left = {k: len(ds) for k, ds in deps.items()}
        out = []
        while heap:
            _, k = heapq.heappop(heap)
            out.append(k)
            for u in users.get(k, ()):
                left[u] -= 1
                if left[u] == 0:
                    heapq.heappush(heap, (key(u), u))
        if len(out) < len(types):
            # (a cycle: never by value; moonc's order for what is left)
            done = set(out)
            out += [k for k in sorted(types) if k not in done]
        return [ditems[k][0] for k in pp + fwd + out + protos]

    head = '/* scripts/csplit.py: one unit of the program moonc generated */\n'
    layout_names = set(layouts)
    data_r.append(''.join(f'CSPLIT_INTERNAL const uint32_t {n} = {off};\n' for n, off in sorted(layouts.items())))
    stats['layouts_named'] = len(layouts)
    decls_all = ''.join(t if t.endswith('\n') else t + '\n' for t, _, _, _ in ditems)
    files = {
        'decls.h': '#ifndef CSPLIT_DECLS\n#define CSPLIT_DECLS\n' + INTERNAL + prelude + '\n' + decls_all + '#endif\n',
        'externs.h': '#ifndef CSPLIT_EXTERNS\n#define CSPLIT_EXTERNS\n' + ''.join(t for t, _, _ in eitems) + '#endif\n',
        'data.c': head + '#define CSPLIT_DEFS\n#include "decls.h"\n\n' + '\n'.join(data_r) + '\n',
        'init.c': None,  # (below: a unit of its own, as the functions' are)
    }
    loads = []

    def unit_text(used, body, texts=None):
        """A unit: the prelude, the declarations and externs `used` needs (in an order of their own), then `body`;
        with `texts` (its functions), the structs they need defined, the others declared only."""
        need = defined_needed(texts, globals_, fields) if texts is not None and os.environ.get('MBC_DECLARE_ONLY', '1') != '0' \
            else None
        want_d, want_e, fwd_made = closure(used, need)
        d = ''.join(t if t.endswith('\n') else t + '\n' for t in canonical(want_d))
        d = ''.join(f'struct {n};\n' for n in fwd_made) + d
        e = ''.join(t for t in sorted(eitems[k][0] for k in want_e))
        e += ''.join(f'extern CSPLIT_INTERNAL const uint32_t {n};\n' for n in sorted(used & layout_names))
        return head + INTERNAL + prelude + '\n' + d + e + '\n' + body + '\n'
    # moonbit_init too: with all of decls.h it was compiled again for any type changed anywhere (15-30 s on macos-15)
    if pieces:
        files['init.c'] = unit_text(set(), ''.join(f'CSPLIT_INTERNAL void {f}(void);\n' for f in init_calls)
                                    + 'void moonbit_init() {\n' + ''.join(f'{f}();\n' for f in init_calls) + '}\n', [])
        for unit in sorted(init_units):
            texts, used = init_units[unit]
            files[f'{unit}.c'] = unit_text(used, '\n'.join(t for _, t in texts), [t for _, t in texts])
    else:
        files['init.c'] = unit_text(init_used, init_text)
    for unit in sorted(units):
        texts, used = units[unit]
        files[f'{unit}.c'] = unit_text(used, '\n'.join(t for _, t in sorted(texts)), [t for _, t in texts])
        loads.append(sum(len(t) for _, t in texts))
    accounted = len(data) + len(funcs) + (len(decls) - stats['pp'] - stats['prototypes_added'])
    if accounted != len(items) - stats['pp']:
        fail(f'{len(items) - stats["pp"]} items, {accounted} placed')
    manifest = {
        'units': {name: len(text) for name, text in files.items()},
        'functions': len(funcs),
        'globals': len(data),
        'stats': stats,
        'init_bytes': len(inits[0][1]),
        'unit_loads': loads,
        'largest_function': max((len(f[1]), f[0]) for f in rest)[1],
        # moonc's statics, global in the split: by their names and as renamed (scripts/mbc.py check)
        'made_global': sorted(static_names | {names[n] for n in statics if n in names} | layout_names | set(init_calls)),
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

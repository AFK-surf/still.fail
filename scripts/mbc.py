#!/usr/bin/env python3
"""The C step of every native build: the C that moonc generates, split (scripts/csplit.py) and compiled in parallel.

    mbc.py gen [--dir MOD] [--debug] src/PKG
        moon's build of PKG with stand-ins for its C compiler and archiver (scripts/mbc-stub.sh): only moonc runs.
        Prints the generated .c; fails if moon did not write it anew. (Android, iOS: their compiler is not moon's.)
    mbc.py compile --cc CC --cflags FLAGS [--gen-flags F] [--init-flags F] [--extra FILE…] [--optional FILE…]
                   [--objc-flags F] --obj DIR [-j N] [-n UNITS] FILE.c
        FILE.c split into units and compiled with the extra C/Objective-C files, all at once (-j, default the
        cores); prints the objects. An object whose command and inputs (its depfile's, by content) did not change is
        kept. --optional files that do not compile are left out (as the runtime's that a platform lacks).
    mbc.py wrap --real CC -- ARGS…
        A C compiler for moon itself (macOS, Windows: scripts/mbc-cc.sh, scripts/mbc-cl.c on PATH as cc / cl):
        every command goes to CC as is, except the one that compiles and links moonc's C into the program, which is
        split, compiled in parallel and linked from the objects. MBC_SPLIT=0 passes that one through too.
    mbc.py link --out OUT [--dep PATH…] -- LINK COMMAND…
        The link, unless the same command made OUT of the same inputs already (by content: the files it names and
        the --dep ones). wrap's link is the same.
    mbc.py check --cc CC --cflags FLAGS [--nm NM] --obj DIR FILE.c
        The self-check: FILE.c compiled whole and split; the global symbols each defines must be the same, none
        defined twice among the units.
    mbc.py work MOON.WORK COPY
        A workspace's moon.work for a copy of its module elsewhere: the module ".", its other members by absolute path.
    mbc.py mirror STAGE COPY
        COPY's files as STAGE has them (each file and directory at STAGE's top, the rest of COPY left alone: its
        _build), a file only written when its content changed, so that moon, which goes by mtimes, builds anew only
        what changed (scripts/win.sh: the copies of the modules it makes afresh each build). Gone from STAGE: gone.

moonbit_init (every global's initial value, tens of thousands of lines, run once) is a unit of its own, compiled with
--init-flags (MBC_INIT_FLAGS) after the others' flags: by default -O0 (/Od), as optimising it is most of the time
the whole program takes to compile at any level (still.fail's: clang -O1 9 s, -O0 2 s, the other units 3 s each;
MSVC, moonbitlang/moon#2254: cl /O2 takes minutes). It runs once, at the start; its frame at -O0 is some 43 KB.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import csplit  # noqa: E402


def log(msg):
    print('mbc: ' + msg, file=sys.stderr, flush=True)
    if os.environ.get('MBC_LOG'):
        # moon shows a command's output only when it fails: the wrapper's account of a build goes here too
        with open(os.environ['MBC_LOG'], 'a', encoding='utf-8') as f:
            f.write('mbc: ' + msg + '\n')


def die(msg):
    log(msg)
    sys.exit(1)


def default_init_flags(msvc):
    """moonbit_init's flags after the others' (MBC_INIT_FLAGS): it runs once, and optimising it is the slowest part
    of compiling the program at any level."""
    v = os.environ.get('MBC_INIT_FLAGS')
    return split_words(v) if v is not None else (['/Od'] if msvc else ['-O0'])


def split_words(s):
    return shlex.split(s or '', posix=os.name != 'nt')


def is_msvc(cc):
    name = os.path.basename(cc[0]).lower()
    return name in ('cl', 'cl.exe', 'clang-cl', 'clang-cl.exe')


_kinds = {}


def compiler_kind(cc):
    """'msvc', 'clang' (with 'apple' when it targets Apple's platforms: ld64) or 'other' (gcc…)."""
    k = tuple(cc)
    if k not in _kinds:
        if is_msvc(cc):
            _kinds[k] = ('msvc', False)
        else:
            def ask(flag):
                try:
                    return subprocess.run(cc + [flag], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.decode()
                except OSError:
                    return ''
            _kinds[k] = ('clang' if 'clang' in ask('--version') else 'other', 'apple' in ask('-dumpmachine'))
    return _kinds[k]


def lto_for(cc, j):
    """ThinLTO (MBC_LTO=thin, the default with clang; 0 turns it off): the split loses the inlining across units
    that the whole file had (frames 10-30% slower in scripts/bench.sh), ThinLTO's link brings it back, its backends in
    parallel. Returns the link's flags, or None."""
    if os.environ.get('MBC_LTO', 'thin') in ('0', 'off', 'no', ''):
        return None
    kind, apple = compiler_kind(cc)
    if kind == 'msvc':
        # MSVC's counterpart: whole-program optimisation (/GL) and link-time code generation, on up to 8 threads
        return ['/link', '/LTCG', f'/CGTHREADS:{min(8, j)}']
    if kind != 'clang':
        return None
    # ld64 runs ThinLTO's backends on every core by itself; lld takes the count
    return ['-flto=thin'] if apple else ['-flto=thin', f'-Wl,--thinlto-jobs={j}']


def lto_compile(msvc):
    return ['/GL'] if msvc else ['-flto=thin']


def with_link_flags(args, flags):
    """A compile-and-link command with the link's flags added (MSVC's after its /link)."""
    if flags and flags[0] == '/link':
        low = [x.lower() for x in args]
        for k, x in enumerate(low):
            if x in ('/link', '-link'):
                return args[:k + 1] + flags[1:] + args[k + 1:]
    return args + flags


# ---------------------------------------------------------------- gen

def cmd_gen(a):
    mod = os.path.abspath(a.dir)
    with open(os.path.join(mod, 'moon.mod'), encoding='utf-8') as f:
        text = f.read()
    m = re.search(r'^\s*source\s*=\s*"([^"]*)"', text, re.M)
    source = m.group(1) if m else '.'
    # a workspace's (moon.work) packages are built under their module's name
    name = re.search(r'^\s*name\s*=\s*"([^"]*)"', text, re.M)
    in_work = os.path.isfile(os.path.join(mod, 'moon.work')) and name
    pkg = a.pkg.rstrip('/')
    rel = os.path.relpath(pkg, source) if source not in ('', '.') else pkg
    mode = 'debug' if a.debug else 'release'
    target = os.path.abspath(a.target_dir) if a.target_dir else os.path.join(mod, '_build')
    out = os.path.join(target, 'native', mode, 'build', *([name.group(1)] if in_work else []), rel, os.path.basename(rel) + '.c')
    env = dict(os.environ)
    stub = os.path.join(HERE, 'mbc-stub.sh')
    env['MOON_CC'] = stub
    env['MOON_AR'] = stub
    cmd = ['moon', 'build', '--target', 'native'] + ([] if a.debug else ['--release']) + (
        ['--target-dir', target] if a.target_dir else []) + [pkg]
    t0 = time.time()
    p = subprocess.run(cmd, cwd=mod, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sys.stderr.write(p.stdout.decode('utf-8', 'replace'))
    # never an old one: moon succeeded, and the C is no older than the package's .core beside it (link-core's
    # input; when moon had nothing to do, both are as the last build left them)
    core = out[:-2] + '.core'
    said = p.stdout.decode('utf-8', 'replace')
    if re.search(r'^\s*Error\b', said, re.M):
        die(f'moon reported errors (exit {p.returncode}): its output above')
    if p.returncode != 0 or not os.path.isfile(out) or os.path.getsize(out) == 0 or not os.path.isfile(core) \
            or os.path.getmtime(out) < os.path.getmtime(core):
        die(f'moon did not write {out} (exit {p.returncode}{", no " + core if not os.path.isfile(core) else ""}): its '
            'output above; if moon now puts it elsewhere, mbc.py gen needs to know')
    log(f'{os.path.relpath(out)}: {os.path.getsize(out) // 1024} KB in {time.time() - t0:.1f} s (moon exit {p.returncode})')
    print(out)


# ---------------------------------------------------------------- work

def cmd_work(a):
    """A copy of a workspace's moon.work for a copy of its module elsewhere (scripts/android.sh's out/android/mod):
    the module itself stays ".", every other member by its absolute path. Written only when it changes."""
    base = os.path.dirname(os.path.abspath(a.src))
    with open(a.src, encoding='utf-8') as f:
        text = f.read()
    new = re.sub(r'"([^"]*)"', lambda m: '"."' if m.group(1) == '.' else
                 json.dumps(os.path.realpath(os.path.join(base, m.group(1)))), text)
    if not os.path.isfile(a.dst) or open(a.dst, encoding='utf-8').read() != new:
        with open(a.dst, 'w', encoding='utf-8') as f:
            f.write(new)


def cmd_mirror(a):
    def same(x, y):
        if os.path.getsize(x) != os.path.getsize(y):
            return False
        with open(x, 'rb') as f, open(y, 'rb') as g:
            return f.read() == g.read()
    written = 0
    for top in sorted(os.listdir(a.src)):
        src, dst = os.path.join(a.src, top), os.path.join(a.dst, top)
        if os.path.isfile(src):
            pairs = [(src, dst)]
            if os.path.isdir(dst):
                shutil.rmtree(dst)
        else:
            if os.path.isfile(dst):
                os.remove(dst)
            pairs = []
            for root, dirs, names in os.walk(src):
                rel = os.path.relpath(root, src)
                pairs += [(os.path.join(root, n), os.path.normpath(os.path.join(dst, rel, n))) for n in names]
            keep = {d for _, d in pairs}
            for root, dirs, names in os.walk(dst, topdown=False):
                for n in names:
                    if os.path.join(root, n) not in keep:
                        os.remove(os.path.join(root, n))
                if root != dst and not os.listdir(root):
                    os.rmdir(root)
        for s_, d in pairs:
            if os.path.isfile(d) and same(s_, d):
                continue
            os.makedirs(os.path.dirname(d), exist_ok=True)
            if os.path.isdir(d):
                shutil.rmtree(d)
            # (a file written now: newer than anything built from what it was)
            shutil.copyfile(s_, d)
            written += 1
    if os.environ.get('MBC_VERBOSE'):
        log(f'mirror {a.dst}: {written} files written')


# ---------------------------------------------------------------- compile

_hashes = {}


def file_hash(path):
    st = os.stat(path)
    k = (path, st.st_mtime_ns, st.st_size)
    h = _hashes.get(k)
    if h is None:
        with open(path, 'rb') as f:
            h = hashlib.sha1(f.read()).hexdigest()
        _hashes[k] = h
    return h


def depfile_paths(dep):
    with open(dep, encoding='utf-8', errors='replace') as f:
        text = f.read().replace('\\\n', ' ')
    _, _, rest = text.partition(':')
    paths = []
    for tok in re.split(r'(?<!\\)\s+', rest.strip()):
        if tok:
            paths.append(tok.replace('\\ ', ' '))
    return paths


class Job:
    def __init__(self, src, obj, argv, optional=False, depfile=None, weight=0):
        self.src, self.obj, self.argv, self.optional, self.depfile, self.weight = src, obj, argv, optional, depfile, weight
        self.secs = 0.0
        self.cached = False
        self.ok = True
        self.err = ''

    def stamp(self):
        return self.obj + '.mbc'

    def up_to_date(self):
        try:
            with open(self.stamp(), encoding='utf-8') as f:
                st = json.load(f)
        except (OSError, ValueError):
            return False
        if st.get('argv') != self.argv or not os.path.exists(self.obj):
            return False
        try:
            return all(file_hash(p) == h for p, h in st['deps'].items())
        except OSError:
            return False

    def run(self):
        if self.up_to_date():
            self.cached = True
            return self
        try:
            os.remove(self.stamp())
        except OSError:
            pass
        t0 = time.time()
        p = subprocess.run(self.argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.secs = time.time() - t0
        self.err = p.stdout.decode('utf-8', 'replace')
        self.ok = p.returncode == 0
        if self.ok:
            deps = [self.src]
            if self.depfile and os.path.exists(self.depfile):
                deps = depfile_paths(self.depfile)
            try:
                with open(self.stamp(), 'w', encoding='utf-8') as f:
                    json.dump({'argv': self.argv, 'deps': {d: file_hash(d) for d in deps}}, f)
            except OSError:
                pass
        return self


def compile_args(cc, flags, src, obj, msvc):
    """The command compiling `src` to `obj`, and its depfile (none with MSVC: those always compile)."""
    if msvc:
        return cc + flags + ['/nologo', '/c', src, '/Fo' + obj], None
    dep = obj + '.d'
    return cc + flags + ['-MMD', '-MF', dep, '-c', src, '-o', obj], dep


def run_jobs(jobs, j, label):
    t0 = time.time()
    jobs = sorted(jobs, key=lambda x: -x.weight)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, j)) as ex:
        list(ex.map(Job.run, jobs))
    wall = time.time() - t0
    bad = [x for x in jobs if not x.ok and not x.optional]
    for x in jobs:
        if not x.ok and x.optional:
            first = next((l for l in x.err.splitlines() if 'error' in l), x.err.strip()[:200])
            log(f'skip {x.src}: {first}')
        elif not x.ok:
            sys.stderr.write(x.err)
            log(f'{x.src} did not compile: ' + ' '.join(shlex.quote(w) for w in x.argv))
    built = [x for x in jobs if not x.cached]
    slow = sorted(built, key=lambda x: -x.secs)[:3]
    log(f'{label}: {len(built)} of {len(jobs)} compiled ({len(jobs) - len(built)} up to date) in {wall:.1f} s on '
        f'{j} jobs' + (('; slowest ' + ', '.join(f'{os.path.basename(x.src)} {x.secs:.1f} s' for x in slow)) if slow else ''))
    if bad:
        sys.exit(1)
    return [x.obj for x in jobs if x.ok]


def split_jobs(c_file, objdir, cc, flags, gen_flags, init_flags, units, msvc, lto=False):
    """Split c_file into objdir/src and the jobs compiling its units into objdir."""
    srcdir = os.path.join(objdir, 'src')
    with open(c_file, 'rb') as f:
        raw = f.read()
    t0 = time.time()
    # the same C split the same way as last time: the units are there already
    # a package's functions together (MBC_GROUP=package, the default; size: each function by itself): with ThinLTO
    # the frames of scripts/bench.sh are within 1% of the whole file's (size: 2%; without LTO 12% and 17% slower)
    group = os.environ.get('MBC_GROUP', 'package')
    key = hashlib.sha1(raw + f'\0{units}\0{group}\0{file_hash(os.path.abspath(csplit.__file__))}'.encode()).hexdigest()
    saved = os.path.join(srcdir, 'manifest.json')
    manifest = None
    try:
        with open(saved, encoding='utf-8') as f:
            m = json.load(f)
        if m.get('key') == key and all(os.path.isfile(os.path.join(srcdir, n)) for n in m['units']):
            manifest = m
    except (OSError, ValueError, KeyError):
        pass
    if manifest is None:
        try:
            files, manifest = csplit.split(raw.decode('utf-8', 'surrogateescape'), units, group)
        except csplit.SplitError as e:
            die(f'{c_file}: {e}')
        os.makedirs(srcdir, exist_ok=True)
        for old in os.listdir(srcdir):
            if old not in files:
                os.remove(os.path.join(srcdir, old))
        for name, body in files.items():
            csplit.write_if_changed(os.path.join(srcdir, name), body)
        manifest['key'] = key
        with open(saved, 'w', encoding='utf-8') as f:
            json.dump(manifest, f)
    files = {name: os.path.getsize(os.path.join(srcdir, name)) for name in manifest['units']}
    for old in os.listdir(objdir):
        # a unit's object (u_<unit>.o and its .d, .mbc) when the split has fewer units than before
        if old.startswith('u_') and old[2:].split('.')[0] + '.c' not in files:
            os.remove(os.path.join(objdir, old))
    s = manifest['stats']
    log(f'{os.path.basename(c_file)}: {manifest["functions"]} functions, {manifest["globals"]} globals -> '
        f'{len(files) - 2} units in {time.time() - t0:.1f} s (moonbit_init {manifest["init_bytes"] // 1024} KB, '
        f'functions {max(manifest["unit_loads"]) // 1024} KB a unit, decls.h {manifest["units"]["decls.h"] // 1024} KB'
        f'{", " + str(s["statics_dropped"]) + " static dropped" if s["statics_dropped"] else ""})')
    ext = '.obj' if msvc else '.o'
    jobs = []
    for name, size in files.items():
        if not name.endswith('.c'):
            continue
        # the units but moonbit_init's as ThinLTO's bitcode (lto): the link inlines across them as the whole file did
        f = flags + gen_flags + (init_flags if name == 'init.c' else lto_compile(msvc) if lto else [])
        src = os.path.join(srcdir, name)
        obj = os.path.join(objdir, 'u_' + name[:-2] + ext)
        argv, dep = compile_args(cc, f, src, obj, msvc)
        # moonbit_init first: the slowest to compile at any level
        weight = size * (4 if name == 'init.c' else 1)
        jobs.append(Job(src, obj, argv, depfile=dep, weight=weight))
    return jobs, manifest


def cmd_compile(a):
    cc = split_words(a.cc)
    msvc = is_msvc(cc)
    flags = split_words(a.cflags)
    gen_flags = split_words(a.gen_flags)
    init_flags = split_words(a.init_flags) if a.init_flags is not None else default_init_flags(msvc)
    objdir = os.path.abspath(a.obj)
    os.makedirs(objdir, exist_ok=True)
    j = a.j or os.cpu_count() or 4
    ext = '.obj' if msvc else '.o'
    link_flags = []
    if os.environ.get('MBC_SPLIT', '1') == '0':
        # the C whole, one unit (as before the split; for comparisons)
        obj = os.path.join(objdir, 'whole' + ext)
        argv, dep = compile_args(cc, flags + gen_flags, os.path.abspath(a.src), obj, msvc)
        jobs = [Job(a.src, obj, argv, depfile=dep, weight=1 << 40)]
    else:
        lto = lto_for(cc, j)
        jobs, _ = split_jobs(a.src, objdir, cc, flags, gen_flags, init_flags, a.n or j, msvc, lto is not None)
        link_flags = lto or []
        try:
            os.remove(os.path.join(objdir, 'whole' + ext))
        except OSError:
            pass
    seen = set()
    for path, optional in [(p, False) for p in a.extra] + [(p, True) for p in a.optional]:
        base = os.path.splitext(os.path.basename(path))[0]
        name = base
        k = 1
        while name in seen:
            k += 1
            name = f'{base}{k}'
        seen.add(name)
        f = flags + (split_words(a.objc_flags) if path.endswith('.m') else [])
        obj = os.path.join(objdir, 'x_' + name + ext)
        argv, dep = compile_args(cc, f, path, obj, msvc)
        jobs.append(Job(path, obj, argv, optional=optional, depfile=dep, weight=os.path.getsize(path)))
    for o in run_jobs(jobs, j, os.path.basename(a.src)):
        print(o)
    if a.link_flags:
        # what the link of these objects needs (ThinLTO's flags), for the caller's link command
        with open(a.link_flags, 'w') as f:
            f.write(' '.join(shlex.quote(x) for x in link_flags) + '\n')


# ---------------------------------------------------------------- link

def link_inputs(argv, deps, out):
    """The files a link reads that it names (objects, archives; not its output) and `deps` (files, or directories:
    their files)."""
    files = [x for x in argv if os.path.isfile(x) and os.path.abspath(x) != os.path.abspath(out)]
    for d in deps:
        if os.path.isdir(d):
            for root, _, names in os.walk(d):
                files += [os.path.join(root, n) for n in sorted(names)]
        elif os.path.isfile(d):
            files.append(d)
    return files


def link_stamp(out, stamp=None):
    return stamp or out + '.mbc-link'


def link_key(argv, deps, out):
    return json.dumps({'argv': argv, 'inputs': {p: file_hash(p) for p in link_inputs(argv, deps, out)}},
                      sort_keys=True)


def linked_already(argv, out, deps=(), stamp=None):
    """Whether `out` is what this command made of these very inputs (its command and their contents the same)."""
    try:
        with open(link_stamp(out, stamp), encoding='utf-8') as f:
            return os.path.isfile(out) and f.read() == link_key(argv, deps, out)
    except OSError:
        return False


def link(argv, out, deps=(), stamp=None):
    """Runs the link unless it made `out` of the same inputs already (then only its mtime moves on, for make-like
    tools after it). Returns its exit code."""
    if linked_already(argv, out, deps, stamp):
        os.utime(out)
        log(f'{os.path.basename(out)}: linked already from the same objects and flags')
        return 0
    try:
        os.remove(link_stamp(out, stamp))
    except OSError:
        pass
    t0 = time.time()
    code = subprocess.call(argv)
    log(f'linked {os.path.basename(out)} in {time.time() - t0:.1f} s')
    if code == 0 and os.path.isfile(out):
        with open(link_stamp(out, stamp), 'w', encoding='utf-8') as f:
            f.write(link_key(argv, deps, out))
    return code


def cmd_link(a):
    argv = a.argv[1:] if a.argv and a.argv[0] == '--' else a.argv
    sys.exit(link(argv, a.out, a.dep, a.stamp))


# ---------------------------------------------------------------- wrap

def gnu_compile_flags(args):
    """What of a compile-and-link command concerns compiling (the rest is the link's)."""
    out = []
    i = 0
    while i < len(args):
        x = args[i]
        if x in ('-arch', '-isysroot', '-target', '-include', '-isystem', '-iquote', '-I', '-D', '-U'):
            out += args[i:i + 2]
            i += 2
            continue
        if x.startswith('-Wl,') or x.startswith('-l') or x.startswith('-L') or x.startswith('-framework'):
            i += 1 + (x == '-framework')
            continue
        if re.match(r'-(I|D|U|f|O|g|std=|m|W|isysroot|target=|include)', x):
            out.append(x)
        i += 1
    return out


def msvc_compile_flags(args):
    out = []
    i = 0
    while i < len(args):
        x = args[i]
        lx = x.lower()
        if lx in ('/link', '-link'):
            break
        if lx in ('/i', '-i', '/d', '-d', '/u', '-u', '/fi', '-fi') and i + 1 < len(args):
            out += args[i:i + 2]
            i += 2
            continue
        if (x.startswith('/') or x.startswith('-')) and not os.path.isfile(x) and not re.match(r'[/-](fe|fo|link)', lx):
            out.append(x)
        i += 1
    return out


def response_files(args, msvc):
    """@FILE arguments (a long command line) as the arguments in them."""
    out = []
    for x in args:
        if x.startswith('@') and os.path.isfile(x[1:]):
            with open(x[1:], encoding='utf-8-sig', errors='replace') as f:
                words = shlex.split(f.read(), posix=not msvc)
            out += [w[1:-1] if msvc and len(w) > 1 and w[0] == w[-1] == '"' else w for w in words]
        else:
            out.append(x)
    return out


def plain_path(p):
    """A Windows path without the \\\\?\\ moon puts before it (cl does not open those)."""
    return p[4:] if p.startswith('\\\\?\\') else p


def cmd_wrap(a):
    real = [a.real] if os.path.isfile(a.real) else split_words(a.real)
    msvc = is_msvc(real)
    args = response_files(a.args, msvc)
    out = None
    for i, x in enumerate(args):
        if x == '-o' and i + 1 < len(args):
            out = args[i + 1]
        m = re.match(r'[/-]Fe:?(.+)', x) or re.match(r'(?i)[/-]out:(.+)', x)
        if m:
            out = m.group(1)
    out = plain_path(out) if out else out
    links = not any(x in ('-c', '/c', '-E', '/E', '-dumpmachine') for x in args)
    cs = [i for i, x in enumerate(args) if x.endswith('.c') and os.path.isfile(x)]
    if os.environ.get('MBC_SPLIT', '1') == '0' or not links or not out or not out.endswith('.exe') or len(cs) != 1:
        if os.environ.get('MBC_VERBOSE'):
            log('as is: ' + ' '.join(real + args))
        sys.exit(subprocess.call(real + args))
    c_file = args[cs[0]]
    objdir = out[:-4] + '.mbc'
    os.makedirs(objdir, exist_ok=True)
    flags = msvc_compile_flags(args) if msvc else gnu_compile_flags(args)
    init_flags = default_init_flags(msvc)
    j = int(os.environ.get('MBC_JOBS', '0')) or os.cpu_count() or 4
    lto = lto_for(real, j)
    jobs, _ = split_jobs(c_file, objdir, real, flags, [], init_flags, j, msvc, lto is not None)
    objs = run_jobs(jobs, j, os.path.basename(c_file))
    sys.exit(link(real + with_link_flags(args[:cs[0]] + objs + args[cs[0] + 1:], lto or []), out))


def cmd_shim(a):
    """DIR/cc (DIR/cl.exe on Windows) that moon finds first on PATH: `mbc.py wrap` over the real one."""
    d = os.path.abspath(a.dir)
    os.makedirs(d, exist_ok=True)
    path = [p for p in os.environ.get('PATH', '').split(os.pathsep) if p and os.path.abspath(p) != d]
    if os.name == 'nt':
        real = os.environ.get('MBC_REAL_CC') or shutil.which('cl', path=os.pathsep.join(path))
        if not real:
            die('no cl.exe on PATH (a Developer Command Prompt, or ilammy/msvc-dev-cmd)')
        # moon takes MSVC's lib.exe and link.exe from beside the cl.exe it finds: the same forwarder for them, each
        # running the command line in its .txt (cl's: mbc.py wrap over the real cl; lib's and link's: the real ones)
        exe = os.path.join(d, 'mbc-cl.exe')
        src = os.path.join(HERE, 'mbc-cl.c')
        if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
            p = subprocess.run([real, '/nologo', '/O1', src, '/Fe' + exe, '/Fo' + os.path.join(d, 'mbc-cl.obj')],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=d)
            if p.returncode != 0:
                die('mbc-cl.c did not compile:\n' + p.stdout.decode('utf-8', 'replace'))
        prefix = {'cl': [sys.executable, os.path.abspath(__file__), 'wrap', '--real', real, '--']}
        for tool in ('lib', 'link'):
            t = os.path.join(os.path.dirname(real), tool + '.exe')
            if not os.path.isfile(t):
                die(f'no {t} beside {real}')
            # (lib's archive with no time stamps in it: the same objects, the same .lib, and the link that takes it
            # found made already; cl's and link's own are scripts/win.sh's CL and LINK)
            prefix[tool] = [t, '/Brepro'] if tool == 'lib' else [t]
        for tool, line in prefix.items():
            t = os.path.join(d, tool + '.exe')
            if not os.path.isfile(t) or file_hash(t) != file_hash(exe):
                shutil.copyfile(exe, t)
            csplit.write_if_changed(os.path.join(d, tool + '.txt'), subprocess.list2cmdline(line))
    else:
        real = os.environ.get('MBC_REAL_CC') or shutil.which('cc', path=os.pathsep.join(path))
        if not real:
            die('no cc on PATH')
        sh = os.path.join(d, 'cc')
        # written only when it changes: moon builds anew what its C compiler's mtime is newer than
        csplit.write_if_changed(sh, '#!/bin/sh\n# scripts/mbc.py shim: moon\'s C compiler, scripts/mbc.py wrap over %s\n'
                                'exec %s %s wrap --real %s -- "$@"\n' % (real, shlex.quote(sys.executable),
                                                                          shlex.quote(os.path.abspath(__file__)),
                                                                          shlex.quote(real)))
        os.chmod(sh, 0o755)
    print(d)


# ---------------------------------------------------------------- check

def symbols(nm, obj):
    """(defined global symbols, undefined ones) of an object."""
    p = subprocess.run(nm + [obj], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        die(f'{" ".join(nm)} {obj}: {p.stderr.decode()[:300]}')
    defined, undefined = [], set()
    for line in p.stdout.decode('utf-8', 'replace').splitlines():
        parts = line.split()
        if len(parts) >= 3 and len(parts[-2]) == 1 and parts[-2] in 'TDRBSCVW':
            defined.append(parts[-1])
        elif len(parts) >= 2 and parts[-2] in ('U', 'w', 'v'):
            undefined.add(parts[-1])
    return defined, undefined


def cmd_check(a):
    cc = split_words(a.cc)
    flags = split_words(a.cflags)
    nm = split_words(a.nm)
    objdir = os.path.abspath(a.obj)
    os.makedirs(objdir, exist_ok=True)
    j = a.j or os.cpu_count() or 4
    whole = os.path.join(objdir, 'whole.o')
    argv, dep = compile_args(cc, flags, os.path.abspath(a.src), whole, False)
    jobs, manifest = split_jobs(a.src, os.path.join(objdir, 'split'), cc, flags, [], split_words(a.init_flags), j, False)
    objs = run_jobs(jobs + [Job(a.src, whole, argv, depfile=dep, weight=1 << 40)], j, 'check')
    one, one_needs = symbols(nm, whole)
    one = set(one)
    many, needs = [], set()
    for o in objs:
        if o != whole:
            d, u = symbols(nm, o)
            many += d
            needs |= u
    twice = sorted(s for s, k in collections.Counter(many).items() if k > 1)
    split_set = set(many)
    only_whole = sorted(one - split_set)
    only_split = sorted(split_set - one)
    # and what they take from outside (the runtime, the host, libc) is the same too
    needs -= split_set
    # (the C library's functions that a compiler calls or folds as it optimises differ with what it inlines: memset
    # for a loop, free in a helper inlined or not, sin and cos as sincos; shown, not counted)
    libc = re.compile(r'_?(mem\w*|bzero|free|malloc|calloc|realloc|abort|str\w*|__\w+|(a?sinh?|a?cosh?|a?tanh?|atan2|'
                      r'sincos|exp\w*|log\w*|pow|sqrt|cbrt|floor|ceil|round|trunc|fabs|fmod|hypot)[fl]?)$')
    # (moonc's statics are globals in the split, kept when nothing calls them, as the whole file's are not: what they
    # take from outside the split may take alone; never the other way)
    extra = needs - one_needs if manifest['made_global'] else set()
    needs_diff = sorted(x for x in (needs ^ one_needs) - extra if not libc.match(x))
    libc_diff = sorted(x for x in needs ^ one_needs if libc.match(x))
    # moonc's statics (none today) are globals in the split: only those may be in the split alone
    only_split = [s for s in only_split if (s[1:] if s.startswith('_') else s) not in manifest['made_global']
                  and s not in manifest['made_global']]
    log(f'check: whole {len(one)} global symbols, split {len(split_set)} ({len(many)} definitions); '
        f'only whole {len(only_whole)}, only split {len(only_split)}, defined twice {len(twice)}; '
        f'{len(one_needs)} taken from outside, {len(needs_diff)} different'
        f'{" (" + str(len(extra)) + " more by moonc statics the whole file dropped)" if extra else ""}'
        f'{" (and the C library " + ", ".join(libc_diff) + ")" if libc_diff else ""}')
    for title, xs in (('only in the whole', only_whole), ('only in the split', only_split), ('twice', twice),
                      ('taken from outside by one only', needs_diff)):
        for s in xs[:20]:
            log(f'  {title}: {s}')
    ok = not only_whole and not only_split and not twice and not needs_diff
    print('ok' if ok else 'FAIL')
    sys.exit(0 if ok else 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    g = sub.add_parser('gen')
    g.add_argument('--dir', default='.')
    g.add_argument('--debug', action='store_true')
    g.add_argument('--target-dir', help="moon's build directory (default the module's _build): the stand-ins' empty "
                   "objects and program then stay out of a build for this machine")
    g.add_argument('pkg')
    c = sub.add_parser('compile')
    c.add_argument('--cc', required=True)
    c.add_argument('--cflags', default='')
    c.add_argument('--gen-flags', default='')
    c.add_argument('--init-flags')
    c.add_argument('--objc-flags', default='-fobjc-arc')
    c.add_argument('--extra', action='append', default=[])
    c.add_argument('--optional', action='append', default=[])
    c.add_argument('--obj', required=True)
    c.add_argument('-j', type=int, default=0)
    c.add_argument('-n', type=int, default=0)
    c.add_argument('--link-flags', help='write the flags the link of the objects needs (ThinLTO) here')
    c.add_argument('src')
    w = sub.add_parser('wrap')
    w.add_argument('--real', required=True)
    w.add_argument('args', nargs=argparse.REMAINDER)
    ln = sub.add_parser('link')
    ln.add_argument('--out', required=True)
    ln.add_argument('--dep', action='append', default=[], help='a file or directory the link reads unnamed (-L)')
    ln.add_argument('--stamp', help='where to keep what the link was made of (default OUT.mbc-link)')
    ln.add_argument('argv', nargs=argparse.REMAINDER)
    wk = sub.add_parser('work')
    wk.add_argument('src')
    wk.add_argument('dst')
    mi = sub.add_parser('mirror')
    mi.add_argument('src')
    mi.add_argument('dst')
    sh = sub.add_parser('shim')
    sh.add_argument('dir')
    k = sub.add_parser('check')
    k.add_argument('--cc', required=True)
    k.add_argument('--cflags', default='')
    k.add_argument('--init-flags', default='')
    k.add_argument('--nm', default='nm')
    k.add_argument('--obj', required=True)
    k.add_argument('-j', type=int, default=0)
    k.add_argument('src')
    a = ap.parse_args()
    if a.cmd == 'wrap' and a.args and a.args[0] == '--':
        a.args = a.args[1:]
    {'gen': cmd_gen, 'compile': cmd_compile, 'link': cmd_link, 'wrap': cmd_wrap, 'shim': cmd_shim,
     'check': cmd_check, 'work': cmd_work, 'mirror': cmd_mirror}[a.cmd](a)


if __name__ == '__main__':
    main()

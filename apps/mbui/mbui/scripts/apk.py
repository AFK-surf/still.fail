#!/usr/bin/env python3
"""An Android app's APK without Gradle: its Java compiled, shrunk by R8, its resources and manifest linked by aapt2,
its native libraries and assets packed, aligned and signed, with the SDK's own tools (and R8 at a version pinned here).

    apk.py lock APP.json             its dependencies (APP.json's "lock": group:artifact:version a line) fetched once and
                                     their SHA-256 written beside each, so builds take those bytes and no others
    apk.py build APP.json --variant release|debug --version-code N --version-name S --out APP.apk
                                     [--abi arm64-v8a] [--keystore PATH]
    apk.py fetch PATH SHA256         a file of the Maven repositories (its path in one), checked, kept: its local path

APP.json (paths relative to it): "namespace" (its Java package, R's), "applicationId", "minSdk", "targetSdk",
"compileSdk", "manifest", "java" [dirs], "res" [dirs], "assets" [dirs], "jniLibs" [dirs], "rules" [R8 files],
"lock" (the dependencies' file), "variants": {"release"|"debug": {"applicationIdSuffix", "placeholders": {…},
"minify": bool}}, "strings": {resource name: [env var naming a JSON file, its key]} (values put in as string
resources: what is secret to the build, read by the app as it starts).

Why: Gradle's release build (AGP 9) ran R8 and lint again on every build, as the versionCode (main's commit count)
is in the manifest R8 reads for its resource shrinking, and its cache could never be hit: most of CI's minute of
Gradle (2026-10-22). Here R8's output is kept by what it is made of (the classes, the dependencies, the rules, R8's
version), the build's number only in the manifest linked at the end. The manifest is the app's with its placeholders
filled and its components' names made whole, and what its libraries' manifests add to <application> (attributes
alone: one with anything else stops this, rather than a merge it does not do). The libraries' resources are
linked beside the app's (R classes for each package); resources are not shrunk (R8's shrinker reads the linked
manifest); stripped of nothing, the native libraries compressed (extractNativeLibs), as the release had them.

Tools: $ANDROID_HOME's platforms/android-<compileSdk>/android.jar and the newest build-tools' aapt2, zipalign and
apksigner; java and javac (17 or newer); R8 from Google's Maven at R8_VERSION. Everything fetched is kept in
$APK_CACHE (default ~/.cache/mbui-apk) by its content's hash.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile

R8_VERSION = '9.0.55'
REPOS = ['https://dl.google.com/dl/android/maven2', 'https://repo1.maven.org/maven2']
ANDROID_NS = 'http://schemas.android.com/apk/res/android'


def log(msg):
    print(f'apk: {msg}', flush=True)


def die(msg):
    print(f'apk: {msg}', file=sys.stderr, flush=True)
    sys.exit(1)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def cache_dir():
    d = os.environ.get('APK_CACHE') or os.path.join(os.path.expanduser('~'), '.cache', 'mbui-apk')
    os.makedirs(d, exist_ok=True)
    return d


def fetch(url, dest):
    """`url` into `dest`; False where the repository has no such file. (Once: what is fetched is kept in the cache, CI's
    by its Actions cache, so a build fetches only what a change of the lock asks for.)"""
    tmp = dest + '.part'
    try:
        # (a name of its own: Maven Central turns Python's default User-Agent away with a 403)
        req = urllib.request.Request(url, headers={'User-Agent': 'mbui-apk/1'})
        with urllib.request.urlopen(req, timeout=60) as r, open(tmp, 'wb') as f:
            shutil.copyfileobj(r, f)
    except urllib.error.HTTPError as e:
        # (Google's Maven answers 403 for what it does not have, after a redirect: the next repository's)
        if e.code in (403, 404):
            return False
        raise
    os.replace(tmp, dest)
    return True


def artifact_path(coord, ext):
    g, a, v = coord.split(':')
    return f'{g.replace(".", "/")}/{a}/{v}/{a}-{v}.{ext}'


def get_artifact(coord, ext, sha=None):
    """The artifact coord.ext, from the cache or the repositories; checked against `sha` when given."""
    name = coord.replace(':', '_') + '.' + ext
    dest = os.path.join(cache_dir(), 'm2', name)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if not os.path.exists(dest):
        if not any(fetch(f'{repo}/{artifact_path(coord, ext)}', dest) for repo in REPOS):
            return None
    if sha and sha256_file(dest) != sha:
        os.remove(dest)
        die(f'{coord}.{ext}: not the SHA-256 the lock has ({sha})')
    return dest


def cmd_fetch(a):
    dest = os.path.join(cache_dir(), 'm2', a.path.replace('/', '_'))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if not os.path.exists(dest) and not any(fetch(f'{repo}/{a.path}', dest) for repo in REPOS):
        die(f'{a.path}: not found')
    if sha256_file(dest) != a.sha:
        os.remove(dest)
        die(f'{a.path}: not the SHA-256 asked for ({a.sha})')
    print(dest)


# ---- the dependencies' lock ----

def read_lock(path):
    """[(coord, ext or None, sha or None)] of the lock's lines (group:artifact:version [ext sha256]); # comments."""
    out = []
    with open(path) as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            out.append((parts[0], parts[1] if len(parts) > 1 else None, parts[2] if len(parts) > 2 else None))
    return out


def cmd_lock(a):
    cfg, base = load(a.app)
    path = os.path.join(base, cfg['lock'])
    with open(path) as f:
        head = [l for l in f.read().split('\n') if l.startswith('#')]
    lines = []
    for coord, _, _ in read_lock(path):
        for ext in ('aar', 'jar'):
            p = get_artifact(coord, ext)
            if p:
                lines.append(f'{coord} {ext} {sha256_file(p)}')
                break
        else:
            lines.append(f'{coord} none')  # a BOM, or a root of Kotlin's multiplatform: nothing to pack
    with open(path, 'w') as f:
        f.write('\n'.join(head + lines) + '\n')
    log(f'{path}: {len(lines)} dependencies')


# ---- the build ----

def load(app):
    with open(app) as f:
        return json.load(f), os.path.dirname(os.path.abspath(app))


def run(argv, **kw):
    r = subprocess.run(argv, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        die(f'{os.path.basename(argv[0])} failed: ' + ' '.join(argv[:6]) + ' …')
    return r


def sdk_tools(compile_sdk):
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or \
        os.path.join(os.path.expanduser('~'), 'Library/Android/sdk')
    jar = os.path.join(sdk, 'platforms', f'android-{compile_sdk}', 'android.jar')
    if not os.path.exists(jar):
        die(f'no {jar}')
    bts = sorted((d for d in os.listdir(os.path.join(sdk, 'build-tools')) if re.match(r'\d+\.\d+\.\d+$', d)),
                 key=lambda v: [int(x) for x in v.split('.')])
    if not bts:
        die(f'no build-tools in {sdk}')
    bt = os.path.join(sdk, 'build-tools', bts[-1])
    return jar, bt


def extract_aar(path, sha):
    """An AAR unpacked once into the cache (by its hash): its classes, libraries, res, manifest, rules, R.txt."""
    d = os.path.join(cache_dir(), 'aar', sha[:24])
    if not os.path.exists(os.path.join(d, '.done')):
        shutil.rmtree(d, ignore_errors=True)
        with zipfile.ZipFile(path) as z:
            z.extractall(d)
        open(os.path.join(d, '.done'), 'w').close()
    return d


def tree_hash(paths, exts=None):
    """A hash of the files under `paths` (their paths below each and contents), in order."""
    h = hashlib.sha256()
    for base in paths:
        if not os.path.exists(base):
            continue
        if os.path.isfile(base):
            h.update(b'F' + base.encode() + b'\0')
            with open(base, 'rb') as f:
                h.update(f.read())
            continue
        for root, dirs, files in os.walk(base):
            dirs.sort()
            for n in sorted(files):
                if exts and not n.endswith(exts):
                    continue
                p = os.path.join(root, n)
                h.update(os.path.relpath(p, base).encode() + b'\0')
                with open(p, 'rb') as f:
                    h.update(f.read())
    return h.hexdigest()


def manifest_text(cfg, base, variant, app_id, libs):
    """The app's manifest as it goes to aapt2: placeholders filled, its components' names whole, tools: gone, and
    what the libraries' manifests put on <application>."""
    with open(os.path.join(base, cfg['manifest']), encoding='utf-8') as f:
        text = f.read()
    ph = dict(variant.get('placeholders', {}))
    ph['applicationId'] = app_id
    for k, v in ph.items():
        text = text.replace('${' + k + '}', v)
    left = re.findall(r'\$\{(\w+)\}', text)
    if left:
        die(f'manifest placeholders not given: {left}')
    ns = cfg['namespace']
    tags = ('application', 'activity', 'activity-alias', 'service', 'receiver', 'provider')
    text = re.sub(r'(<(?:' + '|'.join(tags) + r')\b[^>]*?android:name=")\.', lambda m: m.group(1) + ns + '.', text)
    text = re.sub(r'\s+tools:\w+="[^"]*"', '', text)
    text = re.sub(r'\s+xmlns:tools="[^"]*"', '', text)
    # the libraries' <application> attributes (androidx.core's appComponentFactory), not those the app sets, and the
    # permissions they ask for that the app does not
    added = {}
    permissions = []
    for name, d in libs:
        mpath = os.path.join(d, 'AndroidManifest.xml')
        if not os.path.exists(mpath):
            continue
        with open(mpath, encoding='utf-8') as f:
            lm = re.sub(r'<!--.*?-->', '', f.read(), flags=re.S)
        body = re.sub(r'<\?xml[^>]*>', '', lm)
        body = re.sub(r'<manifest\b[^>]*>|</manifest>|<uses-sdk\b[^>]*/>', '', body)
        app = re.search(r'<application\b([^>]*?)(/>|>(.*?)</application>)', body, re.S)
        rest = body.replace(app.group(0), '') if app else body
        # (a permission it asks for: the app's own too, once)
        for perm in re.findall(r'<uses-permission\b[^>]*/>', rest):
            pname = re.search(r'android:name="([^"]+)"', perm)
            if pname and f'android:name="{pname.group(1)}"' not in text:
                permissions.append(perm)
            rest = rest.replace(perm, '')
        if rest.strip() or (app and app.group(3) and app.group(3).strip()):
            die(f'{name}: its manifest adds more than <application> attributes; merge it here first:\n{body.strip()}')
        if app:
            for k, v in re.findall(r'(android:\w+)="([^"]*)"', app.group(1)):
                added.setdefault(k, v)
    app_open = re.search(r'<application\b[^>]*', text)
    if app_open is None:
        die('no <application> in the manifest')
    have = set(re.findall(r'(android:\w+)=', app_open.group(0)))
    extra = ''.join(f' {k}="{v}"' for k, v in sorted(added.items()) if k not in have)
    extra += '' if 'android:extractNativeLibs' in have else ' android:extractNativeLibs="true"'
    if variant.get('debuggable'):
        extra += ' android:debuggable="true"'
    text = text[:app_open.end()] + extra + text[app_open.end():]
    # its package: the application id (the namespace is R's and the components' names')
    text = re.sub(r'<manifest\b', f'<manifest package="{app_id}"', text, count=1)
    if permissions:
        at = text.index('<application')
        text = text[:at] + ''.join(p + '\n    ' for p in dict.fromkeys(permissions)) + text[at:]
    return text


def write_strings(cfg, d):
    """The build's string resources from the environment (cfg "strings"), as a values file under `d`."""
    vals = []
    for name, (var, key) in sorted(cfg.get('strings', {}).items()):
        v = ''
        p = os.environ.get(var)
        if p and os.path.exists(p):
            with open(p) as f:
                v = str(json.load(f).get(key, ''))
        v = v.replace('\\', '\\\\').replace('"', '\\"').replace('&', '&amp;').replace('<', '&lt;').replace("'", "\\'")
        vals.append(f'  <string name="{name}" translatable="false">{v}</string>')
    os.makedirs(os.path.join(d, 'values'), exist_ok=True)
    with open(os.path.join(d, 'values', 'build_strings.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + '\n'.join(vals) + '\n</resources>\n')


def llvm_strip():
    """The NDK's llvm-strip (the newest NDK's), as AGP strips a release's native libraries with."""
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or \
        os.path.join(os.path.expanduser('~'), 'Library/Android/sdk')
    ndks = sorted(os.listdir(os.path.join(sdk, 'ndk')), key=lambda v: [int(x) for x in re.findall(r'\d+', v)]) \
        if os.path.isdir(os.path.join(sdk, 'ndk')) else []
    for n in reversed(ndks):
        for host in ('darwin-x86_64', 'linux-x86_64', 'windows-x86_64'):
            p = os.path.join(sdk, 'ndk', n, 'toolchains', 'llvm', 'prebuilt', host, 'bin', 'llvm-strip')
            if os.path.exists(p):
                return p
    die(f'no NDK llvm-strip in {sdk}/ndk')


def stripped(path):
    """`path` with its debug symbols stripped (--strip-unneeded, as AGP's stripReleaseDebugSymbols), kept by its
    content's hash."""
    out = os.path.join(cache_dir(), 'strip', sha256_file(path)[:32] + '.so')
    if os.path.exists(out):
        os.utime(out)
    else:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        run([llvm_strip(), '--strip-unneeded', '-o', out + '.tmp', path])
        os.replace(out + '.tmp', out)
    return out


def dex_order(n):
    """classes.dex, then classes2.dex, classes3.dex… in their number's order."""
    m = re.match(r'classes(\d*)\.dex$', n)
    return (int(m.group(1) or 1) if m else 0, n)


def lib_dex(r8, android_jar, min_api, jar, others):
    """A dependency's jar dexed (D8, debug) once, kept by its bytes, R8's version and the API level."""
    key = hashlib.sha256(f'{sha256_file(jar)} {R8_VERSION} {min_api}'.encode()).hexdigest()[:32]
    d = os.path.join(cache_dir(), 'dexlib', key)
    if not os.path.exists(os.path.join(d, '.done')):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        run(['java', '-cp', r8, 'com.android.tools.r8.D8', '--debug', '--min-api', str(min_api), '--lib', android_jar,
             '--output', d, jar] + [x for o in others for x in ('--classpath', o)])
        open(os.path.join(d, '.done'), 'w').close()
    return d


def prune():
    """The cache kept small: the newest 6 dex outputs, the newest 24 stripped libraries."""
    for sub, keep in (('dex', 6), ('strip', 24)):
        d = os.path.join(cache_dir(), sub)
        if not os.path.isdir(d):
            continue
        items = sorted((os.path.join(d, n) for n in os.listdir(d)), key=os.path.getmtime, reverse=True)
        for p in items[keep:]:
            shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else os.remove(p)


def cmd_build(a):
    t0 = time.time()
    times = {}

    def lap(what, since):
        times[what] = time.time() - since
        return time.time()
    cfg, base = load(a.app)
    variant = cfg['variants'][a.variant]
    app_id = cfg['applicationId'] + variant.get('applicationIdSuffix', '')
    minify = variant.get('minify', False)
    android_jar, bt = sdk_tools(cfg['compileSdk'])
    aapt2 = os.path.join(bt, 'aapt2')
    work = tempfile.mkdtemp(prefix='apk-')
    t = time.time()
    # the dependencies: AARs unpacked (classes, their res), jars as they are
    deps = [(c, e, s) for c, e, s in read_lock(os.path.join(base, cfg['lock'])) if e and e != 'none']
    jars, libs, rules = [], [], []
    for coord, ext, sha in deps:
        p = get_artifact(coord, ext, sha)
        if p is None:
            die(f'{coord}.{ext}: not found')
        if ext == 'jar':
            jars.append(p)
            continue
        d = extract_aar(p, sha)
        libs.append((coord, d))
        for j in [os.path.join(d, 'classes.jar')] + sorted(
                os.path.join(d, 'libs', n) for n in (os.listdir(os.path.join(d, 'libs')) if os.path.isdir(os.path.join(d, 'libs')) else [])):
            if os.path.exists(j):
                jars.append(j)
        if os.path.exists(os.path.join(d, 'proguard.txt')):
            rules.append(os.path.join(d, 'proguard.txt'))
    t = lap('dependencies', t)
    # resources: each library's compiled once (by its own content), the app's and the build's strings each time
    strings = os.path.join(work, 'strings')
    write_strings(cfg, strings)
    compiled = []
    lib_packages = []
    for coord, d in libs:
        res = os.path.join(d, 'res')
        m = re.search(r'package="([^"]+)"', open(os.path.join(d, 'AndroidManifest.xml'), encoding='utf-8').read())
        if not os.path.isdir(res) or not os.listdir(res):
            continue
        if m:
            lib_packages.append(m.group(1))
        out = os.path.join(cache_dir(), 'flat', tree_hash([res])[:24] + '.zip')
        if not os.path.exists(out):
            os.makedirs(os.path.dirname(out), exist_ok=True)
            run([aapt2, 'compile', '--dir', res, '-o', out + '.tmp'])
            os.replace(out + '.tmp', out)
        compiled.append(out)
    app_flat = []
    for i, res in enumerate([os.path.join(base, r) for r in cfg.get('res', [])] + [strings]):
        if os.path.isdir(res):
            out = os.path.join(work, f'app{i}.zip')
            run([aapt2, 'compile', '--dir', res, '-o', out])
            app_flat.append(out)
    t = lap('resources compiled', t)
    # the manifest, linked with everything: resources.arsc, res/, the binary manifest, R.java, the rules it keeps
    man = os.path.join(work, 'AndroidManifest.xml')
    with open(man, 'w', encoding='utf-8') as f:
        f.write(manifest_text(cfg, base, variant, app_id, libs))
    gen = os.path.join(work, 'gen')
    ap = os.path.join(work, 'res.ap_')
    aapt_rules = os.path.join(work, 'aapt_rules.txt')
    link = [aapt2, 'link', '-I', android_jar, '--manifest', man, '-o', ap, '--java', gen, '--proguard', aapt_rules,
            '--min-sdk-version', str(cfg['minSdk']), '--target-sdk-version', str(cfg['targetSdk']),
            '--version-code', str(a.version_code), '--version-name', a.version_name,
            '--custom-package', cfg['namespace'], '--auto-add-overlay', '--no-version-vectors']
    if lib_packages:
        link += ['--extra-packages', ':'.join(sorted(set(lib_packages)))]
    for c in compiled:
        link += ['-R', c]
    for c in app_flat:
        link += ['-R', c]
    run(link)
    t = lap('linked', t)
    # dex: javac, then R8 (release) or D8, kept by what they are made of: the Java's sources (the app's and R's), the
    # dependencies, the rules, the tools (not the manifest: the build's number is in it); kept, neither runs
    srcs = []
    for d in [os.path.join(base, j) for j in cfg.get('java', [])] + [gen]:
        for root, _, files in os.walk(d):
            srcs += [os.path.join(root, n) for n in sorted(files) if n.endswith('.java')]
    r8 = get_artifact(f'com.android.tools:r8:{R8_VERSION}', 'jar')
    all_rules = [os.path.join(base, r) for r in cfg.get('rules', [])] + rules
    default_rules = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'apk-proguard-android-optimize.txt')
    # (aapt2's rules say where each came from: this build's own temporary paths, not what they keep)
    with open(aapt_rules) as f:
        kept = ''.join(l for l in f if not l.lstrip().startswith('#'))
    with open(aapt_rules, 'w') as f:
        f.write(kept)
    key = hashlib.sha256()
    key.update(f'{R8_VERSION} {minify} {cfg["minSdk"]} {a.variant} {os.environ.get("JAVA_HOME", "")}\0'.encode())
    for p in srcs:
        key.update(os.path.basename(p).encode() + b'\0')
        key.update(sha256_file(p).encode())
    for p in jars + all_rules + [default_rules, android_jar]:
        key.update(sha256_file(p).encode())
    key.update(kept.encode())
    dex_dir = os.path.join(cache_dir(), 'dex', key.hexdigest()[:32])
    if not os.path.exists(os.path.join(dex_dir, '.done')):
        classes = os.path.join(work, 'classes')
        os.makedirs(classes)
        with open(os.path.join(work, 'srcs.txt'), 'w') as f:
            f.write('\n'.join(srcs))
        run(['javac', '-nowarn', '-encoding', 'UTF-8', '-source', '17', '-target', '17', '-Xlint:-options',
             '-cp', os.pathsep.join([android_jar] + jars), '-d', classes, '@' + os.path.join(work, 'srcs.txt')])
        t = lap('javac', t)
        shutil.rmtree(dex_dir, ignore_errors=True)
        os.makedirs(dex_dir)
        jar_in = os.path.join(work, 'app-classes.jar')
        with zipfile.ZipFile(jar_in, 'w') as z:
            for root, _, files in os.walk(classes):
                for n in sorted(files):
                    p = os.path.join(root, n)
                    z.write(p, os.path.relpath(p, classes))
        if minify:
            cmd = ['java', '-cp', r8, 'com.android.tools.r8.R8', '--release', '--min-api', str(cfg['minSdk']),
                   '--lib', android_jar, '--output', dex_dir, '--pg-conf', default_rules, '--pg-conf', aapt_rules,
                   '--pg-map-output', os.path.join(dex_dir, 'mapping.txt')]
            for r in all_rules:
                cmd += ['--pg-conf', r]
            cmd += [jar_in] + jars
        else:
            # (debug: the app's own classes alone, the dependencies on their classpath: they are dexed apart, below)
            cmd = ['java', '-cp', r8, 'com.android.tools.r8.D8', '--debug', '--min-api', str(cfg['minSdk']),
                   '--lib', android_jar, '--output', dex_dir, jar_in] + [x for j in jars for x in ('--classpath', j)]
        run(cmd)
        open(os.path.join(dex_dir, '.done'), 'w').close()
        t = lap('r8' if minify else 'd8', t)
    else:
        os.utime(dex_dir)
        t = lap('dex (kept)', t)
    # a debug build's dependencies: each dexed once, by its own bytes (the lock's), side by side with the app's
    # (classes2.dex on: minSdk 29 loads them all), as Gradle's debug builds dex each library apart
    dexes = [os.path.join(dex_dir, n) for n in sorted(os.listdir(dex_dir), key=dex_order) if n.endswith('.dex')]
    if not minify:
        for j in jars:
            d = lib_dex(r8, android_jar, cfg['minSdk'], j, [x for x in jars if x != j])
            dexes += [os.path.join(d, n) for n in sorted(os.listdir(d), key=dex_order) if n.endswith('.dex')]
        t = lap('dependencies dexed', t)
    # the APK: what aapt2 linked, the dex, the native libraries (compressed), the assets, the jars' resources
    unsigned = os.path.join(work, 'unsigned.apk')
    shutil.copy(ap, unsigned)
    with zipfile.ZipFile(unsigned, 'a', zipfile.ZIP_DEFLATED) as z:
        for i, p in enumerate(dexes):
            z.write(p, 'classes.dex' if i == 0 else f'classes{i + 1}.dex', compress_type=zipfile.ZIP_STORED)
        for d in [os.path.join(base, x) for x in cfg.get('jniLibs', [])]:
            for abi in ([a.abi] if a.abi else sorted(os.listdir(d)) if os.path.isdir(d) else []):
                ad = os.path.join(d, abi)
                if os.path.isdir(ad):
                    for n in sorted(os.listdir(ad)):
                        if n.endswith('.so'):
                            z.write(stripped(os.path.join(ad, n)), f'lib/{abi}/{n}')
        for d in [os.path.join(base, x) for x in cfg.get('assets', [])]:
            if os.path.isdir(d):
                for root, _, files in os.walk(d):
                    for n in sorted(files):
                        p = os.path.join(root, n)
                        z.write(p, 'assets/' + os.path.relpath(p, d))
        seen = set(z.namelist())
        for j in jars:
            with zipfile.ZipFile(j) as jz:
                for n in jz.namelist():
                    keep = (n.endswith('.kotlin_builtins') or (n.startswith('META-INF/') and n.endswith('.version')))
                    if keep and n not in seen:
                        z.writestr(n, jz.read(n))
                        seen.add(n)
    t = lap('packed', t)
    aligned = os.path.join(work, 'aligned.apk')
    run([os.path.join(bt, 'zipalign'), '-P', '16', '-f', '4', unsigned, aligned])
    ks = a.keystore or os.path.join(os.environ.get('ANDROID_USER_HOME') or os.path.join(os.path.expanduser('~'), '.android'),
                                    'debug.keystore')
    if not os.path.exists(ks):
        # (no key given, as a branch's CI has none: a debug key of its own, as Gradle made one)
        os.makedirs(os.path.dirname(os.path.abspath(ks)), exist_ok=True)
        run(['keytool', '-genkeypair', '-keystore', ks, '-storepass', 'android', '-alias', 'androiddebugkey',
             '-keypass', 'android', '-keyalg', 'RSA', '-validity', '10000', '-dname', 'CN=Android Debug,O=Android,C=US'])
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    run([os.path.join(bt, 'apksigner'), 'sign', '--ks', ks, '--ks-pass', 'pass:android', '--ks-key-alias',
         'androiddebugkey', '--key-pass', 'pass:android', '--v1-signing-enabled', 'false', '--v2-signing-enabled', 'true',
         '--v3-signing-enabled', 'false', '--out', a.out, aligned])
    lap('signed', t)
    shutil.rmtree(work, ignore_errors=True)
    prune()
    log(f'{a.out}: {os.path.getsize(a.out)} bytes in {time.time() - t0:.1f} s: ' +
        ', '.join(f'{k} {v:.1f} s' for k, v in times.items()))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    lk = sub.add_parser('lock')
    lk.add_argument('app')
    b = sub.add_parser('build')
    b.add_argument('app')
    b.add_argument('--variant', default='debug')
    b.add_argument('--version-code', type=int, default=1)
    b.add_argument('--version-name', default='0.1.1')
    b.add_argument('--out', required=True)
    b.add_argument('--abi', default=None)
    b.add_argument('--keystore', default=None)
    f = sub.add_parser('fetch')
    f.add_argument('path')
    f.add_argument('sha')
    a = ap.parse_args()
    {'lock': cmd_lock, 'build': cmd_build, 'fetch': cmd_fetch}[a.cmd](a)


if __name__ == '__main__':
    main()

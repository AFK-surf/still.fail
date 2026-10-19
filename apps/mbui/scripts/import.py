#!/usr/bin/env python3
"""still.fail's parts of mbui, imported again from a commit of mbui that still has them (the move out of mbui's own
repository: until it is cut there, what lands on mbui's main is taken here again).

    python3 apps/mbui/scripts/import.py [REF]     REF: an mbui commit or branch (default main), as GitHub has it

What is still.fail's (PATHS) is replaced by that commit's, then made this module's (moon.pkg's imports of the moved
packages from stillfail/, the demo's kit and glass screens as src/sfkit, the paths a workspace builds to); what is
only here (the scripts that run mbui's, the Android project, src/sfkit's main, the forwarding headers) is left alone.
It changes the working tree only: look at `git diff` before committing. mbui.rev (the framework this builds with) is
not touched: scripts/mbui.sh bump moves it.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'https://github.com/zzj3720/mbui.git'
CACHE = os.environ.get('STILLFAIL_MBUI_CACHE') or os.path.join(
    os.path.expanduser('~/Library/Caches') if sys.platform == 'darwin'
    else os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')), 'stillfail-mbui')

# mbui's paths that are still.fail's (directories whole), and its goldens of still.fail's screens
PATHS = [
    'src/core', 'src/sf', 'src/sfapp', 'src/sfcore', 'src/sffix', 'src/stillfail', 'src/coredemo', 'src/gallery',
    'src/shelf', 'src/videos', 'src/photos', 'src/books', 'src/player',
    'src/host/apple_core.m', 'src/host/android_core.c', 'src/host/core_api.h', 'src/host/apple_auth.m',
    'android/app/src/main/java/dev/mbui/CoreHost.java',
    'core', 'e2e', 'docs/stillfail-port.md', 'docs/stillfail-android-map.md', 'docs/stillfail-motion.md',
    'scripts/core.sh', 'scripts/e2e-local.sh', 'scripts/icons.py', 'scripts/drawables.py', 'scripts/motion',
    'scripts/record.sh', 'scripts/motionplot.py', 'scripts/android-core.sh',
]
GOLDENS = re.compile(r'^goldens/(mac|web)-.*\.png$')
# the packages that moved (moon.pkg imports them from this module, stillfail/…)
MOVED = ['core', 'sf', 'sfapp', 'sfapp/settings', 'sfcore', 'sffix', 'stillfail', 'coredemo', 'gallery', 'shelf',
         'videos', 'photos', 'books', 'player', 'sfkit']
# a workspace builds a package under its module's name: _build/<target>/<mode>/build/stillfail/<pkg>
BUILT = re.compile(r'(_build/(?:native|js)/(?:release|debug|\$MODE)/build/)')


def git(*args, **kw):
    return subprocess.run(['git', '--git-dir', os.path.join(CACHE, 'repo.git'), *args], check=True,
                          stdout=subprocess.PIPE, **kw).stdout


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else 'main'
    bare = os.path.join(CACHE, 'repo.git')
    if not os.path.isdir(bare):
        os.makedirs(CACHE, exist_ok=True)
        subprocess.run(['git', 'clone', '-q', '--bare', '--filter=blob:none', REPO, bare], check=True)
    git('fetch', '-q', '--filter=blob:none', 'origin', f'+refs/heads/*:refs/heads/*')
    rev = git('rev-parse', f'{ref}^{{commit}}').decode().strip()
    files = git('ls-tree', '-r', '--name-only', rev).decode().split('\n')
    tmp = tempfile.mkdtemp()
    try:
        take = [p for p in PATHS if any(f == p or f.startswith(p + '/') for f in files)]
        goldens = [f for f in files if GOLDENS.match(f)]
        extra = [f for f in ('src/demo/kit.mbt', 'src/demo/glass.mbt', 'scripts/shots.sh') if f in files]
        if 'src/sfapp' not in take:
            sys.exit(f'import: {ref} ({rev[:9]}) has no src/sfapp: it is after the cut, nothing of still.fail\'s to take')
        archive = subprocess.run(['git', '--git-dir', bare, 'archive', rev, *take, *goldens, *extra],
                                 check=True, stdout=subprocess.PIPE).stdout
        subprocess.run(['tar', '-x', '-C', tmp], input=archive, check=True)
        for p in take:
            dst = os.path.join(A, p)
            if os.path.isdir(dst):
                shutil.rmtree(dst)
            elif os.path.exists(dst):
                os.remove(dst)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(os.path.join(tmp, p), dst)
        gold = os.path.join(A, 'goldens')
        for f in os.listdir(gold) if os.path.isdir(gold) else []:
            if GOLDENS.match('goldens/' + f):
                os.remove(os.path.join(gold, f))
        for f in goldens:
            os.makedirs(os.path.dirname(os.path.join(A, f)), exist_ok=True)
            shutil.move(os.path.join(tmp, f), os.path.join(A, f))
        # the demo's kit and glass screens: src/sfkit's (its main.mbt and moon.pkg are this module's own)
        for f in ('kit.mbt', 'glass.mbt'):
            if os.path.isfile(os.path.join(tmp, 'src/demo', f)):
                shutil.copy(os.path.join(tmp, 'src/demo', f), os.path.join(A, 'src/sfkit', f))
        # moon.pkg: the moved packages from this module
        for root, _, names in os.walk(os.path.join(A, 'src')):
            if 'moon.pkg' in names:
                p = os.path.join(root, 'moon.pkg')
                s = open(p, encoding='utf-8').read()
                n = re.sub(r'"mbui/([a-z/]+)"', lambda m: f'"stillfail/{m.group(1)}"' if m.group(1) in MOVED else m.group(0), s)
                if n != s:
                    open(p, 'w', encoding='utf-8').write(n)
        # the scripts and flows: what a workspace builds where; the debug app's package
        for p in ('scripts/core.sh', 'scripts/record.sh', 'e2e/run.sh', 'e2e/android-flow.sh'):
            p = os.path.join(A, p)
            if not os.path.isfile(p):
                continue
            s = open(p, encoding='utf-8').read()
            n = BUILT.sub(r'\1stillfail/', s)
            # mbui's own test files, in its checkout
            n = re.sub(r'(?<![/$\w])test/(images|apple_views)\b', r'$MBUI_DIR/test/\1', n)
            n = n.replace('E2E_PKG:-dev.mbui.demo', 'E2E_PKG:-fail.still.mbui.debug').replace('PKG=dev.mbui.demo', 'PKG=${E2E_PKG:-fail.still.mbui.debug}')
            if n != s:
                open(p, 'w', encoding='utf-8').write(n)
        # the screenshots of still.fail's screens: mbui's scripts/shots.sh, theirs only (scripts/shots.py's way)
        if os.path.isfile(os.path.join(tmp, 'scripts/shots.sh')):
            subprocess.run([sys.executable, os.path.join(A, 'scripts/shots.py'), os.path.join(tmp, 'scripts/shots.sh'),
                            os.path.join(A, 'scripts/shots.sh')], check=True)
        print(f'imported still.fail\'s parts of mbui {rev[:9]} ({ref}): {len(take)} paths, {len(goldens)} goldens; '
              'see git diff')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()

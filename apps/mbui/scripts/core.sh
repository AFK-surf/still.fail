#!/bin/bash
# The still.fail client core (client/core-ts of this repository) in Hermes on its Rust shell (client/shell), for the
# Apple apps (src/host/apple_core.mm) and Android's (src/host/android_core.c on still.fail's prebuilt engine): builds the
# pieces from the checkout and runs a headless smoke test..
#   scripts/core.sh deps | shell [TARGET] | hermes [apple] | hermes-kept [apple] | hermes-script FILE [OUT] | hermes-apple | engine [TARGET] | apple [TARGET]
#                   | smoke [build|run] | listen | exit | fairness | sealed | collate | login-test | vectors | sizes | clean | all
#                   | chat-open | ws-switch | md-parse | mermaid | mermaid-lib | mermaid-smoke | zstd-read
# SF_SRC: the still.fail checkout (default: this one, scripts/env.sh); out/core/ gets everything built.
# TARGET: a Rust target (default aarch64-apple-darwin; aarch64-apple-ios, aarch64-apple-ios-sim for iOS).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
ROOT=$PWD
OUT=$ROOT/out/core
# (Git Bash on Windows: paths as D:/…, which both its shell and Windows' programs take)
if [ "${OSTYPE:-}" = msys ] || [ "${OSTYPE:-}" = cygwin ]; then
  ROOT=$(cygpath -m "$ROOT")
  SF_SRC=$(cygpath -m "$SF_SRC")
fi
CORE_TS=$SF_SRC/client/core-ts
# The shell's intermediate build lives outside the checkout (and outside this repo): only the .a is kept in out/core.
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$(cd "$TOOLS/.." && pwd)/core-target}
export CARGO_TARGET_DIR
# rustup's cargo (it has the iOS/Android targets), before Homebrew's.
[ -x "$HOME/.cargo/bin/cargo" ] && export PATH=$HOME/.cargo/bin:$PATH
mkdir -p $OUT

# (Windows' Python is `python`)
PY=$(command -v python3 || command -v python)
now() { "$PY" -c 'import time;print(time.time())'; }
since() { "$PY" -c "print(round($(now)-$1,2))"; }

deps() {
  [ -d "$CORE_TS" ] || { echo "no still.fail checkout at $SF_SRC (SF_SRC=...)"; exit 1; }
  (cd $CORE_TS && pnpm install --frozen-lockfile --prefer-offline 2>&1 | tail -5)
}

# deps, when this checkout has not had them (a fresh worktree: esbuild and Babel missing from core-ts's node_modules)
have_deps() {
  [ -x $CORE_TS/node_modules/.bin/esbuild ] && [ -d $CORE_TS/node_modules/@babel/core ] || deps
}

# libstillfail_shell.a for TARGET: the crate is a cdylib + lib; `cargo rustc --crate-type staticlib` makes the
# archive without touching still.fail's Cargo.toml. What it needs from the system goes to out/core/shell-<target>.libs.
shell() {
  local target=${1:-aarch64-apple-darwin}
  local t0=$(now)
  (cd $SF_SRC/client/shell && cargo rustc --release --lib --crate-type staticlib --target $target \
      -- --print native-static-libs 2> >(tee $OUT/shell-$target.log >&2))
  # (rustc prints it only when it builds: a fresh build keeps the last one)
  local libs=$(grep -o 'native-static-libs: .*' $OUT/shell-$target.log | tail -1 | sed 's/native-static-libs: //')
  [ -n "$libs" ] && echo "$libs" > $OUT/shell-$target.libs
  mkdir -p $OUT/$target
  cp $CARGO_TARGET_DIR/$target/release/libstillfail_shell.a $OUT/$target/
  echo "shell $target in $(since $t0) s: $(stat -f %z $OUT/$target/libstillfail_shell.a) bytes; links: $(libs $target)"
}

# The shell for TARGET as still.fail's natives have it for the shell's sources now (scripts/native.ts shell-apple, by
# its key: built once on a Mac by CI's natives job, for macOS 11.0 and iOS 17.0; else as said by native.ts: built
# there), copied only when it differs (an unchanged one keeps its mtime). Fails where native.ts cannot say (no node, a
# checkout that is not git's).
shell_prebuilt() {
  local t dir
  case $1 in
    aarch64-apple-darwin) t=darwin-arm64 ;;
    aarch64-apple-ios) t=ios-arm64 ;;
    aarch64-apple-ios-sim) t=ios-sim-arm64 ;;
    *) return 1 ;;
  esac
  dir=$(node "$SF_SRC/scripts/native.ts" path shell-apple $t) || return 1
  mkdir -p $OUT/$1
  cmp -s "$dir/libstillfail_shell.a" $OUT/$1/libstillfail_shell.a || cp "$dir/libstillfail_shell.a" $OUT/$1/ || return 1
  cmp -s "$dir/libstillfail_shell.libs" $OUT/shell-$1.libs || cp "$dir/libstillfail_shell.libs" $OUT/shell-$1.libs || return 1
  echo "shell $1: still.fail's natives, shell-apple $t ($dir)"
}

# The core for Hermes (every native host: src/host/apple_core.mm, src/host/android_core.c): out/core/core.hbc. Made as still.fail's
# client/core-ts/scripts/hermes-bundle.ts makes it (esbuild to ES2020, async functions as generators; Babel's class
# transform, as Hermes 0.81 has no classes nor async functions; then React Native 0.81.4's hermesc, the engine's Hermes, to bytecode), but from an entry of ours (ENTRY,
# default core/hermes.ts: still.fail's), `@core/` and `@stillfail/`
# aliased (`@core/` is client/core-ts/src, `@stillfail/` this checkout). hermesc: $HERMESC, else the one kept in ~/Library/Caches/stillfail-build, else
# fetched (npm pack react-native@0.81.4) into out/core/hermesc.
HERMES_RN=0.81.4
hermesc() {
  if [ -n "${HERMESC:-}" ]; then echo "$HERMESC"; return; fi
  local bin=sdks/hermesc/$([ "$(uname)" = Darwin ] && echo osx-bin || echo linux64-bin)/hermesc
  for c in "$HOME/Library/Caches/stillfail-build/hermesc-$HERMES_RN/package" "$OUT/hermesc/package"; do
    if [ -x "$c/$bin" ]; then echo "$c/$bin"; return; fi
  done
  mkdir -p $OUT/hermesc
  (cd $OUT/hermesc && npm pack react-native@$HERMES_RN --silent > /dev/null \
    && tar -xzf react-native-$HERMES_RN.tgz package/sdks/hermesc && rm react-native-$HERMES_RN.tgz)
  echo "$OUT/hermesc/package/$bin"
}

# core.hbc's stamp: its source checkout, the bundle's inputs (esbuild's metafile), the entry and hermesc.
# A shared build directory may be used by several checkouts: the old metafile still points into the first one.
hbc_stamp() {
  "$PY" - "$OUT/core-hermes.meta.json" "${ENTRY:-$ROOT/core/hermes.ts}" "$1" "$SF_SRC" <<'PY'
import json, os, sys
meta, entry, hermesc, checkout = sys.argv[1:5]
try:
    inputs = sorted(json.load(open(meta))['inputs'])
except (OSError, ValueError, KeyError):
    sys.exit(1)
def st(p):
    try:
        s = os.stat(p)
        return [s.st_mtime_ns, s.st_size]
    except OSError:
        return None
print(json.dumps({'checkout': os.path.realpath(checkout), 'entry': entry, 'hermesc': [hermesc, st(hermesc)], 'inputs': {p: st(p) for p in inputs}}))
PY
}

# HBC_CACHE (a directory: CI's, kept in the Actions cache by every job that makes the core): core.hbc kept there by
# what it is made of, by content, and taken from there when that is the same. A checkout's mtimes are all new, so the
# stamp above never holds on CI: each job made the core again, ~14 s of a CPU (Windows' 13.9 s beside cl compiling the
# app, 2026-10-24, 40064767331). What it is made of: HBC_TREES of the checkout as committed, with the config files of
# the directories above them (hbc_paths), none of them changed in it (else no key: made, not kept, and why said); this
# module's core/ and the tsconfig.json and package.json over it; this script; the entry; hermesc itself (the bytecode
# is its Hermes's: Windows' is the engine's own).
SHA=$(command -v sha256sum > /dev/null && echo sha256sum || echo "shasum -a 256")
# (as bash's paths: Windows' runner says D:\a\..., and a glob over it, the newest 8's keep below, matched nothing, so
# none went: the Windows job's HBC_CACHE grew to 566 MB, its restore 40 s, 2026-10-30)
[ -z "${HBC_CACHE:-}" ] || ! command -v cygpath > /dev/null || HBC_CACHE=$(cygpath -u "$HBC_CACHE")
# What of the checkout the bundle takes, said here alone: the core with its lockfile (its packages), the words' catalog
# and the brand, the lock's and the vaults' rules, the releases' keys, the build that takes a moved workspace, the
# buddies asks.ts imports. The key is of these, and `hermes` refuses a bundle that takes a file git tracks from
# anywhere else (hbc_inputs), so none is left out of it: the key named client/core-ts, media and the avatars alone
# until 2026-11-14, and a change to the rules or the words alone found the core.hbc of before under the same key.
# The last four are what esbuild makes those by and its metafile never lists: the tsconfig.json (else jsconfig.json,
# with what it `extends`) and the package.json nearest over each file it bundles (the nearest alone, of each: esbuild
# 0.28.2, tried). The root's are over the rules, the brand and this module's core/, the station's over its two. A
# tsconfig's `strict` over the entry is the whole bundle's "use strict", its `verbatimModuleSyntax` an unused import
# kept; a package.json's `type`, `sideEffects` and `imports` are what an import means. The four are named to say
# which there are today; the key has them named or not, as it has such a file in every directory over a path named
# here (hbc_paths, below), so a file the bundle takes is all this line is ever given: the config over it is in the key
# with it, one added later too. The one config to name by hand is what a tsconfig.json `extends` from outside these,
# which hbc_inputs refuses the bundle for until it is named.
# The config files are in the key and, on purpose, in none of the lists of what starts a release or a preview
# (scripts/plan.sh's beta apps, beta.sh APP_SRC, preview.yml's paths), which name the files above them alone: the key
# is what keeps a wrong core.hbc from being taken, and a miss costs seconds; the lists say which pushes release the
# apps, and the four change about twice a day (station/package.json's packages, 2026-11) without changing the core.
# One that does change it ships with the next release, its core made anew because the key changed. Do not make the
# two agree: a file the bundle takes goes in both, a config file here alone (decided in #6106, 2026-11-14).
HBC_TREES="client/core-ts client/i18n rules/js station/src/updates/keys.ts station/src/api/moved-from.ts web/public/avatars/index.json package.json tsconfig.json station/package.json station/tsconfig.json"
# What the key is of in the checkout: HBC_TREES and, for each of them and for this module's core/ where it lies in the
# checkout, the package.json, tsconfig.json and jsconfig.json of every directory above it, up to the checkout's own:
# every place the config esbuild makes a file of theirs by can be, now or after a later commit. Worked out of
# HBC_TREES, never written: most are not there (today the four it names and web/tsconfig.json are), one that is not
# says nothing to `git ls-tree`, and the commit that adds it is a new key. As #6106 merged (2026-11-14) the key was of
# HBC_TREES alone: a config added between one of them and the root (client/tsconfig.json, web/package.json) left it as
# it was, so the core.hbc made without it went on being taken, and the next commit to change the key, whatever it was
# of, had its bundle refused for it. Each once, in one order on every machine (C's).
hbc_paths() {
  local p n own=
  case $ROOT/core in "$SF_SRC"/*) own=${ROOT#"$SF_SRC"/}/core ;; esac
  { for p in $HBC_TREES; do echo "$p"; done
    for p in $HBC_TREES $own; do
      while [ -n "$p" ]; do
        case $p in */*) p=${p%/*} ;; *) p= ;; esac
        for n in package.json tsconfig.json jsconfig.json; do echo "${p:+$p/}$n"; done
      done
    done; } | LC_ALL=C sort -u
}
# The same two over DIR, wherever it lies: this module's core/ is the checkout's own or a copy with no repository over
# it (beta.sh's WORK), and the entry is made strict by the root's tsconfig.json in the one and by none in the other,
# so the key has them by content (nothing where there is none).
hbc_over() {
  local d=$1 up ts= pkg=
  while [ -z "$ts" ] || [ -z "$pkg" ]; do
    if [ -n "$ts" ]; then :; elif [ -f "$d/tsconfig.json" ]; then ts=$d/tsconfig.json; elif [ -f "$d/jsconfig.json" ]; then ts=$d/jsconfig.json; fi
    [ -n "$pkg" ] || [ ! -f "$d/package.json" ] || pkg=$d/package.json
    up=$(dirname "$d")
    if [ "$up" = "$d" ] || [ "$up" = . ]; then break; fi
    d=$up
  done
  [ -z "$ts" ] || echo "$ts"
  [ -z "$pkg" ] || echo "$pkg"
}
# No key where one was asked for (HBC_CACHE set) says why, in a line: a week of no key at all (2026-11-07 to 11-14,
# `media` gone) was seen by nobody, each job making the core again without a word.
hbc_no_key() {
  echo "core.hbc has no key, so HBC_CACHE is not used (the core is made here, and not kept): $1" >&2
}
# The PostHog project this build's core sends what people use to (client/core-ts/src/use-counts.ts, its
# `__STILLFAIL_POSTHOG__`): {host, key} of the file STILLFAIL_POSTHOG names, as the hosts' own reports take it (a
# release's, from POSTHOG_JSON); none, `undefined`, and the core sends nothing. Part of core.hbc's key and stamp.
posthog_define() {
  if [ -n "${STILLFAIL_POSTHOG:-}" ] && [ -f "$STILLFAIL_POSTHOG" ]; then
    node -e 'const { host, key } = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.stdout.write(JSON.stringify({ host, key }))' "$STILLFAIL_POSTHOG"
  else
    echo undefined
  fi
}
hbc_key() {
  [ -n "${HBC_CACHE:-}" ] || return 1
  local trees changed paths
  paths=$(hbc_paths)
  # (a path that is not there says nothing, as the bundle takes nothing from it: `rev-parse HEAD:media` failed once
  # media was gone, 2026-11-07, so there was no key and nothing was kept; none of them there is no checkout of ours)
  trees=$(git -C "$SF_SRC" ls-tree HEAD -- $paths 2> /dev/null) \
    || { hbc_no_key "\`git ls-tree HEAD\` failed in $SF_SRC: $(git -C "$SF_SRC" ls-tree HEAD -- $paths 2>&1 > /dev/null | head -1)"; return 1; }
  [ -n "$trees" ] || { hbc_no_key "git has none of HBC_TREES at HEAD in $SF_SRC"; return 1; }
  # (a status that fails is not a clean tree)
  changed=$(git -C "$SF_SRC" status --porcelain -uno -- $paths 2> /dev/null) \
    || { hbc_no_key "\`git status\` failed in $SF_SRC: $(git -C "$SF_SRC" status --porcelain -uno -- $paths 2>&1 > /dev/null | head -1)"; return 1; }
  [ -z "$changed" ] || { hbc_no_key "$(echo "$changed" | head -1 | cut -c4-) is changed in $SF_SRC and not committed$(echo "$changed" | awk 'END { if (NR > 1) print " (and " NR - 1 " more of what the key is of)" }')"; return 1; }
  { echo "$trees"
    (cd "$ROOT/core" && find . -type f | LC_ALL=C sort | xargs $SHA)
    hbc_over "$ROOT/core" | while IFS= read -r f; do echo "${f##*/}"; $SHA < "$f"; done
    $SHA < "$D/core.sh"
    echo "${ENTRY#"$ROOT"/}"
    echo "posthog $(posthog_define | $SHA)"
    $SHA < "$1"; } | $SHA | cut -c1-24
}

# The bundle just made (esbuild's metafile) held to what the key covers, which is hbc_paths as committed, this
# module's core/ and the core's packages (its lockfile): a file git tracks elsewhere is refused, saying the line to
# change; and with a key ($1), a file git does not track is too (one a build made, an entry of one's own: the key says
# nothing of what is in it). So is what esbuild makes each file by and lists nowhere (HBC_TREES says which): the
# nearest config over a file HBC_TREES has is in hbc_paths wherever it is, so what is left to refuse of those is what
# a tsconfig.json extends from elsewhere, and the config over a file that is itself refused. It never
# passes having held nothing: the entry is among the files it found, and every input the metafile says is a file here
# (a metafile read from another place, or a path in a form this does not know, was nothing checked and no refusal).
hbc_inputs() {
  HBC_OVER=$(hbc_over "$ROOT/core") "$PY" - "$OUT/core-hermes.meta.json" "$ROOT" "$SF_SRC" "$1" "$ENTRY" $(hbc_paths) <<'PY'
import json, os, re, subprocess, sys
meta, root, checkout, key, entry = sys.argv[1:6]
trees = sys.argv[6:]
root, checkout = os.path.realpath(root), os.path.realpath(checkout)
def within(p, d):
    return p == d or p.startswith(d + os.sep)
def said(p):
    return os.path.relpath(p, checkout).replace(os.sep, '/') if within(p, checkout) else p
own = os.path.join(root, 'core')
packages = os.path.join(checkout, 'client', 'core-ts', 'node_modules')
keyed = [os.path.join(checkout, *t.split('/')) for t in trees]
# (esbuild says them from where it ran, this module; what it left out of a package is no file, nor what a --define of
# an object makes, `<define:NAME>`: its value is the key's and stamp's already, as hermes says it: posthog)
files, lost = [], []
for i in sorted(json.load(open(meta))['inputs']):
    p = os.path.realpath(os.path.join(root, i))
    if os.path.isfile(p):
        files.append(p)
    elif re.fullmatch(r'<define:[A-Za-z0-9_$.]+>', i):
        continue
    elif 'node_modules' not in re.split(r'[\\/]', i):
        lost.append(i)
unheld = ", so the bundle cannot be held to core.hbc's key (hbc_inputs in apps/mbui/scripts/core.sh: where it reads the metafile's paths from)"
if lost:
    sys.exit('hermes: ' + meta + ' says the bundle takes ' + lost[0] + (' and %d more' % (len(lost) - 1) if len(lost) > 1 else '')
             + ', no file from ' + root + unheld)
start = os.path.normcase(os.path.realpath(os.path.join(root, entry)))
if not any(os.path.normcase(p) == start for p in files):
    sys.exit('hermes: ' + meta + ' says the bundle takes %d files, none of them its entry, ' % len(files) + entry + unheld)
# What esbuild makes each by: the package.json nearest over it and, but for a .json, the tsconfig.json (else
# jsconfig.json) with what that extends. A package's file is made by its package's own (the lockfile's).
def nearest(d, names, seen={}):
    if (d, names) not in seen:
        here = [os.path.join(d, n) for n in names if os.path.isfile(os.path.join(d, n))]
        seen[d, names] = here[0] if here else nearest(os.path.dirname(d), names) if os.path.dirname(d) != d else None
    return seen[d, names]
def extended(ts):
    if os.path.basename(ts) == 'package.json':
        return []
    # (a tsconfig's JSON: comments, a comma before a closing bracket)
    text = re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/', lambda m: m.group(1) or '', open(ts, encoding='utf-8-sig').read(), flags=re.S)
    text = re.sub(r'("(?:\\.|[^"\\])*")|,(?=\s*[}\]])', lambda m: m.group(1) or '', text)
    try:
        more = json.loads(text).get('extends') or []
    except (ValueError, AttributeError):
        sys.exit('hermes: ' + said(ts) + " is over files of the bundle and is not read as a tsconfig's JSON, so what it extends cannot be held to core.hbc's key: mend it")
    out = []
    for e in [more] if isinstance(more, str) else more:
        there = [f for f in (os.path.join(os.path.dirname(ts), e), os.path.join(os.path.dirname(ts), e + '.json')) if os.path.isfile(f)]
        if not e.startswith('.') and not os.path.isabs(e) or not there:
            sys.exit('hermes: ' + said(ts) + ' is over files of the bundle and extends ' + e + ", no file by its path, which core.hbc's key cannot be held to: name a file there is, by ./ or ../")
        out.append(os.path.realpath(there[0]))
    return out
# (those over this module's core/ are in the key by content, hbc_over's: not what they extend; `by` the first file
# found under each, `via` the config that extends it where it was come to that way)
by, via, in_key = {}, {}, set(os.path.realpath(c) for c in os.environ.get('HBC_OVER', '').split('\n') if c)
for p in files:
    if within(p, packages):
        continue
    made_by = [nearest(os.path.dirname(p), ('package.json',))]
    if not p.endswith('.json'):
        made_by.append(nearest(os.path.dirname(p), ('tsconfig.json', 'jsconfig.json')))
    for c in [os.path.realpath(c) for c in made_by if c]:
        todo = [(e, c) for e in extended(c)] if within(p, own) and c in in_key else [(c, None)]
        while todo:
            c, e = todo.pop()
            if c not in by:
                by[c], via[c] = p, e
                todo += [(x, c) for x in extended(c)]
taken = [p for p in files if not within(p, own) and not within(p, packages)]
taken += sorted(c for c in by if c not in taken and not within(c, own) and not within(c, packages))
elsewhere = set(p for p in taken if not any(within(p, t) for t in keyed))
listed = subprocess.run(['git', '--literal-pathspecs', '-C', checkout, 'ls-files', '-z', '--'] + trees
                        + [said(p) for p in taken if p in elsewhere and within(p, checkout)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
if listed.returncode != 0:
    # (no checkout of git's: no key either)
    sys.exit('hermes: a key for core.hbc, but git lists no files in ' + checkout if key else 0)
tracked = set(listed.stdout.decode().split('\0'))
wrong = 0
for p in taken:
    what = 'takes ' + said(p) if p in files else ('is made by ' + said(p) + ' (' + (said(via[p]) + ' extends it, ' if via[p] else '')
                                                  + 'esbuild applies it to ' + said(by[p]) + ', and its metafile does not list it)')
    # (the nearest config over a file: the key has it once it has the file, hbc_paths; one come to by `extends` is named)
    mend = ('add it' + (' (or its directory)' if p in files else '') + ' to HBC_TREES in apps/mbui/scripts/core.sh'
            if p in files or via[p] or by[p] not in elsewhere
            else 'it does once ' + said(by[p]) + ' (or its directory) is in HBC_TREES in apps/mbui/scripts/core.sh, with nothing added for it')
    if p in elsewhere and said(p) in tracked:
        print('hermes: the bundle ' + what + ", which core.hbc's key does not cover: " + mend)
    elif key and said(p) not in tracked:
        print('hermes: the bundle ' + what + ", which git does not track here: core.hbc's key is of what is committed and says nothing of it (commit it, or make the core without HBC_CACHE)")
    else:
        continue
    wrong = 1
sys.exit(wrong)
PY
}

# Whether `hermes` (with apple: as `apple` makes it, its entry) would take core.hbc from HBC_CACHE, its key said:
# CI asks before it fetches the packages (pnpm's store, core-ts's node_modules), which only a core made here needs
# (deps: done by `hermes` itself then). Fetches hermesc when there is none, as `hermes` would.
hermes_kept() {
  local key
  [ "${1:-}" != apple ] || ENTRY=${ENTRY:-$APPLE_ENTRY}
  ENTRY=${ENTRY:-$ROOT/core/hermes.ts}
  [ -n "${HBC_CACHE:-}" ] && key=$(hbc_key "$(hermesc)") && [ -f "$HBC_CACHE/$key.hbc" ] || { echo "hermes-kept: no core.hbc in HBC_CACHE for ${ENTRY#"$ROOT"/}${key:+ ($key)}"; return 1; }
  echo "hermes-kept: core.hbc for ${ENTRY#"$ROOT"/} kept as $key (HBC_CACHE)"
}

hermes() {
  local t0=$(now)
  local hc="$(hermesc)" key= stamp=
  ENTRY=${ENTRY:-$ROOT/core/hermes.ts}
  if key=$(hbc_key "$hc") && [ -f "$HBC_CACHE/$key.hbc" ]; then
    cp -p "$HBC_CACHE/$key.hbc" $OUT/core.hbc && rm -f $OUT/core.hbc.stamp
    echo "hermes: core.hbc kept as $key (HBC_CACHE), $(wc -c < $OUT/core.hbc | tr -d ' ') bytes"
    return 0
  fi
  have_deps
  # With a clean Git tree the content key decides reuse; a missing key cannot fall back to an older timestamp stamp.
  # Without a content key, use the last build only when its checkout and inputs still match.
  local posthog
  posthog=$(posthog_define) || { echo "hermes: STILLFAIL_POSTHOG ($STILLFAIL_POSTHOG) is no {host, key}"; return 1; }
  if [ -z "$key" ] && [ -f $OUT/core.hbc ] && [ -f $OUT/core.hbc.stamp ] && [ "$(hbc_stamp "$hc" 2>/dev/null) posthog $(echo "$posthog" | $SHA)" = "$(cat $OUT/core.hbc.stamp)" ]; then
    echo "hermes: core.hbc as it was (its inputs unchanged)"
    return 0
  fi
  # never an old core.hbc after a failed step (it would hide a module gone missing)
  rm -f $OUT/core-hermes.js $OUT/core.hbc $OUT/core.hbc.stamp
  # what an app's modules import from npm found in the core's own node_modules
  NODE_PATH=$CORE_TS/node_modules $CORE_TS/node_modules/.bin/esbuild ${ENTRY:-$ROOT/core/hermes.ts} --bundle \
    --format=iife --platform=neutral --main-fields=module,main --conditions=hermes --target=es2020 --supported:async-await=false --supported:async-generator=false --minify --legal-comments=none \
    --alias:@core=$CORE_TS/src --alias:@stillfail=$SF_SRC --resolve-extensions=.ts,.js,.mjs \
    "--define:__STILLFAIL_POSTHOG__=$posthog" \
    --outfile=$OUT/core-hermes.js --metafile=$OUT/core-hermes.meta.json --log-level=warning \
    || { echo "hermes: bundle failed"; return 1; }
  hbc_inputs "$key" || { rm -f $OUT/core-hermes.js; return 1; }
  # Classes as functions (and `extends Error` as Babel's wrapped native super), with still.fail's Babel.
  (cd $CORE_TS && node --input-type=module -e "
import { readFileSync, writeFileSync } from 'node:fs';
import { transformSync } from '@babel/core';
const f = process.argv[1];
const out = transformSync(readFileSync(f, 'utf8'), { babelrc: false, configFile: false, compact: true, plugins: ['@babel/plugin-transform-classes'] });
if (!out || !out.code) throw new Error('babel made nothing');
writeFileSync(f, out.code);" $OUT/core-hermes.js) || { echo "hermes: class transform failed"; return 1; }
  "$hc" -emit-binary -O -block-scoping -out $OUT/core.hbc $OUT/core-hermes.js \
    || { echo "hermes: hermesc failed"; rm -f $OUT/core.hbc; return 1; }
  { stamp=$(hbc_stamp "$hc") && echo "$stamp posthog $(echo "$posthog" | $SHA)" > $OUT/core.hbc.stamp; } || rm -f $OUT/core.hbc.stamp
  echo "hermes in $(since $t0) s: $(wc -c < $OUT/core-hermes.js | tr -d ' ') bytes of script, $(wc -c < $OUT/core.hbc | tr -d ' ') of bytecode${key:+ (kept as $key)}"
  if [ -n "$key" ]; then
    mkdir -p "$HBC_CACHE" && cp -p $OUT/core.hbc "$HBC_CACHE/$key.hbc.tmp" && mv "$HBC_CACHE/$key.hbc.tmp" "$HBC_CACHE/$key.hbc"
    ls -t "$HBC_CACHE"/*.hbc | tail -n +9 | xargs rm -f  # the newest 8
  fi
}

# A plain script (no bundle, no Babel) as bytecode, OUT (default out/core/core.hbc, the core's place: Android's
# listen-test; the stamp goes with it, so the next `hermes` makes the core again).
hermes_script() {
  local out=${2:-$OUT/core.hbc}
  rm -f "$out"
  [ "$out" = $OUT/core.hbc ] && rm -f $OUT/core.hbc.stamp
  "$(hermesc)" -emit-binary -O -out "$out" "$1" || { echo "hermes-script: hermesc failed"; return 1; }
  echo "hermes-script: $1 as $(wc -c < "$out" | tr -d ' ') bytes of bytecode"
}

# React Native 0.81.4's Hermes for Apple's systems, the one Android's hermes-android is (the same release's Maven
# tarball, `react-native-artifacts:hermes-ios-release`; MIT): macOS's hermes.framework (Library/Frameworks/macosx), iOS's
# hermes.xcframework (Library/Frameworks/universal: the device's and the simulator's slices), the headers of Hermes and
# its JSI (include). Fetched once into a cache every worktree shares (beside hermesc's:
# ~/Library/Caches/stillfail-build/hermes-apple-<version>), its sha256 checked; never committed. out/core/hermes links
# to its destroot.
HERMES_APPLE_URL=https://repo1.maven.org/maven2/com/facebook/react/react-native-artifacts/$HERMES_RN/react-native-artifacts-$HERMES_RN-hermes-ios-release.tar.gz
HERMES_APPLE_SHA256=0a9ada4198ed5bbd4a8099197cd100397d65cc86cd44c8eba6c162099081e554
hermes_apple() {
  local cache=${STILLFAIL_BUILD_CACHE:-$HOME/Library/Caches/stillfail-build}/hermes-apple-$HERMES_RN
  if [ ! -f $cache/destroot/include/hermes/hermes.h ]; then
    mkdir -p "$(dirname $cache)"
    local tmp=$(mktemp -d "$cache.XXXXXX")
    curl -fsSL --retry 3 -o $tmp/hermes.tgz $HERMES_APPLE_URL || { rm -rf $tmp; echo "hermes-apple: download failed"; return 1; }
    local sum=$(shasum -a 256 $tmp/hermes.tgz | cut -d' ' -f1)
    [ "$sum" = $HERMES_APPLE_SHA256 ] || { rm -rf $tmp; echo "hermes-apple: sha256 $sum, not $HERMES_APPLE_SHA256"; return 1; }
    tar -xzf $tmp/hermes.tgz -C $tmp && rm $tmp/hermes.tgz
    # (another build may have put it there meanwhile: theirs kept)
    if [ -d $cache ]; then rm -rf $tmp; else mv $tmp $cache; fi
    echo "hermes-apple: Hermes $HERMES_RN for macOS and iOS in $cache"
  fi
  [ "$(readlink $OUT/hermes 2>/dev/null)" = $cache/destroot ] || ln -sfn $cache/destroot $OUT/hermes
}

# Where Hermes's framework for TARGET is (the directory holding hermes.framework).
hermes_fw() {
  case ${1:-aarch64-apple-darwin} in
    aarch64-apple-darwin) echo $OUT/hermes/Library/Frameworks/macosx ;;
    aarch64-apple-ios-sim) echo $OUT/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64_x86_64-simulator ;;
    aarch64-apple-ios) echo $OUT/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64 ;;
    *) echo "core.sh: no Hermes for $1" >&2; return 1 ;;
  esac
}

# The core's engine for TARGET: src/host/apple_core.mm (Objective-C++: the core's thread and loop, Hermes and its JSI,
# the shell's C ABI, secure.* and listen.*) as out/core/<target>/libmbui_core.a, which the apps with the core link
# beside the shell's .a and Hermes's framework (src/stillfail/moon.pkg; the iOS build's hook). Made again only when its
# sources (or this script) are newer: 1-2 s in the measured build, not worth a native part of its own as the shell is.
engine() {
  local target=${1:-aarch64-apple-darwin} cc
  hermes_apple || return 1
  case $target in
    aarch64-apple-darwin) cc="xcrun --sdk macosx clang++ -arch arm64" ;;
    aarch64-apple-ios-sim) cc="xcrun --sdk iphonesimulator clang++ -arch arm64 -mios-simulator-version-min=17.0" ;;
    aarch64-apple-ios) cc="xcrun --sdk iphoneos clang++ -arch arm64 -miphoneos-version-min=17.0" ;;
    *) echo "engine: no target $target"; return 1 ;;
  esac
  local lib=$OUT/$target/libmbui_core.a
  if [ -f $lib ] && [ $lib -nt src/host/apple_core.mm ] && [ $lib -nt engine/ready_queue.h ] && [ $lib -nt src/host/apple_collate.h ] && [ $lib -nt src/host/electron_sealed.h ] && [ $lib -nt src/host/core_api.h ] && [ $lib -nt src/host/listen_api.h ] && [ $lib -nt "$D/core.sh" ]; then
    return 0
  fi
  mkdir -p $OUT/$target
  $cc -std=c++20 -fobjc-arc -fexceptions -frtti -O2 -Wall -Isrc/host -I$OUT/hermes/include \
    -c src/host/apple_core.mm -o $OUT/$target/apple_core.o || { echo "engine: $target did not compile"; return 1; }
  rm -f $lib && ar rcs $lib $OUT/$target/apple_core.o
  echo "engine $target: $lib ($(wc -c < $lib | tr -d ' ') bytes)"
}

# What an Apple app with the core needs for TARGET: Hermes, the engine (when stale), the shell's .a (still.fail's natives
# by its key; where native.ts cannot say, the one here, else built by cargo: rebuild it with `shell`), the core's
# bytecode (ENTRY, by default still.fail's own, as Android's). apple-native is what the app's link takes (all
# but the bytecode, which only its bundle carries: scripts/mac.sh makes that beside the app's compile, `hermes apple`).
APPLE_ENTRY=$ROOT/core/hermes.ts
apple_native() {
  local target=${1:-aarch64-apple-darwin}
  engine $target || return 1
  shell_prebuilt $target || [ -f $OUT/$target/libstillfail_shell.a ] || shell $target
}
apple() {
  apple_native "${1:-}" || return 1
  ENTRY=${ENTRY:-$APPLE_ENTRY} hermes
}

# The shell's link line for TARGET, each library once (-framework X, -lY; clang adds -lSystem and -lobjc itself).
libs() {
  python3 -c '
import sys
t = open(sys.argv[1]).read().split(); out = []; i = 0
while i < len(t):
    x = t[i:i + 2] if t[i] == "-framework" else t[i:i + 1]; i += len(x)
    if " ".join(x) not in out and x[0] not in ("-lSystem", "-lobjc"): out.append(" ".join(x))
print(" ".join(out))' $OUT/shell-$1.libs
}

# A command-line program of core/FILE.m with the engine (libmbui_core.a: Hermes on the shell), for macOS: out/core/NAME.
core_program() {
  local target=aarch64-apple-darwin fw=$(hermes_fw aarch64-apple-darwin)
  apple $target || return 1
  clang -fobjc-arc -O2 -Wall -Isrc/host core/$1.m "$MBUI_DIR/src/host/apple_listen.m" $OUT/$target/libmbui_core.a \
    $OUT/$target/libstillfail_shell.a $(libs $target) -F$fw -framework hermes -Wl,-rpath,$fw -lc++ \
    -framework LocalAuthentication -framework Foundation -Wl,-dead_strip -o $OUT/$1
}

# core/smoke.m + the engine, for macOS.
smoke_build() {
  core_program smoke || return 1
  strip -o $OUT/smoke.stripped $OUT/smoke
  echo "smoke: $(stat -f %z $OUT/smoke) bytes, stripped $(stat -f %z $OUT/smoke.stripped)"
}

# Twice on one data directory: a first start (no files yet), then one over what the first left.
# /usr/bin/time -l: the process's peak resident size and footprint. MB_CORE_TRACE=1 shows the shell's operations.
smoke_run() {
  local dir=$(mktemp -d /tmp/mbui-core-smoke.XXXXXX) code=0
  : > $OUT/smoke.log
  for run in first again; do
    echo "== $run run ==" | tee -a $OUT/smoke.log
    MB_CORE_BUNDLE=$OUT/core.hbc /usr/bin/time -l $OUT/smoke "$dir" ${CLOUD:-https://app.still.fail} > $OUT/smoke-$run.log 2>&1 || code=1
    cat $OUT/smoke-$run.log >> $OUT/smoke.log
    grep -v '^ *0  \|messages\|signals\|swaps\|block\|context switches\|page' $OUT/smoke-$run.log
    echo "data dir after it: $(cd "$dir" && find . -type f | sort | tr '\n' ' ')" | tee -a $OUT/smoke.log
  done
  rm -rf "$dir"
  return $code
}

# Chats opened from what the device holds, in Hermes (core/chatopen.m; client/core-ts/bench/chat-open.ts seeds the data):
# from `subscribe` to each chat's first value, the first time, a moment after, after the core let its view go; run twice
# on one data directory, the second as the app started anew.
chat_open() {
  core_program chatopen || return 1
  local dir=$(mktemp -d /tmp/mbui-chat-open.XXXXXX) code=0
  (cd $CORE_TS && node bench/chat-open.ts seed "$dir") || code=1
  for run in first again; do
    [ $code = 0 ] || break
    echo "== $run run =="
    MB_CORE_BUNDLE=$OUT/core.hbc $OUT/chatopen "$dir" || code=1
  done
  rm -rf "$dir"
  return $code
}

# A workspace switched to, in Hermes (core/wsswitch.m; client/core-ts/bench/ws-switch-seed.ts seeds two of real size):
# what the app sends at a switch and when each answer comes, how long the person waits and when the new screen is whole.
# SCREEN=small|wide: 小屏's Home or 大屏's frame; WS2_LANDS=new: 大屏 lands on a new chat in ws2 (else its chat);
# STATIONS=up: each workspace's stations up as a device has them as it starts (core/wsswitch.m says how), so a new
# chat's page is made on one as a device makes it (else every station down). Run twice on the same data: the first imports it, the second is the app
# started again (the one to read). AWAY_MS: how long away before the last switch (70 s: past what the core keeps of a
# topic let go of, store.ts EVICT_AFTER_MS).
ws_switch() {
  core_program wsswitch || return 1
  local dir=$(mktemp -d /tmp/mbui-ws-switch.XXXXXX) code=0
  (cd $CORE_TS && node bench/ws-switch-seed.ts "$dir" ${SCALE:-1}) || code=1
  for run in first again; do
    [ $code = 0 ] || break
    echo "== $run run =="
    AWAY_MS=$([ $run = first ] && echo 0 || echo ${AWAY_MS:-70000}) MB_CORE_BUNDLE=$OUT/core.hbc $OUT/wsswitch "$dir" || code=1
  done
  rm -rf "$dir"
  return $code
}

# Markdown read in Hermes as the core reads it (client/core-ts/bench/md-parse.ts over the bench's replies), bundled as the
# core is, run by Hermes's own command: characters read a second, and a chat's page (80 000 of them) in ms.
md_parse() {
  have_deps
  hermes_apple || return 1
  local o=$OUT/md-parse
  mkdir -p $o
  (cd $CORE_TS && node --input-type=module -e 'import { replies } from "./bench/replies.ts"; import { writeFileSync } from "node:fs"; writeFileSync(process.argv[1], "var TEXTS = " + JSON.stringify(replies()) + ";\n");' $o/texts.js) || return 1
  NODE_PATH=$CORE_TS/node_modules $CORE_TS/node_modules/.bin/esbuild $CORE_TS/bench/md-parse.ts --bundle --format=iife --platform=neutral \
    --main-fields=module,main --target=es2020 --supported:async-await=false --supported:async-generator=false --minify --legal-comments=none --resolve-extensions=.ts,.js,.mjs --log-level=warning --outfile=$o/bench.js || return 1
  (cd $CORE_TS && node --input-type=module -e "
import { readFileSync, writeFileSync } from 'node:fs';
import { transformSync } from '@babel/core';
const f = process.argv[1];
writeFileSync(f, transformSync(readFileSync(f, 'utf8'), { babelrc: false, configFile: false, compact: true, plugins: ['@babel/plugin-transform-classes'] }).code);" $o/bench.js) || return 1
  cat $o/texts.js $o/bench.js > $o/run.js
  "$(hermesc)" -emit-binary -O -block-scoping -out $o/run.hbc $o/run.js 2>&1 | grep -a "error:" && return 1
  $OUT/hermes/bin/hermes $o/run.hbc
}

# Mermaid's charts made in Hermes as the core makes them (client/core-ts/bench/mermaid.ts: mermaid, here compiled with it as
# the app's mermaid_hbc.mbt is, loaded for the first, then each kind of chart, timed), bundled as the core is.
mermaid_bench() {
  have_deps
  hermes_apple || return 1
  local o=$OUT/mermaid
  mkdir -p $o
  NODE_PATH=$CORE_TS/node_modules $CORE_TS/node_modules/.bin/esbuild $CORE_TS/bench/mermaid.ts --bundle --format=iife --platform=neutral \
    --main-fields=module,main --target=es2020 --supported:async-await=false --supported:async-generator=false --minify --legal-comments=none --resolve-extensions=.ts,.js,.mjs --log-level=warning --outfile=$o/bench.js || return 1
  (cd $CORE_TS && node --input-type=module -e "
import { readFileSync, writeFileSync } from 'node:fs';
import { transformSync } from '@babel/core';
const f = process.argv[1];
writeFileSync(f, transformSync(readFileSync(f, 'utf8'), { babelrc: false, configFile: false, compact: true, plugins: ['@babel/plugin-transform-classes'] }).code);" $o/bench.js) || return 1
  # (by its exit: its warnings quote lines of mermaid's that say "error:")
  "$(hermesc)" -emit-binary -O -block-scoping -out $o/run.hbc $o/bench.js > $o/hermesc.log 2>&1 \
    || { grep -a -o ": error: .\{0,200\}" $o/hermesc.log | head -20; return 1; }
  $OUT/hermes/bin/hermes $o/run.hbc
}

# mermaid as the app carries it (client/core-ts/scripts/mermaid-bundle.ts: sfbase's mermaid_hbc.mbt),
# made again with this hermesc: after mermaid or Hermes changes.
mermaid_lib() {
  have_deps
  (cd $CORE_TS && HERMESC="$(hermesc)" node scripts/mermaid-bundle.ts "$@")
}

# The core in the app's engine for macOS (core/mermaid_smoke.m) given mermaid's bytecode as the app gives it, then asked
# for charts: what Hermes's own command cannot try (the engine's `__native.evaluate`).
mermaid_smoke() {
  core_program mermaid_smoke || return 1
  hermes || return 1
  mermaid_lib --hbc $OUT/mermaid.hbc || return 1
  local dir=$(mktemp -d /tmp/mbui-mermaid-smoke.XXXXXX) code=0
  MB_CORE_BUNDLE=$OUT/core.hbc $OUT/mermaid_smoke "$dir" $OUT/mermaid.hbc || code=1
  rm -rf "$dir"
  return $code
}

# A station's JSON replies taken apart in Hermes as the core takes them apart (client/core-ts/bench/zstd-read.ts: fzstd,
# a piece at a time), compressed as a station compresses them (station/src/mesh/compress.ts: zstd at a reply's level and
# at a background batch's), bundled as the core is: plain bytes a second, by Hermes and by V8 beside it.
zstd_read() {
  have_deps
  hermes_apple || return 1
  local o=$OUT/zstd-read
  mkdir -p $o
  (cd $CORE_TS && node --input-type=module -e '
import { replies } from "./bench/replies.ts";
import { writeFileSync } from "node:fs";
import { constants, zstdCompressSync } from "node:zlib";
const entries = replies().map((text, i) => ({ seq: i + 1, ts: String(1790000000 + i), author_kind: "agent", author: "s-bench", text }));
const plain = Buffer.from(JSON.stringify({ entries }));
const packed = [3, 9].map((level) => ({ level, plain: plain.length, b64: zstdCompressSync(plain, { params: { [constants.ZSTD_c_compressionLevel]: level } }).toString("base64") }));
writeFileSync(process.argv[1], "var PACKED = " + JSON.stringify(packed) + ";\n");' $o/packed.js) || return 1
  NODE_PATH=$CORE_TS/node_modules $CORE_TS/node_modules/.bin/esbuild $CORE_TS/bench/zstd-read.ts --bundle --format=iife --platform=neutral \
    --main-fields=module,main --target=es2020 --supported:async-await=false --supported:async-generator=false --minify --legal-comments=none --resolve-extensions=.ts,.js,.mjs --log-level=warning --outfile=$o/bench.js || return 1
  (cd $CORE_TS && node --input-type=module -e "
import { readFileSync, writeFileSync } from 'node:fs';
import { transformSync } from '@babel/core';
const f = process.argv[1];
writeFileSync(f, transformSync(readFileSync(f, 'utf8'), { babelrc: false, configFile: false, compact: true, plugins: ['@babel/plugin-transform-classes'] }).code);" $o/bench.js) || return 1
  cat $o/packed.js $o/bench.js > $o/run.js
  "$(hermesc)" -emit-binary -O -block-scoping -out $o/run.hbc $o/run.js 2>&1 | grep -a "error:" && return 1
  echo "hermes:"
  $OUT/hermes/bin/hermes $o/run.hbc
  echo "v8:"
  node -e 'globalThis.print = console.log; (0, eval)(require("fs").readFileSync(process.argv[1], "utf8"))' $o/run.js
}

# listen.* (apple_core.mm on apple_listen.m) with core/listen-test.js (as bytecode) in the core's place: core/listen_test.m.
listen_test() {
  core_program listen_test || return 1
  hermes_script $ROOT/core/listen-test.js $OUT/listen-test.hbc || return 1
  local dir=$(mktemp -d /tmp/mbui-core-listen.XXXXXX) code=0
  MB_CORE_BUNDLE=$OUT/listen-test.hbc $OUT/listen_test "$dir" || code=1
  rm -rf "$dir"
  return $code
}

# exit() with the core's thread in a task (core/exit_test.m, with core/exit-test.js as bytecode in the core's place):
# the core ends before the statics it runs on are destroyed (apple_core.mm's stop_at_exit).
exit_test() {
  core_program exit_test || return 1
  hermes_script $ROOT/core/exit-test.js $OUT/exit-test.hbc || return 1
  local dir=$(mktemp -d /tmp/mbui-core-exit.XXXXXX) code=0
  MB_CORE_BUNDLE=$OUT/exit-test.hbc $OUT/exit_test "$dir" || code=1
  rm -rf "$dir"
  return $code
}

# Inputs and due timers on both native core loops, in Hermes (engine/tests/fairness.*), plus deterministic ordering,
# cancellation and equal-clock cases on the queue itself. Neither test depends on how long a task takes to run.
fairness_test() {
  local target=aarch64-apple-darwin fw
  apple_native $target || return 1
  fw=$(hermes_fw $target)
  hermes_script "$ROOT/engine/tests/fairness.js" "$OUT/fairness-test.hbc" || return 1
  clang++ -std=c++20 -O2 "$ROOT/engine/tests/ready_queue.cpp" -o "$OUT/ready-queue-test" || return 1
  "$OUT/ready-queue-test" || return 1
  clang++ -std=c++20 -O2 -fexceptions -frtti -I"$OUT/hermes/include" -I"$ROOT/engine" \
    "$ROOT/engine/engine.cpp" "$ROOT/engine/tests/fairness.cpp" -F"$fw" -framework hermes -Wl,-rpath,"$fw" \
    -o "$OUT/fairness-engine" || return 1
  "$OUT/fairness-engine" "$OUT/fairness-test.hbc" || return 1
  clang -fobjc-arc -O2 -Isrc/host -c "$MBUI_DIR/src/host/apple_listen.m" -o "$OUT/fairness-listen.o" || return 1
  clang++ -std=c++20 -O2 -DTEST_APPLE_HOST -Isrc/host "$ROOT/engine/tests/fairness.cpp" "$OUT/fairness-listen.o" \
    "$OUT/$target/libmbui_core.a" "$OUT/$target/libstillfail_shell.a" $(libs $target) -F"$fw" -framework hermes \
    -Wl,-rpath,"$fw" -framework LocalAuthentication -framework Foundation -o "$OUT/fairness-apple" || return 1
  mkdir -p "$OUT/fairness-test-data"
  "$OUT/fairness-apple" "$OUT/fairness-test.hbc" "$OUT/fairness-test-data"
}

# What still.fail's desktop app (Electron's safeStorage) sealed, opened as the app built in its place opens it
# (src/host/electron_sealed.h): core/sealed_test.m against files made as that app makes them. No core, no Keychain.
sealed_test() {
  clang -fobjc-arc -O2 -Wall -Isrc/host core/sealed_test.m -framework Foundation -o $OUT/sealed_test || return 1
  $OUT/sealed_test
}

# The order people read names in (src/host/apple_collate.h, the core's text.collate): core/collate_test.m. No core.
collate_test() {
  clang -fobjc-arc -O2 -Wall -Isrc/host core/collate_test.m -framework Foundation -o $OUT/collate_test || return 1
  $OUT/collate_test
}

# The core demo's login command (scripts/mac.sh login, MBUI_AUTH_LOGIN: still.fail's sign-in on the host's
# browser_login) as a station's remote login would run it, up to the person's browser step, against still.fail cloud: a fresh data directory, BROWSER a stand-in that keeps the
# page's address. Nobody signs in: the browser that comes back is curl, with a state that is not the sign-in's.
login_test() {
  MBUI_CORE=1 "$D/mac.sh" build > /dev/null
  local exe=$ROOT/_build/native/release/build/stillfail/coredemo/coredemo.exe
  local dir=$(mktemp -d /tmp/mbui-login.XXXXXX) code=0
  printf '#!/bin/sh\necho "$1" > "%s/url"\n' "$dir" > $dir/browser
  chmod +x $dir/browser
  MB_CORE_BUNDLE=$OUT/core.hbc MBUI_CORE_DATA=$dir/data BROWSER=$dir/browser MBUI_AUTH_LOGIN=1 $exe > $dir/out.log 2>&1 &
  local pid=$!
  # (the page given to BROWSER, as its stand-in writes it: scripts/waitfor.mjs, the file's events)
  node "$D/waitfor.mjs" --deadline 60 --what "the page given to BROWSER" --exists $dir/url > /dev/null
  local url=$(cat $dir/url 2>/dev/null)
  ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; code=1; fi; }
  ok "the page went to BROWSER" '[ -n "$url" ]'
  local port=$(python3 -c '
import sys, urllib.parse as u
p = u.urlparse(sys.argv[1]); q = u.parse_qs(p.query); back = u.urlparse(q.get("redirect_uri", [""])[0])
ok = p.scheme == "https" and p.path == "/v1/auth/google/start" and "state" in q and back.scheme == "http" and back.hostname == "127.0.0.1" and back.path == "/oauth/callback"
print(back.port if ok else 0)' "$url")
  ok "it is still.fail cloud's login page, coming back to 127.0.0.1:$port/oauth/callback" '[ "$port" -gt 0 ]'
  if [ -f "$SF_SRC/station/src/logins/parse.ts" ]; then
    local seen=$(node --experimental-strip-types --no-warnings --input-type=module -e "
const { loopbackOf } = await import('$SF_SRC/station/src/logins/parse.ts');
const b = loopbackOf(process.argv[1]);
console.log(b && b.state ? b.host + ':' + b.port + b.path : 'none');" "$url" 2>&1)
    ok "a station's login takes it as a loopback login with a state ($seen)" '[ "$seen" = "127.0.0.1:$port/oauth/callback" ]'
  fi
  ok "the app itself listens there (lsof, as the station checks before relaying)" 'lsof -a -p $pid -iTCP:$port -sTCP:LISTEN -n -P | grep -q "127.0.0.1:$port"'
  ok "another path is not taken" '[ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$port/favicon.ico)" = 404 ]'
  ok "nor the callback under another host name" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: elsewhere.example:$port" "http://127.0.0.1:$port/oauth/callback?code=x&state=y")" = 404 ]'
  ok "the app still waits" 'kill -0 $pid 2>/dev/null'
  local back=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" "http://127.0.0.1:$port/oauth/callback?code=x&state=not-this-one")
  ok "the browser coming back is sent on to still.fail cloud's page saying it is signed in ($back)" '[ "${back%% *}" = 302 ] && case "${back#* }" in https://*/v1/auth/done) true ;; *) false ;; esac'
  local exit_code=0
  # (its end, as the system tells it: mbui's scripts/chk logwait --pid, kqueue's; not waited for forever, then killed)
  "$MBUI_DIR/scripts/chk" logwait --pid $pid --deadline 60 > /dev/null || kill $pid 2> /dev/null
  wait $pid || exit_code=$?
  ok "the app exits 1 (the state was not the sign-in's: $(grep -a 'Sign-in failed' $dir/out.log | head -1))" '[ $exit_code = 1 ] && grep -q "Sign-in failed" $dir/out.log'
  ok "it no longer listens" '! lsof -iTCP:$port -sTCP:LISTEN -n -P > /dev/null'
  [ $code = 0 ] || cat $dir/out.log
  rm -rf "$dir"
  return $code
}

# src/core/vectors_test.mbt: core-ts's diff and apply over values shaped like the topics (core/delta-vectors.ts).
vectors() {
  SF_SRC=$SF_SRC node core/delta-vectors.ts > src/core/vectors_test.mbt
  echo "vectors: $(grep -c '^test ' src/core/vectors_test.mbt) tests in src/core/vectors_test.mbt"
}

# (the shell's .a stripped only here, for its size: the apps link the unstripped one, and stripping 70 MB took a minute
# and more on CI's macOS runner, beside a simulator booting)
sizes() {
  for a in $OUT/*/libstillfail_shell.a; do
    [ -f "$a" ] && strip -S -x -o "${a%.a}.stripped.a" "$a" 2>/dev/null
  done
  ls -la $OUT/core.hbc $OUT/*/libstillfail_shell*.a $OUT/*/libmbui_core.a $OUT/smoke $OUT/smoke.stripped 2>/dev/null
}

case "${1:-all}" in
  deps) deps ;;
  shell) shell "$2" ;;
  hermes) [ "${2:-}" != apple ] || ENTRY=${ENTRY:-$APPLE_ENTRY}; hermes ;;
  hermes-kept) hermes_kept "${2:-}" ;;
  hermes-script) hermes_script "$2" "${3:-}" ;;
  hermes-apple) hermes_apple ;;
  engine) engine "${2:-aarch64-apple-darwin}" ;;
  apple) apple "${2:-aarch64-apple-darwin}" ;;
  apple-native) apple_native "${2:-aarch64-apple-darwin}" ;;
  listen) listen_test ;;
  chat-open) chat_open ;;
  ws-switch) ws_switch ;;
  md-parse) md_parse ;;
  mermaid) mermaid_bench ;;
  mermaid-lib) mermaid_lib ;;
  mermaid-smoke) mermaid_smoke ;;
  zstd-read) zstd_read ;;
  exit) exit_test ;;
  fairness) fairness_test ;;
  collate) collate_test ;;
  sealed) sealed_test ;;
  login-test) login_test ;;
  smoke)
    case "${2:-all}" in
      build) smoke_build ;;
      run) smoke_run ;;
      *) smoke_build && smoke_run ;;
    esac ;;
  vectors) vectors ;;
  sizes) sizes ;;
  clean) rm -rf "$CARGO_TARGET_DIR"; echo "removed $CARGO_TARGET_DIR (out/core kept)" ;;
  all) deps; shell; smoke_build; smoke_run; sizes ;;
  *) echo "usage: scripts/core.sh deps | shell [TARGET] | hermes [apple] | hermes-kept [apple] | hermes-script FILE [OUT] | hermes-apple | engine [TARGET] | apple [TARGET] | apple-native [TARGET] | smoke [build|run] | listen | exit | fairness | collate | login-test | vectors | sizes | chat-open | ws-switch | md-parse | mermaid | mermaid-lib | mermaid-smoke | zstd-read | clean | all"; exit 2 ;;
esac

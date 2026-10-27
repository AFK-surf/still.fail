#!/usr/bin/env python3
"""Every catalog key the app's sources say is in the words.txt of the package whose `tr` says it, so scripts/strings
puts its words in that package's tables: a key said but not listed shows as the key itself (web-main.composer.ccLabel
showed as such in the composer). The settings (src/sfapp/settings) say theirs from their own words.txt, but what they
say through @sf.t; every other package says through @sf.t, sfbase's, which has the settings' words too. A key is a
string literal of the sources that the catalog (client/i18n/catalog/zh) has; keys put together from parts
(`"web-main.keymap." + id`) are not seen.

  python3 scripts/words.py --check  fails, naming each key and where it is said (scripts/check.sh)"""
import glob, json, os, re, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(A))
SETTINGS = os.path.join(A, "src/sfapp/settings")
BASE = os.path.join(A, "src/sfbase")


def listed(pkg):
    with open(os.path.join(pkg, "words.txt"), encoding="utf-8") as f:
        return {k.strip() for k in f if k.strip() and not k.strip().startswith("#")}


catalog = set()
for part in glob.glob(os.path.join(ROOT, "client/i18n/catalog/zh/*.json")):
    with open(part, encoding="utf-8") as f:
        catalog.update(json.load(f))
words = {SETTINGS: listed(SETTINGS), BASE: listed(BASE) | listed(SETTINGS)}
lacking = []
for path in sorted(glob.glob(os.path.join(A, "src/**/*.mbt"), recursive=True)):
    if re.search(r"/strings_(zh|en)\.mbt$", path):
        continue
    own = SETTINGS if path.startswith(SETTINGS + os.sep) else BASE
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            for via, key in re.findall(r'(@sf\.t\()?"([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+)"', line):
                pkg = BASE if via else own
                if key in catalog and key not in words[pkg]:
                    lacking.append(f"{os.path.relpath(pkg, A)}/words.txt lacks {key} ({os.path.relpath(path, A)}:{n})")
if lacking:
    print("words: keys said but not in their package's words.txt (add them, then scripts/strings):", file=sys.stderr)
    for line in lacking:
        print("  " + line, file=sys.stderr)
    sys.exit(1)

#!/bin/bash
# Type-check every target of this module (and mbui with it); print errors only. First: every global of the app's
# (a top-level `let` in src/sfapp and its packages, but their tests, of a Ref, Map, Array or struct: anything but
# Int, Double, String, Bool, Json…) is put back by its package's reset() or what that calls (as each Tester starts:
# src/sfapp/app.mbt init), or says why not on the line over it (`// kept across runs: …`), so that nothing a Tester
# left is the next one's input.
D="$(cd "$(dirname "$0")" && pwd)"
# (no git: it runs in copies without one; no file to look in, no reset(), or python's own error fails the check)
python3 - "$D/../src/sfapp" <<'EOF' || exit 1
import os, re, sys
root = sys.argv[1]
plain = {"Int", "Int64", "UInt", "UInt64", "Int16", "UInt16", "Double", "Float", "String", "Bool", "Char", "Byte",
         "Bytes", "Json", "Unit"}
pkgs = {}
for d, _, names in os.walk(root):
    pkg = os.path.relpath(d, root).replace(os.sep, "/")
    for n in names:
        if n.endswith(".mbt") and not n.endswith(("_test.mbt", "_wbtest.mbt")):
            pkgs.setdefault("" if pkg == "." else pkg, []).append(os.path.join(d, n))
if "" not in pkgs:
    sys.exit("apps/mbui/scripts/check.sh: no files of src/sfapp to look in")
fn_re = re.compile(r"^(?:pub(?:\([a-z]+\))? )?fn ((?:[A-Za-z_]\w*::)?[a-z_]\w*)\b")
let_re = re.compile(r"^(?:pub(?:\([a-z]+\))? )?let ([a-z_]\w*) *(?:: *(.*?))? *=")
fns, lets = {}, []
for pkg, files in pkgs.items():
    for f in files:
        lines = open(f, encoding="utf-8").read().split("\n")
        for i, l in enumerate(lines):
            m = fn_re.match(l)
            if m:
                j = i + 1
                while j < len(lines) and not lines[j].startswith("}"):
                    j += 1
                fns.setdefault((pkg, m.group(1)), []).append("\n".join(lines[i + 1:j]))
            m = let_re.match(l)
            if m:
                k = i - 1
                while k >= 0 and lines[k].strip() == "":
                    k -= 1
                kept = k >= 0 and lines[k].startswith("// kept across runs:")
                lets.append((pkg, m.group(1), m.group(2) or "", f, i + 1, kept))
if ("", "reset") not in fns:
    sys.exit("apps/mbui/scripts/check.sh: no fn reset() in src/sfapp")
# what each package's reset() reaches: its body, and those of the functions it calls (its own, or @pkg.f of another
# package here), and theirs
alias = {p.split("/")[-1]: p for p in pkgs if p}
seen, todo, said = set(), [(p, "reset") for p in pkgs if (p, "reset") in fns], {p: [] for p in pkgs}
while todo:
    key = todo.pop()
    if key in seen or key not in fns:
        continue
    seen.add(key)
    for body in fns[key]:
        said[key[0]].append(body)
        for q, name in re.findall(r"(?<![\w.:])(?:@(\w+)\.)?([a-z_]\w*)\(", body):
            p = alias.get(q) if q else key[0]
            if p is not None:
                todo.append((p, name))
        for q, name in re.findall(r"@(\w+)\.([a-z_]\w*)", body):
            if q in alias:
                said[alias[q]].append(name)
bad = []
for pkg, name, ty, f, n, kept in lets:
    if ty and set(re.findall(r"[A-Za-z_]\w*", re.sub(r"@\w+\.", "", ty))) <= plain:
        continue
    if kept or re.search(r"(?<![\w.@])" + re.escape(name) + r"\b", "\n".join(said[pkg])):
        continue
    bad.append(f"  {os.path.relpath(f, os.path.dirname(root))}:{n}: {name} : {ty}")
if bad:
    print("apps/mbui/src: globals kept from one Tester to the next: put back by reset(), or `// kept across runs: why`")
    print("\n".join(bad))
    sys.exit(1)
EOF
. "$D/env.sh"
cd "$A"
for t in ${TARGETS:-js native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | python3 "$MBUI_DIR/scripts/errs.py"
done

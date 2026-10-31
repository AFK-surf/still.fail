#!/bin/bash
# View::scale refusing an old view (view's scale_test.mbt, its four refused scenes): each scene alone in a process of
# its own (MBUI_REFUSED=<scene>), judged by how that process ended. Refused: built (no compiler's error), stopped by
# the program's abort (rc 255), the refusal said by the running program with the scale it was refused at (not the
# line of source quoted), and never past the call refused ("not refused" unsaid). The ordinary run of the file
# after: none of them does anything.
#   scripts/refused_scale.sh            the check (scripts/test_native.sh runs it)
#   scripts/refused_scale.sh --counter  for development: the guards where the change is made taken out (the read-side
#                                       ones left), restored however it ends; the scenes made straight must then run
#                                       past their call (rc 0, "not refused" said)
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# (as test_native builds them, --release by the C step: its programs, built by it already, run again, none built anew)
cd "$D/.." || exit 2
out=$(mktemp -d)
w=0
said='drawn 0.5 as big: View::scale holds no old view'
run() { # scene out
  MBUI_REFUSED=$1 moon_test_native src/view/scale_test.mbt > "$2" 2>&1
}
built() { # out: no compiler's error in it
  ! grep -aq 'Error: \[\|error\[\|^error:' "$1"
}
told() { # out: the refusal said by the running program, not a quoted source line
  grep -a "$said" "$1" | grep -avq '│\|^ *[0-9][0-9]* |\|abort("'
}
refused() { # scene
  local o="$out/$1.txt" r
  run "$1" "$o"; r=$?
  if built "$o" && [ $r -eq 255 ] && told "$o" && ! grep -aq 'not refused' "$o"; then
    echo "== $1 refused (rc=$r): $(grep -a "$said" "$o" | head -1 | cut -c1-160)"
  else
    echo "== $1 NOT refused as said: rc=$r built=$(built "$o" && echo yes || echo no) told=$(told "$o" && echo yes || echo no)"
    grep -a "Error\|error\|not refused\|$said" "$o" | cut -c1-300 | head -6
    w=1
  fi
}
let_through() { # scene
  local o="$out/$1.txt" r
  run "$1" "$o"; r=$?
  if built "$o" && [ $r -eq 0 ] && grep -aq 'not refused' "$o" && ! told "$o"; then
    echo "== $1 let through without its guard (rc=$r), as it should be"
  else
    echo "== $1 NOT let through without its guard: rc=$r"
    grep -a "Error\|error\|$said" "$o" | cut -c1-300 | head -6
    w=1
  fi
}
if [ "$1" = --counter ]; then
  v=src/view/view.mbt
  keep="$out/view.mbt"
  cp "$v" "$keep"
  trap 'cp "$keep" "$v"; rm -rf "$out"' EXIT
  trap 'exit 130' INT TERM
  perl -0pi -e 's/    if s != 1.0 && self.tree.hosts_within\(self.at\) \{\n      hosted_refused\(s\)\n    \}\n//; s/    match tree.scale_over\(v.at\) \{\n      Some\(s\) => hosted_refused\(s\)\n      None => \(\)\n    \}\n//' "$v"
  if grep -q 'hosts_within(self.at)\|scale_over(v.at)' "$v"; then echo "== the guards NOT taken out"; exit 1; fi
  let_through hosted-in-scaled
  let_through scale-over-hosted
  exit $w
fi
trap 'rm -rf "$out"' EXIT
for s in hosted-in-scaled scale-over-hosted hosted-shown scaled-by; do
  refused $s
done
moon_test_native src/view/scale_test.mbt > "$out/plain.txt" 2>&1; r=$?
echo "== the file's ordinary run rc=$r $(grep -a 'Total tests' "$out/plain.txt" | tail -1)"
[ $r -ne 0 ] && w=1
exit $w

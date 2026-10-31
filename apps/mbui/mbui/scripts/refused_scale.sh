#!/bin/bash
# (run from anywhere: mbui's root found from here)
# View::scale refusing an old view: each scene alone in a process of its own (MBUI_REFUSED), its exit and what it said;
# refused = it stopped (rc != 0) saying the refusal, and never got past (no "not refused"). Then with the guards where
# the change is made taken out (the read-side ones left): the scenes made straight must no longer be refused.
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
out=$(mktemp -d)
w=0
run() { # tag scene out
  ( . scripts/env.sh && MBUI_REFUSED=$2 moon test --target native src/view/scale_test.mbt ) > "$3" 2>&1
}
judge() { # tag scene out rc want(refused|let)
  local said=no past=no
  grep -aq "View::scale holds no old view" "$3" && said=yes
  grep -aq "not refused" "$3" && past=yes
  if [ "$5" = refused ]; then
    if [ "$4" -ne 0 ] && [ $said = yes ] && [ $past = no ]; then echo "== $1 $2 refused as said (rc=$4)"; else echo "== $1 $2 NOT refused as said rc=$4 said=$said past=$past"; grep -a "error\|Error\|FAILED" "$3" | head -5; w=9; fi
  else
    if [ $past = yes ] && [ $said = no ]; then echo "== $1 $2 let through, as without its guard"; else echo "== $1 $2 NOT let through rc=$4 said=$said past=$past"; grep -a "error\|Error" "$3" | head -5; w=9; fi
  fi
}
for s in hosted-in-scaled scale-over-hosted hosted-shown scaled-by; do
  run refuse $s $out/rf-$s.txt; r=$?; judge refuse $s $out/rf-$s.txt $r refused
done
# (the ordinary run: none of them does anything)
( . scripts/env.sh && moon test --target native src/view/scale_test.mbt ) > $out/rf-plain.txt 2>&1; r=$?
echo "== plain rc=$r $(grep -a 'Total tests' $out/rf-plain.txt | tail -1)"; [ $r -ne 0 ] && w=9
# counterproof: the guards at the change taken out
v="$root/src/view/view.mbt"; b=$(mktemp); cp $v $b; trap 'cp '$b' '$v'; rm -f '$b EXIT
perl -0pi -e 's/    if s != 1.0 && self.tree.hosts_within\(self.at\) \{\n      hosted_refused\(s\)\n    \}\n//; s/    match tree.scale_over\(v.at\) \{\n      Some\(s\) => hosted_refused\(s\)\n      None => \(\)\n    \}\n//' $v
if grep -q "hosts_within(self.at)\|scale_over(v.at)" $v; then echo "== counter entryguards NOT APPLIED"; w=9; else
  for s in hosted-in-scaled scale-over-hosted; do
    run counter $s $out/rfc-$s.txt; r=$?; judge counter $s $out/rfc-$s.txt $r let
  done
fi
cp $b $v
echo "worst=$w"; exit $w

#!/bin/sh
# Proves rules/protocol/lock.spthy with Tamarin (tamarin-prover and maude on PATH), each lemma on its own, a minute at
# most; then plants a mistake in a copy for each of what it is to catch, which must then be falsified: a station taking
# an entry no device of its lock signed, a device approving a key whose code it was not shown, a vault's key sealed to
# a box key no device certified. Exits 1 when a lemma is not verified, or a planted mistake not caught.
cd "$(dirname "$0")"
bad=0
lemmas=$(grep -oE '^lemma [a-z_]+' lock.spthy | cut -d' ' -f2)
said() { # file lemma -> verified | falsified | none
  timeout 60 tamarin-prover --prove="$2" "$1" 2>/dev/null | grep -E "^ +$2 \(" | grep -oE 'verified|falsified' | head -1
}
for l in $lemmas; do
  r=$(said lock.spthy "$l")
  if [ "$r" = verified ]; then echo "protocol: $l: verified"; else echo "protocol: $l: ${r:-not ended in a minute}" >&2; bad=1; fi
done
work=$(mktemp -d)
plant() { # name lemma from to
  python3 -c "import sys;p,a,b,o=sys.argv[1:];s=open(p).read();assert s.count(a)==1,a;open(o,'w').write(s.replace(a,b))" lock.spthy "$3" "$4" "$work/m.spthy" ||
    { echo "protocol: \"$1\" is not in lock.spthy as it was; update rules/protocol/check.sh" >&2; bad=1; return; }
  r=$(said "$work/m.spthy" "$2")
  if [ "$r" = falsified ]; then echo "protocol: planted, $1: $2 falsified"; else echo "protocol: planted, $1: $2 ${r:-not ended in a minute}, not caught" >&2; bad=1; fi
}
plant "a station takes an entry unsigned" each_key_taken_as_its_signer_approved \
  "In(<'device', pkNew, pk(signer), sign(<'device', pkNew>, signer)>)" "In(<'device', pkNew, pk(signer)>)"
plant "a device approves a key it was shown no code of" approved_only_as_shown \
  "In(pkNew), !Shown(h(pkNew)) ]" "In(pkNew) ]"
plant "a vault's key sealed to a box key no device certified" sealed_to_certified \
  "In(<'box', boxPub, pk(d), sign(<'box', boxPub>, d)>)" "In(<'box', boxPub, pk(d)>)"
for l in $(grep -oE '^lemma [a-z_]+' person.spthy | cut -d' ' -f2); do
  r=$(said person.spthy "$l")
  if [ "$r" = verified ]; then echo "protocol: person: $l: verified"; else echo "protocol: person: $l: ${r:-not ended in a minute}" >&2; bad=1; fi
done
plantp() { # name lemma from to
  python3 -c "import sys;p,a,b,o=sys.argv[1:];s=open(p).read();assert s.count(a)==1,a;open(o,'w').write(s.replace(a,b))" person.spthy "$3" "$4" "$work/p.spthy" ||
    { echo "protocol: \"$1\" is not in person.spthy as it was; update rules/protocol/check.sh" >&2; bad=1; return; }
  r=$(said "$work/p.spthy" "$2")
  if [ "$r" = falsified ]; then echo "protocol: planted, $1: $2 falsified"; else echo "protocol: planted, $1: $2 ${r:-not ended in a minute}, not falsified" >&2; bad=1; fi
}
plantp "a station takes a binding unsigned" bound_as_its_device_said \
  "In(<'person', root, pk(d), sign(<'person', root>, d)>)" "In(<'person', root, pk(d)>)"
plantp "a station goes along a chain unsigned" each_key_as_its_signer_approved \
  "In(<'pdevice', root, pkNew, wk, pk(s), sign(<'pdevice', root, pkNew, wk>, s)>)" "In(<'pdevice', root, pkNew, wk, pk(s)>)"
plantp "a signer taken of an entry unsigned" signer_as_its_approver_said \
  "In(<'pdevice', root, pkNew, wk, pk(s), sign(<'pdevice', root, pkNew, wk>, s)>)" "In(<'pdevice', root, pkNew, wk, pk(s)>)"
plantp "a device approves a key it was shown no code of" approved_only_as_shown \
  "In(<pkNew, wk>), !Shown(h(<pkNew, wk>)) ]" "In(<pkNew, wk>) ]"
plantp "a device approves a signer the code it was shown was not of" approved_only_as_shown \
  "In(<pkNew, wk>), !Shown(h(<pkNew, wk>)) ]" "In(<pkNew, wk>), !Shown(h(<pkNew, other>)) ]"
rm -rf "$work"
exit $bad

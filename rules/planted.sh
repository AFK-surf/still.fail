#!/bin/sh
# Mistakes planted in the proved rules, one at a time: each must make `moon prove` fail, so the proofs still say
# what they are meant to. Each in a copy of rules/ of its own, one after another (side by side, a why3server now and
# then sat idle for good). Exits 1 when one still proves.
cd "$(dirname "$0")"
work=$(mktemp -d)
n=0
plant() { # name, file, from, to
  n=$((n + 1))
  d="$work/$n"
  mkdir -p "$d" && cp -R moon.mod src "$d/" || exit 1
  python3 -c "import sys;p,a,b=sys.argv[1:];s=open(p).read();assert s.count(a)==1,a;open(p,'w').write(s.replace(a,b))" "$d/$2" "$3" "$4" ||
    { echo "planted: \"$1\" is not in $2 as it was; update rules/planted.sh" >&2; exit 1; }
  echo "$1" > "$d/name"
  (cd "$d" && if moon prove > out 2>&1; then echo proved > verdict; else echo failed > verdict; fi)
}
# (the rules as they are, in a copy as the others: must prove, or the copies fail for another reason)
plant "unchanged" src/role/role.mbt "pub fn lower(" "pub fn lower("
plant "a lock's last owner taken out" src/role/role.mbt "    owners >= 2" "    owners >= 1"
plant "an own signer replaced" src/role/role.mbt "  if own_found {
    false
  } else if !holds" "  if false {
    false
  } else if !holds"
plant "a device that ran out signs" src/role/role.mbt "  } else if !live {
    false
  } else {
    member" "  } else if false {
    false
  } else {
    member"
plant "someone else's device admitted" src/role/role.mbt "  } else if !theirs {
    Others" "  } else if false {
    Others"
plant "a manager binds someone else to a lock" src/role/role.mbt "  if !mine {
    false
  } else {
    own
  }" "  if false {
    false
  } else {
    own
  }"
plant "a person's last device taken off" src/role/role.mbt "  if !held {
    false
  } else {
    !lone
  }" "  if !held {
    false
  } else {
    true
  }"
plant "a device let in on a lock its member did not bind" src/role/role.mbt "  if !pinned {
    false
  } else if !proved" "  if false {
    false
  } else if !proved"
plant "a device put in by another gets vault keys" src/role/role.mbt "  if own {
    true
  } else {
    ever
  }" "  if own {
    true
  } else {
    true
  }"
plant "a device put in by another signs a vault" src/role/role.mbt "  } else if !own {
    false
  } else {
    member" "  } else if false {
    false
  } else {
    member"
plant "a member taken out keeps the vault key" src/history/history.mbt "  } else if gone && next == prev {
    false" "  } else if false {
    false"
plant "a deleted item written again" src/history/history.mbt "  if was {
    false
  } else {
    true
  }" "  if was {
    true
  } else {
    true
  }"
plant "an owner or admin makes someone's own device" src/role/role.mbt "  } else if had_own {
    false" "  } else if false {
    false"
plant "a child comes before itself in the fork choice" src/fork/fork.mbt "  } else {
    ha < hb
  }" "  } else {
    ha <= hb
  }"
plant "the fork choice keeps the first child it was given" src/fork/fork.mbt "    if ahead(ws[i], rs[i], ts[i], hs[i], ws[b], rs[b], ts[b], hs[b]) {
      b = i
    }" "    if ahead(ws[i], rs[i], ts[i], hs[i], ws[b], rs[b], ts[b], hs[b]) {
      b = b
    }"
bad=0
for d in "$work"/*; do
  name=$(cat "$d/name") verdict=$(cat "$d/verdict")
  if [ "$name" = unchanged ]; then
    if [ "$verdict" = proved ]; then echo "planted: unchanged: proves"; else echo "planted: the rules unchanged do not prove in a copy:" >&2; tail -20 "$d/out" >&2; bad=1; fi
  elif [ "$verdict" = failed ]; then echo "planted: $name: the proof fails"; else echo "planted: $name: STILL PROVES" >&2; bad=1; fi
done
rm -rf "$work"
exit $bad

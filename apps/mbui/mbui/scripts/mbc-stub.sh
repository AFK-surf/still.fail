#!/bin/sh
# The C compiler and archiver `scripts/mbc gen` gives moon (MOON_CC, MOON_AR): moonc's steps run as they would,
# the C compiler's and the archiver's only leave an empty file where their output would be. Only the C that moonc
# generates is wanted (the Android and iOS builds compile it with their own compiler); moon's compile of it for
# this machine is the slowest step of its build and of no use to them.
out=
prev=
for a in "$@"; do
  [ "$prev" = -o ] && out=$a
  # moon asks the compiler for the machine it builds for: the machine's own compiler answers
  [ "$a" = -dumpmachine ] && exec "${MBC_HOST_CC:-cc}" -dumpmachine
  prev=$a
done
# the archiver: `ar -r -c -s LIB.a OBJ…` (libtool's `-static -o LIB.a` is the -o above)
if [ -z "$out" ]; then
  for a in "$@"; do
    case "$a" in *.a|*.lib) out=$a; break ;; esac
  done
fi
[ -n "$out" ] && : > "$out"
exit 0

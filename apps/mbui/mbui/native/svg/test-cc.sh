#!/bin/bash
set -eu
for arg in "$@"; do
  if [ "$arg" = -c ]; then exec "${SVG_TEST_CC:-cc}" "$@"; fi
done
# Static archives must precede their math dependency on ELF linkers.
exec "${SVG_TEST_CC:-cc}" "$@" "$SVG_TEST_LIB" -lm

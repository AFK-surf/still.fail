#!/bin/bash
set -eu
for arg in "$@"; do
  if [ "$arg" = -c ]; then exec "${SVG_TEST_CC:-cc}" "$@"; fi
done
exec "${SVG_TEST_CC:-cc}" "$@" "$SVG_TEST_LIB"

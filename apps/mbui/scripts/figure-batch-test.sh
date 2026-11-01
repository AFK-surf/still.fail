#!/bin/bash
# The batched pictures are the same as individual renders; a failed batch keeps the existing files.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
mkdir -p out
take=$(mktemp -d "$PWD/out/figure-batch-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
bash scripts/figure.sh wrap "$take/wrap.png"
bash scripts/figure.sh align "$take/align.png"
bash scripts/figure.sh --batch "$take/batch" wrap align
cmp "$take/wrap.png" "$take/batch/wrap.png"
cmp "$take/align.png" "$take/batch/align.png"
if bash scripts/figure.sh --batch "$take/batch" wrap not-a-figure; then
  echo 'figure-batch-test: an unknown figure succeeded' >&2
  exit 1
fi
cmp "$take/wrap.png" "$take/batch/wrap.png"
cmp "$take/align.png" "$take/batch/align.png"
if find "$take/batch" -name '.figure-batch.*' -print | rg -q .; then
  echo 'figure-batch-test: a temporary batch remained' >&2
  exit 1
fi
echo 'figure-batch-test: identical pictures; a failed batch keeps the previous files'

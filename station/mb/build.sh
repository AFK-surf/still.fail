#!/bin/bash
# Builds the station's MoonBit programs (station/mb, natively): the reader, _build/native/release/build/station/reader/
# reader.exe. Linked to the shell's static library (client/shell), which SHELL_LIB names, or scripts/native.ts gets
# (shell-apple: the Mac's), put in out/ where the program's link flags take it (src/reader/moon.pkg). MBUI_TOOLS, as
# apps/mbui's scripts have it, says where moon is when it is not on PATH.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
[ -n "${MBUI_TOOLS:-}" ] && export MOON_HOME=$MBUI_TOOLS/moon PATH=$MBUI_TOOLS/moon/bin:$PATH
lib=${SHELL_LIB:-$(node "$ROOT/scripts/native.ts" path shell-apple darwin-arm64)/libstillfail_shell.a}
mkdir -p "$D/out"
# (copied only when it differs: moon links the program again when what it links is newer)
cmp -s "$lib" "$D/out/libstillfail_shell.a" || cp "$lib" "$D/out/libstillfail_shell.a"
cd "$D"
moon build --target native --release src/reader

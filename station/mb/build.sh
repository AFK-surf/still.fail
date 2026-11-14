#!/bin/bash
# Builds the station's reader in MoonBit (station/mb) for TARGET (darwin-arm64 by default, linux-x64, linux-arm64,
# win32-x64), on a Mac, into OUT (default _build/stillfail-reader-TARGET). MoonBit makes the program's C here; it is
# compiled and linked here too, for each target (zig cc for Linux, glibc 2.28 on, and for Windows, MinGW's), with
# MoonBit's runtime from its source, its reference cycles collected (MOONBIT_TRIAL_DELETION) on the system allocator.
# Linked to the shell's static library (client/shell), which SHELL_LIB names, or scripts/native.ts gets for the target
# (shell-apple on the Mac, shell-station elsewhere). MBUI_TOOLS, as apps/mbui's scripts have it, says where moon is when
# it is not on PATH.
#   build.sh [TARGET] [OUT]
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
[ -n "${MBUI_TOOLS:-}" ] && export MOON_HOME=$MBUI_TOOLS/moon PATH=$MBUI_TOOLS/moon/bin:$PATH
target=${1:-darwin-arm64}
out=${2:-$D/_build/stillfail-reader-$target}
case "$target" in
  darwin-arm64) cc=(cc -arch arm64 -mmacosx-version-min=11.0); ar=(ar); part=shell-apple
    libs=(-framework SystemConfiguration -framework Security -framework CoreFoundation -framework Foundation -liconv -lobjc -Wl,-dead_strip) ;;
  linux-x64) cc=(zig cc -target x86_64-linux-gnu.2.28); ar=(zig ar); part=shell-station
    libs=(-lunwind -lutil -lrt -lpthread -lm -ldl -lc -Wl,--gc-sections -s) ;;
  linux-arm64) cc=(zig cc -target aarch64-linux-gnu.2.28); ar=(zig ar); part=shell-station
    libs=(-lunwind -lutil -lrt -lpthread -lm -ldl -lc -Wl,--gc-sections -s) ;;
  win32-x64) cc=(zig cc -target x86_64-windows-gnu); ar=(zig ar); part=shell-station
    libs=(-lshell32 -liphlpapi -lbcrypt -ladvapi32 -lkernel32 -lntdll -luserenv -lws2_32 -ldbghelp -lunwind -s) ;;
  *) echo "build.sh: no target $target" >&2; exit 2 ;;
esac
shell_lib=${SHELL_LIB:-$(node "$ROOT/scripts/native.ts" path $part $target)/libstillfail_shell.a}
mac_lib=$shell_lib
[ "$target" = darwin-arm64 ] || mac_lib=$(node "$ROOT/scripts/native.ts" path shell-apple darwin-arm64)/libstillfail_shell.a

# The program's C, by moon (which links it for the Mac as well: its link flags take the Mac's shell from out/, as
# src/reader/moon.pkg says; copied only when it differs, moon linking again when what it links is newer).
mkdir -p "$D/out"
cmp -s "$mac_lib" "$D/out/libstillfail_shell.a" || cp "$mac_lib" "$D/out/libstillfail_shell.a"
(cd "$D" && moon build --target native --release src/reader)
moon_home=${MOON_HOME:-$(dirname "$(dirname "$(command -v moon)")")}
flags=(-I"$moon_home/include" -O2 -fwrapv -fno-strict-aliasing -ffp-contract=off -Wno-unused-value -DMOONBIT_TRIAL_DELETION=1)

# MoonBit's runtime for the target: each of its files that builds there (the others are moonbitlang/async's, which the
# program does not use, and which on Windows build with MSVC only), in an archive the link takes what it needs from.
work="$D/_build/link-$target"
rm -rf "$work"
mkdir -p "$work/runtime"
for c in "$moon_home"/lib/runtime/*.c; do
  "${cc[@]}" "${flags[@]}" -c "$c" -o "$work/runtime/$(basename "$c" .c).o" 2> /dev/null || true
done
"${ar[@]}" rcs "$work/libruntime.a" "$work"/runtime/*.o
"${cc[@]}" "${flags[@]}" -o "$out" "$D/_build/native/release/build/station/reader/reader.c" "$D/src/host/host.c" "$D/src/sql/sql.c" \
  "$work/libruntime.a" "$shell_lib" "${libs[@]}"
echo "$out"

#!/bin/bash
# Source after the MSVC action: the app and its release variants must use the same compiler to share mbc's objects.
[ -n "${llvmX64:-}" ] || { echo "win-compiler: Visual Studio's LLVM directory is not set" >&2; return 1; }
export MBC_REAL_CC="$llvmX64\\clang-cl.exe"
# MoonBit's runtime passes an int32_t * for a DWORD *; clang, like cl, should report that as a warning.
export CL="/clang:-Wno-error=incompatible-pointer-types ${CL:-}"

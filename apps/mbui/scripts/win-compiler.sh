#!/bin/bash
# The app and its release variants share mbc's objects only when built by the same compiler. Use Visual Studio's
# clang-cl when installed (faster than cl on the runner), but leave an explicit MBC_REAL_CC and machines without it alone.
if [ -z "${MBC_REAL_CC:-}" ] && [ -n "${llvmX64:-}" ] && [ -f "$(cygpath -u "$llvmX64")/clang-cl.exe" ]; then
  export MBC_REAL_CC="$llvmX64\\clang-cl.exe"
fi
case "${MBC_REAL_CC:-}" in
  *clang-cl|*clang-cl.exe)
    # MoonBit's runtime passes an int32_t * for a DWORD *; clang, like cl, should report that as a warning. This may
    # be sourced by the release workflow as well as win.sh when it builds an older, reviewed revision.
    case " ${CL:-} " in
      *" /clang:-Wno-error=incompatible-pointer-types "*) ;;
      *) export CL="/clang:-Wno-error=incompatible-pointer-types ${CL:-}" ;;
    esac ;;
esac

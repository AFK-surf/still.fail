#!/bin/bash
# What the app's builds weigh, in bytes, printed as JSON (mbui's scripts/size.sh with the shell's .so named).
D="$(cd "$(dirname "$0")" && pwd)"
MBUI_DIR=$(sh "$D/mbui.sh") || exit 1
export MBUI_APK_SHELL_SO=${MBUI_APK_SHELL_SO:-lib/arm64-v8a/libstillfail_shell.so}
exec bash "$MBUI_DIR/scripts/size.sh" "$@"

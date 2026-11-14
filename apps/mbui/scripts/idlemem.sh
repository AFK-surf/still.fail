#!/bin/bash
# The app's memory once idle (mbui's scripts/idlemem.sh).
D="$(cd "$(dirname "$0")" && pwd)"
MBUI_DIR=$(sh "$D/mbui.sh") || exit 1
exec bash "$MBUI_DIR/scripts/idlemem.sh" "$@"

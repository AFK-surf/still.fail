#!/bin/bash
# The C compiler for native tests on macOS (MOON_CC=scripts/cc_apple.sh): clang, and where it links, Apple's frameworks
# the hosts' Objective-C needs (src/host/apple_*.m, mac_app.m). A test package cannot carry cc-link-flags (only a main
# package can), so a test binary linking mbui/host would miss them (_objc_storeStrong, the MB* classes).
for a in "$@"; do
  [ "$a" = "-c" ] && exec clang "$@"
done
exec clang "$@" -framework Cocoa -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics \
  -framework ImageIO -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework WebKit

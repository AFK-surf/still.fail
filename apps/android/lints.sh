#!/bin/sh
# Whether a change is one Android's lint can find anything in: the changed paths on stdin, one a line; exits 0 when one is.
#   git diff --name-only <range> | sh apps/android/lints.sh
# Lint reads the app's own sources, resources, manifests and Gradle files (apps/android), the resources written from the
# words' catalog (client/i18n/catalog: app/build.gradle.kts, systemWords) and the native libraries it carries (the shell:
# client/shell, scripts/native.ts). Not the core's bytecode (client/core-ts, most of the app's changes): built and
# tested, not linted, and lint alone gets a stand-in for it (build.py). CI's check-android lint: 2-5 minutes, 2026-10-18.
grep -qE '^(apps/android|client/i18n/catalog|client/shell)/|^client/Cargo\.(toml|lock)$|^scripts/native\.ts$'

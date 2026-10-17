#!/bin/sh
# Whether a change is one Android's lint can find anything in: the changed paths on stdin, one a line; exits 0 when one is.
#   git diff --name-only <range> | sh apps/android/lints.sh
# Lint reads the app's own sources, resources, manifests and Gradle files (apps/android), and the resources written from
# the words' catalog (client/i18n/catalog: app/build.gradle.kts, systemWords). Not the rest of what the app is built
# from (apps/android/carries.sh): the core's bytecode and the shell's library are files it carries but cannot read, so a
# change to only those (client/core-ts, client/shell: most of the app's changes) is built and tested, not linted
# (CI's check-android lint: three to five minutes, 2026-10-18).
grep -qE '^(apps/android|client/i18n/catalog)/'

# The Android app in Kotlin: frozen (for agents)

Since 2026-10-23, as asked, this app is frozen: nothing in it changes. The stable channel keeps it at 0.1.4520; the
Android app that is developed is the mbui one, `apps/mbui` (its `AGENTS.md`), the beta channel's.

- Do not edit, add or regenerate anything here. A pull request that adds to `apps/android/` or changes a file in it
  fails CI (the pipeline's plan; `scripts/check.sh` says so on a commit too). Taking files out is let through.
- A change for the Android app goes in `apps/mbui`. What this app did (its sizes, radii, timings, behaviour) can still
  be read here as a reference; nothing builds, checks or compares it any more.
- Nothing outside this directory reads it either: the core's generators (`client/core-ts/scripts/shapes.ts`,
  `operations.ts`) and the icons (`apps/mbui/scripts/icons`) no longer write its Kotlin, and the mbui app's engine is
  its own (`apps/mbui/engine`).

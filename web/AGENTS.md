# Working on the web (for agents)

- The web runs the app: `mbui.html` and `src/mbui/` are mbui's web host drawing `apps/mbui` on a canvas, over the
  core in the tab's worker (`src/core/worker.ts`). A page people use is made in the app, once for every screen; the
  React web app's pages are gone (2026-10-31) and are not brought back here. What is left of the web's own is light
  and loads no app (`src/main.tsx`: signing in, Slack's way back, a service's way back to the vault, a station's web service on a page; `src/admin/`
  the operator's console), in Preact.
- No page makes a request of a station or the cloud: it names what it wants done (`src/core/operations.ts`, made
  from the core's `ops.ts`, not edited) and draws the topics the core keeps current.
- `ui/` (`@stillfail/ui`) is the design system and stands alone: nothing of `src/` (its core, station, cloud,
  preferences); the app gives it what it needs through its setters. `ui/src/palette.ts` is the one place still.fail's
  colours are written (the app's palette is made from it by `scripts/palette.ts`).
- `scripts/check.sh` holds the styles' rules (type sizes, weights, corners, hovers, margins, motion reduced read from
  the root, colours mixed in sRGB, no hand-written prefixes); its message says the way to write it.

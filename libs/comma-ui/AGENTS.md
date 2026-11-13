# Comma's parts in mbui (for agents)

A component library of its own beside mbui (`libs/mbui`), which it alone imports: Comma's design system (AFK-surf/Cue
`clients/packages/ui`, Figma `VnkgBb2xCr5bRp4KHrLrqs`) drawn by mbui. mbui is the framework and holds no look; a
library like this one holds the looks; an app uses a library (the user, 2026-11-13: mbui 和组件库应该分开). It started as
a sample of what mbui needs to carry a second design (the user, 2026-11-13: 先在 monoid 做样板).

- `src/cm` is the library, `src/gallery` every part on one page (`APP=gallery MBUI_APP_MOD=libs/comma-ui
  libs/mbui/scripts/mac.sh run`; `MBUI_DARK=1`; `MBUI_CM_FONT`: Inter's variable file). `scripts/check.sh` is its
  check, CI's `check-comma-ui`.
- The numbers are Comma's, never typed here: `src/cm/tokens_made.mbt` is written by `scripts/cm-tokens.mjs` from Cue's
  token modules (`node scripts/cm-tokens.mjs <Cue checkout>`), and a part reads them by name (`colors()`, `space_*`,
  `radius_*`, `type_*`, `ms_*`, `ease_*`). A value Comma's tokens lack is added there first, in Cue.
- A part takes its look from the Comma component of the same name (its `styles.ts`, its classes), and is read out as
  that component's role (react-aria's). Every part is a node of mbui's window's tree (`libs/mbui/src/view`), never an old view.
- What each part does with the hand (`src/cm/presses.mbt`) and how a look moves (`src/cm/eased.mbt`) are the same as
  still.fail's library's `presses_node` and `EdgeWay` (`apps/mbui/src/sf`), copied: they belong in mbui, without a
  look, shared by both libraries.
- mbui's rules hold here as in an app (`libs/mbui/AGENTS.md`): tests declare their moments, warnings are errors or off
  (`moon.mod`'s line), no Python.

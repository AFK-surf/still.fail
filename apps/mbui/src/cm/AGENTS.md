# Comma's parts in mbui (for agents)

A second component library beside `src/sf`: Comma's design system (AFK-surf/Cue `clients/packages/ui`, Figma
`VnkgBb2xCr5bRp4KHrLrqs`) drawn by mbui, as a sample of what mbui needs to carry a second design (the user,
2026-11-13: 先在 monoid 做样板). `src/cmkit` shows every part on one page.

- The numbers are Comma's, never typed here: `tokens_made.mbt` is written by `apps/mbui/scripts/cm-tokens.mjs` from Cue's token
  modules (run from `apps/mbui`: `node scripts/cm-tokens.mjs <Cue checkout>`), and a part reads them by name (`colors()`, `space_*`,
  `radius_*`, `type_*`, `ms_*`, `ease_*`). A value Comma's tokens lack is added there first, in Cue.
- A part takes its look from the Comma component of the same name (its `styles.ts`, its classes), and is read out as
  that component's role (react-aria's). It imports nothing of `src/sf` or the app (detlint's `library-import`).
- What each part does with the hand (`presses.mbt`) and how a look moves (`eased.mbt`) are the same as sf's
  `presses_node` and `EdgeWay`, copied: they belong in mbui, shared by both libraries, once a third use shows their shape.

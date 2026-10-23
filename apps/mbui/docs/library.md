# The component library (`src/sf`)

still.fail's design system for mbui, the counterpart of the web's `web/ui` (`@stillfail/ui`, docs/ui-package.md in the
repository's root): the tokens, the alignment, the icons, the motion, and the parts every page is made of. The phone's
pages (`src/sfapp`) and the desktop's take them from here: a part used by both lives here once, and both use it
directly; neither keeps a copy of its own.

## Its edge

- `src/sf` imports mbui and MoonBit's core library, nothing of the app: not its pages (`sfapp`), not the core client
  (`core`, `sfcore`), nothing of a station's or the cloud's (detlint's `library-import`, detlint.json `library`). Its
  tests may read the kept answers of the real core (`sfkept`).
- What only the app knows is given to the library as the app starts, as the web's host injects it: the keys of an
  action (`@sf.set_shortcuts`, the web's `setShortcuts`), the pictures by their address (`@sf.picture_of`); a word the
  library says for the app (a screen reader's name for a mark) is an argument (`@sf.about(…, label=tr("web-main.about"))`).
- A part draws from what it is given: a page reads the core and hands the part what it shows.

## One file for one of the web's

Each file here is one of `web/ui/src`'s, named after it; a part the web has in `parts.tsx` is in `parts.mbt`. A part
missing here is ported from the web's file (its structure, its states, its values: not measured off a picture of it).

| `web/ui/src` | `src/sf` | |
|---|---|---|
| `styles/tokens.css.ts` (and the values in `web/src/styles/global.css.ts`, the phone's in `mobile/styles/root.css.ts`) | `tokens.mbt` | |
| `styles/align.ts` | `align.mbt` | `Surface` (`surface`, its `corner`, `inner`, `style`), `inner_or`, `surface_corner`, `pill_inner`, `bleed_x` / `bleed_start` / `bleed_end` / `bleed_y`, `in_line`, `columns`, `into_column`, `centred*`, `overlap`, `outset*`, `oversize`, `neg`, `edge_row`, `panel_pad`, `text_in`, `panel_pill`, `small_panel_inner` (panelText is parts.mbt's `panel_text`); with mbui's smooth corners the web's `calc(inner + pad)` is `concentric_out` and its `calc(outer - pad)` is `inner_corner`, a circle in a corner `around` |
| `styles/glass.ts` | `glass.mbt` | |
| `styles/controls.css.ts`, `styles/page.css.ts` | `parts.mbt`, `styles.mbt` | |
| `parts.tsx`, `parts.css.ts`, `own.css.ts` | `parts.mbt` | Button, IconButton, Tip, About, Field, Segmented, Choices, Switch (`switch`, and `switch_look` for a row that takes the tap), SwitchRow, Select, Pill, StatusDot, Dialog, Confirm, the small panel and its parts (PanelHead, PanelGroup, PanelRow: `menu_item(panel=true)`, PanelNote, PanelFoot, PanelText, PanelButton, PanelIconButton), Menu and its items, CopyCommand, Chooser, Empty, FirstOne, Section; ResizeHandle is still the pages' (the sidebar's edge, `sfapp/wide.mbt`; the files' columns', `wide_files_columns.mbt`: the web's own SidebarEdge and ColumnEdge look as it does) |
| `waiting.tsx`, `waiting.css.ts`, `styles/spinner.css.ts` | `waiting.mbt` | Spinner, WaitPill, WaitLine, WaitNote, WaitShapes (rows, messages, cards), Waiting, WaitMore, Progress, the placeholders' breath; the phone's and the desktop's lists, chats and settings wait with them. The pill over a picture (`pillOver`: the preview's, a screen's) is still the pages' |
| `styles/spokes.ts` | `icons.mbt` | |
| `Avatar.tsx` | `avatar.mbt` | |
| `icons.tsx` | `icons.mbt`, `icon_data.mbt` | made by `scripts/icons` from `design/icons` |
| `strokes.ts` | `stroke.mbt` | |
| `fileSize.ts` | `file_size.mbt` | |
| `shortcuts.ts` | `shortcuts.mbt` | |
| `motion.ts`, `styles/keyframes.css.ts`, `styles/still.ts` | `motion.mbt` (EASE_OUT, ENTER, LEAVE, MOVE, GLIDE_*, LOCAL_MS), mbui's `@motion` and `Ctx::move_state` (moveState); `parts.mbt` `pop_in` (popKeyframes) | |
| `toast.tsx`, `toast.css.ts` | `toast.mbt` (`toast_look`, `toast_said`, `toast_ms`) over mbui's `@kit.toaster` | the desktop's toast; the phone keeps its own (the web's ToastTo) |
| `i18n.ts` | | the words are the app's (`sfapp` `tr`, `fill`) |
| `viewer/` (ViewerBar, Reader, Player, media) | | still the app's: `sfapp/viewer_bar.mbt`, `reader_desk.mbt`, `drive_reader.mbt`, `src/player`, `play_desk.mbt` |

Besides the web's: the Markdown of messages (`markdown.mbt`, `md_core.mbt`: the core's tree drawn), code's colours
(`ink.mbt`), formulas (`math.mbt`), the station glyph (`glyph.mbt`), Android's drawables (`picture.mbt`), the phone's
page bar (`nav_bar.mbt`), the fonts (`faces.mbt`).

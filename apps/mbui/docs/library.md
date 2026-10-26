# The component library (`src/sf`)

still.fail's design system for mbui, the counterpart of the web's `web/ui` (`@stillfail/ui`, docs/ui-package.md in the
repository's root): the tokens, the alignment, the icons, the motion, and the parts every page is made of. The pages (one
for every tier: docs/architecture.md) take them from here: a part used by both lives here once, and both use it
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
| `parts.tsx`, `parts.css.ts`, `own.css.ts` | `parts.mbt` | Button, IconButton, Tip, About, Field, Segmented, Choices, Switch (`switch`, and `switch_look` for a row that takes the tap), SwitchRow, Select, Pill, StatusDot, Dialog, Confirm, the small panel and its parts (PanelHead, PanelGroup, PanelRow: `menu_item(panel=true)`, PanelNote, PanelFoot, PanelText, PanelButton, PanelIconButton), Menu and its items, CopyCommand, Chooser, Empty, FirstOne, Section, ResizeHandle (`resize_handle`; its parts `handle_drag`, the press and the drag, and `edge_look`, the look the web's SidebarEdge and ColumnEdge share), usePointerTip (`edge_tip`) |
| `waiting.tsx`, `waiting.css.ts`, `styles/spinner.css.ts` | `waiting.mbt` | Spinner, WaitPill, WaitLine, WaitNote, Waiting, WaitMore, Progress, the breath. As the web's `Bones` (bones.ts measures the page's own parts drawn of made-up data), what will come in its bones (`bones`, @ui's Ctx::bones): the page's own rows, messages and cards drawn of made-up words (`sample_words`), so their outline is theirs; a whole page's in page.mbt's `page_waiting`. The pill over a picture (`pillOver`: the preview's, a screen's) is still the pages' |
| `styles/spokes.ts` | `icons.mbt` | |
| `Avatar.tsx` | `avatar.mbt` | |
| `icons.tsx` | `icons.mbt`, `icon_data.mbt` | made by `scripts/icons` from `design/icons` |
| `strokes.ts` | `stroke.mbt` | |
| `fileSize.ts` | `file_size.mbt` | |
| `shortcuts.ts` | `shortcuts.mbt` | |
| `motion.ts`, `styles/keyframes.css.ts`, `styles/still.ts` | `motion.mbt` (EASE_OUT, ENTER, LEAVE, MOVE, GLIDE_*, LOCAL_MS; --dur, copied, woken and resting, the breath), mbui's `@motion` and `Ctx::move_state` (moveState); kit's `pop_in` (popKeyframes), `tip_in`, `dialog_in` | |
| `toast.tsx`, `toast.css.ts` | `toast.mbt` (`toast_look`, `toast_button`, `toast_said`, `toast_ms`) over mbui's `@kit.toaster` | every frame's toast, the frame saying only where (the narrow one's over its bar); its button (an archive's 撤销, which the web's has not) a capsule concentric with its end |
| `i18n.ts` | `i18n.mbt` | `t`: the catalog's words as the app says them (`set_words`, its `fill`, told as it starts) |
| `viewer/ViewerBar.tsx`, `ViewerBar.css.ts` | `viewer_bar.mbt` | the bar, its tools, download; `BarOnScroll` (useBarOnScroll) |
| `viewer/host.ts` | `viewer_host.mbt` | `set_viewer_host`: what the viewers ask of the page (the app's `sfapp/viewer_host.mbt`, as the web's `web/src/viewer/whole.ts`); the theme is the library's own, so no `useDark` |
| `viewer/file.ts` | `viewer_file.mbt` | a file a viewer opens (the app's drive file: `sfapp/drive_viewer.mbt`, the web's `drive/viewerFile.ts`), `blob_file` |
| `viewer/readerStyle.ts` | `reader_style.mbt` | |
| `viewer/Reader.tsx`, `Reader.css.ts` (and `decode.ts`) | `reader.mbt`, `reader_text.mbt` | the column, its state, the desktop's bar and panels; `reader_text.mbt` the book as laid out (blocks a list lays out one at a time, the indent), the text decoded by the host's tables (`@hostapi.decode_text`). The phone's is the web's narrow one: its bars over the column, its contents, find and layout in the page's sheets (the host's `sheet`) |
| `viewer/Player.tsx`, `Player.css.ts` (and `rest.ts`, `subtitles.ts`) | `player.mbt` | the one player of films and songs, a drive's and a chat's (`sfapp/preview.mbt` shows it too): the source, the place, the subtitle (`@codec.parse_subtitles`), the frames (stepped one at a time, the timeline gone along frame by frame), the speeds, the frame saved; a desktop's view and a phone's (its gestures, its sheet of the others) |
| `viewer/media.css.ts` | `media.mbt` | the controls' bar, timeline, keys and speed; a film's dark ink (`media_ink`) |
| `viewer/names.ts` | `names.mbt` | |

Besides the web's `web/ui`: what a search found as its rows show it (`marked.mbt`: the web's `Marked.tsx`, the words found marked, `found_line`; a row's meta, `join_meta`; each kind's icon, `kind_icon`), the Markdown of messages (`markdown.mbt`, `md_core.mbt`: the core's tree drawn), code's colours
(`ink.mbt`), formulas (`math.mbt`), the station glyph (`glyph.mbt`), Android's drawables (`picture.mbt`), the phone's
page bar (`nav_bar.mbt`), a way to where something is (`way.mbt`: the web's crumbs, its steps leaving for a … short of room), a sidebar's rows (`side_rows.mbt`: the web's `Sidebar.css.ts` navRow, navNew, navScroll and `SidebarList.tsx` NavItem, NavAction; a row's ground as it moves, `nav_ground`), the fonts (`faces.mbt`), a linear gradient's ground (`gradient.mbt`: a small picture of it stretched over
the box, for the notifications page's preview screen, until mbui's renderer fills gradients itself).

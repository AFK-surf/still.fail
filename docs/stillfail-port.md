# still.fail in mbui: the plan

The user, 2026-10-19: "开始直接复刻原生 still.fail 吧，之后两路并行，在合适的时候
再切过去". The native still.fail (ember `apps/android`, Kotlin/Compose, about
51k lines and 12k of tests; mapped in docs/stillfail-android-map.md) is built
again on mbui, page for page, installed beside the current app (its own
package id, `fail.still.mbui`), until it does all the current one does as well
or better; then the release switches over. The current app keeps shipping
meanwhile.

## What stays the same

- The core: still.fail's TypeScript core (client/core-ts) with its Rust shell
  for IO, as the current app runs it. On Android in Hermes (the prebuilt
  `engine` and `shell` parts: `node scripts/native.ts path engine
  android-arm64`), on Apple in JavaScriptCore (src/coredemo already does),
  later on Windows. The protocol is the one src/core speaks (docs/client-core.md
  "Protocol": calls, keyed topics with deltas, `secure.*` and `listen.*` asked
  of the host).
- The design: src/sf, from the web's tokens and ui-panels rules, which the
  Android app follows too (docs/mobile-parity.md: the narrow web is the
  reference).
- The data's shapes: generated from core-ts (`src/shapes/schema.ts`, as
  Shapes.kt and Operations.kt are), not written by hand.

## What mbui needs first (framework)

1. Rich text: runs with their own weight, slant, colour, size, code face and
   links in one paragraph (Markdown, messages, tool steps).
2. A page stack: pushed pages sliding in, the edge swipe and predictive back,
   each page keeping its scroll and its followed topics.
3. Bottom sheets (55% / 94% / fitted, dragged by the grabber), the long-press
   menu, toasts.
4. Squarer corners (the web's superellipse at 1.25×) in the renderers' shader;
   frosted glass (a blurred copy of what is under a bar) as a render pass.
5. A list that follows its newest end (the chat), with the web's list motion.
6. Fields: multi-line composer with IME, selection and the keyboard's insets
   (the editor has most of it).

Done (branch fw-richtext-nav, 2026-10-19):

- 1, rich text: `Ctx::rich(runs)` (src/ui/rich.mbt): runs with their own
  weight, slant, code face (monospace on a tinted ground, or still.fail's
  inline code: its own colour, no box), size, colour, strikethrough,
  underline and links (pressed, tapped: `on_link`), wrapped as one text
  (UAX #14 over the whole paragraph). Hosts shape and measure by run: a
  `style` (italic, mono) beside size and weight on every host. The layout
  answers offsets, carets and a range's rects, for selection later.
  src/md parses Markdown; `@sf.markdown` draws it as a message does
  (Markdown.kt). Not yet: tables, code highlighting, a code block's sideways
  scroll, a link's long-press menu, selection itself.
- 2, the page stack: `Nav[P]` and `Ctx::nav` (src/ui/nav.mbt), App.kt's
  Pages: push/pop sliding side by side (300 ms, standard curve), the left
  edge's swipe and the system's back gesture (`@host.set_back`; Android's
  OnBackAnimationCallback) following the finger, going on or coming back as
  App.kt does; pages under the top keep their widgets' state, forgotten when
  they leave (`on_leave` for what the app keeps, as followed topics). Not
  yet: Settings' slide from the left, a new chat's rise, the bar's place
  switch.
- The demo's kit screen shows both: `MBUI_SCREEN=kit` (`?MBUI_SCREEN=kit`),
  `scripts/shots.sh kit web-kit`.

Slice 3, Home (branch home-list, 2026-10-19): `APP=stillfail` (src/stillfail) is
still.fail itself, beside the demos. It starts the core as src/coredemo does
(both on src/sfcore now: the core's start, signing in, the engine's glue for
Apple and Android), shows the sign-in page signed out (SignIn.kt) and
otherwise Home at the root of a `@ui.Nav` (src/sfapp, Home.kt and its parts):

- The top bar: settings, the workspace's name (24 bold) with its mark (the
  other workspaces' `workspaceMarks.others`, or the invitation dot) and ▾,
  the filter (全部 / 我参与的 / 监控中, kept as the prefs' `listFilter`; 已归档).
- The list: the `chats {scope, mine, watching}` view as it is, its days
  (SectionHeader) and rows (66 high: the state mark, the title bold while
  unread, the station's mark, unplugged or Slack; where it stands, with
  要你帮忙 / 做完了 / 在等 / 监控中 as icons and 奏 bold, or the last message;
  the agents' makers' marks and the people's faces, RowPicture.kt); the time
  (`time.lastActiveAt.ago`) while a row is held; 归档 at a done row's start
  (`chat.archive`); the search field at its top; while it is read, the rows to
  come breathing (WaitShapes), what is wrong over them; the empty list's and
  the first station's illustrations.
- A row tapped pushes its chat (its bar only: slice 4 fills it), swiped back
  from the left edge.
- The workspace's name opens the workspaces' sheet: the one in use, the others
  with what each has waiting (MarkCounts); one tapped is the one in view (the
  prefs' `workspace`); 登录其他账号.
- src/sf draws the Android app's own pictures now (src/sf/picture.mbt over
  drawable_data.mbt, which scripts/drawables.py makes from ember's
  res/drawable and ui/Icons.kt): the makers' marks, Slack's, still.fail's
  mark, the illustrations and the 314 station glyphs.
- `APP=sffix` (src/sffix) is the same Home over made-up chats in the core's
  shapes (src/sfapp/fixture.mbt), no core: `scripts/shots.sh home web-home`
  compares it with goldens/mac-home*.png and web-home.png.

Not yet, against the current app: the bottom bar (slice 7: 奏 N and 令 in
it, so no new-chat button here), the frosted glass (the top bar is the page's
ground at 94%), the search page, the long-press menu (pin, rename, copy link)
and swiping a row away, the rows' motion as the list changes, the open jobs
banner and the changelog's note, pull to refresh (the app has none either),
the update button, inviting and new workspaces in the sheet, English (the
words are the Chinese catalog's), avatars' pictures on Android (no image
decoding there yet), `client.focus`, and picking the first workspace into the
prefs at start (only a switch made here writes them).

## What the hosts need (platform)

Hermes + shell on Android; secure storage with biometrics (`secure.*`);
browser sign-in and deep/app links; notifications and FCM; photo/file pickers
and the camera; share in and out; clipboard (there) and haptics; a native view
over the canvas for WebView (previews, visualizations) and for video (shared
with the media app's player); PDF pages as images; self-update.

## Order (each a slice that runs end to end, beside the current app)

| # | Slice | About (Kotlin lines it replaces) |
|---|---|---|
| 0 | Android host runs the core (Hermes + shell), the shapes generated | 900 |
| 1 | Framework: rich text, page stack, sheets, corners | — |
| 2 | Sign-in (browser, deep link), workspaces | 600 |
| 3 | Home: the chats list, rows, marks, the top bar | 1.2k |
| 4 | A chat, read: messages, Markdown, files, following its end | 3k |
| 5 | The composer, sending, drafts, attachments | 1.5k |
| 6 | New chat becoming its chat | 1.2k |
| 7 | The bottom bar, glass, sheets in use | 1.7k |
| 8 | Decisions, history, tool steps, a chat's sheets, jobs | 2.5k |
| 9 | Settings home and the list pages (me, appearance, usage, archive…) | 2k |
| 10 | Notifications and pushes | 300 + host |
| 11 | File preview: images, PDF, video, HTML | 2.5k |
| 12 | Drive, reader, player (shared with the media app's) | 3.5k |
| 13 | Stations, profiles, connects, vault, security, workspace, memory | 6.5k |
| 14 | Web previews, remote screens, adb lending, share sheet, updates | 4.5k |

Every slice is checked against the current app side by side on the same
account (screenshots of both on the emulator), and runs in CI (ci.yml) on
every push.

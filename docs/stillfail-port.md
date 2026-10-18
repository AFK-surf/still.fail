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

Slice 4, a chat read (branch chat-read, 2026-10-19): a row pushes its chat
(src/sfapp/chat.mbt, messages.mbt over the core's `chat {station, session}`
view, chat_model.mbt; Chat.kt ChatScreen and Messages, Prose.kt,
ChatFiles.kt, Decisions.kt, LoginCards.kt, Follow.kt):

- The bar: back, the title, its people (PeopleStack), its agents' marks, the
  first one's tile carrying the station it runs on (the `stations` topic:
  its mark and how it is reached), the archive button while nothing is left
  in it, the jobs' button when it has some, "…"; the page's ground at 94%
  with a hairline under it, the messages running under it.
- The messages: still.fail's notices as pills (a failing one red; tapped,
  all its words and its time), the viewer's words in bubbles on the right
  (sent close together, 4 apart; quotes as cards ahead of them), anyone
  else's under their picture, name and time (a tap on a time says when, in
  all of them), a person's words with references to other chats as
  `@title` in the accent and bare addresses as links, an agent's as
  Markdown (`@sf.markdown`, which now draws chat references and places a
  message's files where its text names them), files as cards and images in
  boxes of their own proportions before they load (their ThumbHash
  likeness meanwhile, `station.file` with `thumb`), videos as their boxes
  with the play mark, what went to Slack, options cards (who is to decide,
  the options, 忽略), login cards (the `machineLogin` topic), 保留 / 归档此对话
  under the last all-done post, the unread line, the activity line of an
  agent at work (the `live` topic), the outbox. The words are the Chinese
  catalog's. Times are the core's (`time.createdAt.ago`); the Android app
  has no day separators in a chat, so neither has this.
- The list (`Ctx::list` with `stick_end`): it opens at its end (or at the
  unread line with a few lines before it, or where the core says it was
  left: `at`, `atOffset`), follows the newest while it is at its end, and
  over the composer's room shows the way to the newest (↓, with how many
  wait when the window is short of the chat's end) once it is more than a
  corner of the screen away; tapped, the list glides back
  (`Ctx::list_to_end`). Near its top the page before comes in (`chat.older`,
  once a page) and what is in view stays where it is (`Ctx::list_moved`:
  the rows that came above, or under the spinner the first message kept in
  place); near the end of a window short of the chat's, `chat.newer`.
- While the chat is read: its bar, the messages to come breathing, the
  composer; what could not be read over them in red.
- The composer is the next slice's: its capsule is drawn (＋, 发消息, send),
  taking nothing.
- What the reader does is told to the core as the app does
  (`client.focus` with the chat and whether its end shows, which marks it
  read; `left` and `chat.place` as it is left), except with
  MBUI_READONLY=1 (Source.read_only): runs on a real account change nothing.
  MBUI_OPEN_CHAT (words of a title, or `#n` the n-th row),
  MBUI_OPEN_SESSION and MBUI_CHAT_AT_END open a chat for scripted runs;
  MBUI_CHAT_BENCH=1 scrolls it up 600 frames and says the frames' times.
- Scrolling (MBUI_CHAT_BENCH, Studio, 390×844, 600 frames at 40 a frame,
  build + layout + paint): the made-up chat of 3000 messages 0.34–0.57 ms a
  frame on average (p99 0.8–2.5 ms, none over 8 ms); the long real chat
  (its 151 messages, every page brought in) 0.58–0.71 ms (p99 under 4 ms,
  none over 8 ms). Only the rows in view are built; the views are read once
  a version, Markdown parsed once a text.
- `APP=sffix MBUI_FIXTURE=chat` opens a made-up chat with every kind of
  message (src/sfapp/chat_fixture.mbt; `chat-loading`, `chat-long` with
  3000 messages): `scripts/shots.sh chat web-chat` compares it with
  goldens/mac-chat*.png and web-chat.png.

Not yet, against the current app: sending, the composer and drafts (slice
5); answering cards, letting go, archiving and keeping from the chat (the
buttons are drawn, inert); the long-press menu, quoting and picking words;
the file preview (slice 11) and opening links outside the app; tables and
code highlighting in Markdown, a code block's sideways scroll; the messages'
motion (rising in, coming out of an agent's avatar, the activity's glide and
its floor); a new message followed from its top when it is taller than the
screen; the asks' bell; the chat's sheets ("…", the agent's card, jobs);
images on Android (no decoding there yet: their boxes and likenesses only);
the station's update control in the bar; the frosted glass.

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

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
- The composer is the next slice's (below).
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

Not yet, against the current app: answering cards, letting go, archiving and keeping from the chat (the
buttons are drawn, inert); the long-press menu and picking words;
the file preview (slice 11) and opening links outside the app; tables and
code highlighting in Markdown, a code block's sideways scroll; the messages'
motion (rising in, coming out of an agent's avatar, the activity's glide and
its floor); a new message followed from its top when it is taller than the
screen; the asks' bell; the chat's sheets ("…", the agent's card, jobs);
images on Android (no decoding there yet: their boxes and likenesses only);
the station's update control in the bar; the frosted glass.

Slice 5, the composer (branch composer, 2026-10-19): the chat's composer takes
words and sends them (src/sfapp/composer.mbt; Composer.kt ComposerBar,
DraftExtras, Drafts, upload; ChatHost.kt HostComposer; Attach.kt;
PastedText.kt; SendText.kt; MessagePick.kt):

- The capsule: ＋, a field that grows with the words up to six lines (16 on
  21, 发消息), the round send button (faint while nothing can go, ink once
  something can; nothing goes while a file is still going up). Focused or
  holding something it opens: the field the whole width, the buttons under
  it. Enter is a new line, as the Android app's field has it (the soft
  keyboard shows its return key; no key sends). Composition (Chinese input)
  as mbui's editor has it on every host. A tap on the list lets go of the
  keyboard.
- What waits to go, over the field: quotes (each a card with a line for a
  comment, which takes the focus; its Enter goes back to the words), pictures
  as 56 tiles (a spinner while they go up, 失败 when they did not), a long
  paste (5000 characters or more at once) as its card (its first line, so
  many 字符, 展开到输入框 / 重试上传), any other file as a card (正在上传 n% ·
  size). Files go up as soon as they are added (`station.upload.part`, 4 MB a
  part, bytes beside the call: `@core.call(bytes=)`), an image's size read
  from its bytes going with it.
- Drafts: each chat's (`<station>:<session>`), kept by the core on the device
  (`draft.get` as the chat opens, `draft.put` 0.4 s after a change and as the
  chat is left) and put back when it is opened again.
- Sending: `chat.send` by the chat's thread (or its session before it has
  one) with the words, the files up and the quotes; the composer empties at
  once and the list goes to its end; the message shows from the outbox
  (正在发送 under it), and a failed one says 未发送 (a tap says why) with 重试
  (`chat.retry`) and 删除 (`chat.discard`). Refused before the outbox
  (`invalid_params`), the words come back and why is said under the field.
  Typing wakes the agent's runtime (`session.warm`, once a minute). An
  archived chat's composer says so with 还原对话; an offline station's says
  it cannot send.
- ＋'s sheet: the camera tile and the gallery's tile across the top, then
  照片, 文件, Station 文件. 照片 is the system's photo picker
  (ACTION_PICK_IMAGES; the documents UI on images where there is none) and
  文件 its documents UI (ACTION_OPEN_DOCUMENT) on Android, the open panel on
  macOS (`@host.pick`, src/host/pick.mbt; Picks.java); the camera tile takes
  a photo on Android (ACTION_IMAGE_CAPTURE's picture, as the app's
  TakePicturePreview). Not yet (the same tiles, a toast saying so): the
  recent photos (they need the gallery's permission and its thumbnails),
  Station 文件 (slice 12's drive), any picker on iOS, Windows and the web.
- Quoting: a message's words held still half a second are picked (all of
  them: the Android app picks a word and widens it by words, with handles),
  a bar over them with 引用 (into the draft as a quote) and 复制.
- The soft keyboard (Android): MainActivity follows its insets as they move
  (WindowInsetsAnimation), MBView lays the app out above it without
  resizing the surface, so the composer rides on the keyboard as it comes and
  the list keeps its end in view. Paste: the keyboard's paste, KEYCODE_PASTE
  and the context menu's paste put the clipboard's words in.
- MBUI_READONLY=1 refuses every call but the reads (and the device's prefs)
  in src/stillfail itself: nothing is sent, no draft kept, no file put up,
  whatever page asks.
- `APP=sffix` takes what is sent as a station would (the outbox, the message,
  a made-up answer; words with 失败 fail first and go on 重试), keeps drafts
  while it runs and takes files at once. MBUI_FIXTURE=chat-compose,
  chat-attach, chat-quote, chat-sending, chat-failed open the chat with its
  composer so: `scripts/shots.sh composer web-composer` compares them with
  goldens/mac-composer-*.png and web-composer-*.png.

Not yet, against the current app: the words flying from the field into their
bubble (and the capsule's morph as it changes height), `@` references to
other chats and pasted chat links as marks (chat.ref, chatSearch), sharing
what they refer to before sending, the recent photos' strip, Station 文件 (slice 12's drive, below), a
picture's preview from its tile, files pasted or sent by the keyboard (only
words are), the composer's frosted glass, the text toolbar of the field
(select, cut, copy by touch; the keyboard's own paste works), a new chat
(slice 6).

Slice 12 without the player, the drive and the reader (branch drive, 2026-10-19; ember apps/android drive/Files.kt,
DriveScreen.kt, Reader.kt, TextModel.kt, Novel.kt, ReaderMarkdown.kt; chat/screens/StationFiles.kt):

- 文件 (src/sfapp/drive.mbt `files_page`, Page `Files`): every station's folders lent under its name (`stations`
  topic, Overview.drive), its home first (主目录) for a member who browses every folder, a station away faint and
  said so (· 离线); its ＋ (owners and admins) lends another through the folder picker (`drive.folders`: the way as
  crumbs, a filter, the usual places at the home, a folder the station may not read said so; `drive.setRoots`).
  Pushed it has a bar with back and ＋; `files_page(…, place=true)` draws it as a place of the bottom bar (Home's top
  bar), `files_can_lend` / `files_lend` give the bar's notch its ＋ (branch newchat-bar links it).
- A drive's page (Page `Drive(DriveAt)`, `drive_page`): the drive itself with several roots as rows (one that
  cannot be browsed in red with what to do; held, stop lending it), or a folder (`drive` topic): back to where it was
  opened from, its name, 刷新 (`drive.refresh`), ＋ (上传文件, 新建文件夹, the folders lent), ⋯ (its order and
  hidden files, prefs `driveViews`); the crumbs; what it holds in a line; the files going up; its entries as one
  card (kind's mark, name, size · time; how far a text was read; a folder's chevron), folders first. A folder goes
  in (a page pushed: the stack's slide and edge swipe), text and Markdown are read, anything else goes to
  `open_file` (src/sfapp/open_file.mbt, the file preview's: branch preview fills it in; until then it says
  暂时无法预览). Held, a row is chosen (others by a tap; 已选 n 项, 全选, ⋯): one renamed (the ask sheet,
  `drive.rename`), downloaded, shared, its path copied, deleted (to the machine's trash where the station has one,
  said so; else asked, then for good: `drive.remove`); several downloaded, their paths copied, deleted. Uploads go
  one at a time whatever page shows, each a row of its folder (`drive.upload.part`: a quarter of a megabyte first,
  doubling to 4 MB while parts go through; a name taken asked in the row: 替换 or 保留两者; failed: 重试).
- The reader (Page `DriveRead(DriveAt)`, src/sfapp/drive_reader.mbt over drive_text.mbt): the file read through
  the core a part at a time (`drive.read`, bytes beside the answer: Source.read_bytes), 16 MB at most, how much has
  come shown; decoded (a byte order mark, UTF-8, a character cut at the end dropped), a hard-wrapped novel reflowed
  into paragraphs, chapters found (第…章, front matter, Chapter N, title-like lines; Markdown's headings), cut into
  blocks of about 1000 characters that a list lays out one at a time, paragraphs indented by two ideographic spaces.
  One column that scrolls; a tap brings the bars (the paper's bar colour at 72%, 180 ms): the top one back, the
  name and the chapter; the bottom one 上一章 / 下一章, the hairline with its knob (the text goes there when let
  go), how far, 目录 / 搜索 / 排版. The contents (the chapter read checked), search (as it is typed: each hit a line;
  the pill steps through them, hits marked on the text), the layout (字号, 行距, 边距, 字体, 缩进, the five papers;
  the core's prefs `reader`). Where it was left is told to the core as the reader stops and as the page goes
  (`drive.place`; the drivePlace topic) and opened at next time; the folder's row says how far (n%, 读完).
  src/shelf's reader (the media app's books) is paged; Reader.kt scrolls, so this one is its own; it shares @sf's
  slider, segmented control, wait pill and progress bar.
- Station 文件 (src/sfapp/station_files.mbt, ＋'s sheet in the composer): the places, a folder entered by a tap, the
  way back as crumbs; files ticked (or the folder shown as a whole), 添加 n 个: each a card in the draft (outlined:
  it stays where it is), and the message says where in a line each (`common.pathOn`: Studio 上的文件：/…).
- `APP=sffix MBUI_FIXTURE=files|drive|drive-sub|drive-chosen|drive-entry|drive-upload|drive-empty|reader|reader-bars|
  reader-contents|reader-layout|reader-md|chat-station-files|chat-station-ref` (src/sfapp/drive_fixture.mbt, a
  made-up drive that takes renames, deletes, new folders and uploads while it runs): `scripts/shots.sh drive
  web-drive` compares them with goldens/mac-<mode>.png and web-<mode>.png.

Not yet, against the current app: the player (the rest of slice 12), downloading a file to the device, sharing it
to another app, a folder as a zip (each says so in a toast: no host API to keep a file yet), GB18030 text (no
table here: such a file opens as UTF-8 with replacement characters), the serif face (the reader draws its sans
face either way), 跟随's swatch drawn half and half on a diagonal (here the dark page as a disc in the light one),
the system bars' icons following the paper, the frosted glass of the bars and sheets (their tint only), the
system's back closing a sheet or ending a choice (it goes back a page), dragging sheets by the grabber, the
long-press ripple, a station file sent as a file (`drive.stage`, the card's sheet, 此对话默认发送文件) and station
files kept with the draft on the device, the station page's way into a drive (slice 13).

## Checked end to end, against a still.fail of its own (branch e2e-local, 2026-10-19)

`scripts/e2e-local.sh all` runs the app (APP=stillfail) through what the slices do, against a still.fail that lives
only on this machine, never the real account: ember's local cloud (cloud/test/dev.ts: its Workers in Miniflare,
Google mocked, the test identities, alice in the workspace "Dev"), an iroh-relay of its own (dev mode, loopback), and
a test station enrolled there from a clone of ember (built in it, never in ember-src), its agent ember's fake claude
(station/test/fake: it answers `post:<words>` with those words through the agents' door, as an agent's chat_post).
Every part has its own ports (E2E_PORT, the cloud from 18787 to 18792; E2E_RELAY, 18740) and directories (E2E_WORK,
e2e-local beside the checkout; the station's data and HOME under /tmp/mbui-e2e-<uid>, short, as its runners' sockets
need); the station starts with what the shell has of the machine's own station (EMBER_*, STILLFAIL_* …) taken out.

- `up` clones ember (or brings the clone to ember-src's commit), installs and builds it once, starts the relay, the
  cloud and the station (each in a session of its own: they outlive the task that started them until `down`), enrolls
  the station with the cloud's printed token, and has alice's other device (e2e/peer.ts: ember's TS core in Node, on
  the station's mesh addon, signed in with the cloud's mock account) make the test chat; it writes
  `<work>/run/e2e-env.sh`: MBUI_CLOUD and the account (MBUI_CORE_ACCOUNT_B64, from /__dev/account?user=alice).
- The app takes them: MBUI_CLOUD=<origin> is the cloud it starts its core on (src/sfcore; Android logs "cloud
  http://127.0.0.1:18787"), and MBUI_CORE_ACCOUNT (or _B64), only with MBUI_CLOUD, is taken in as signed in (the
  core's `migrate`, as the web app's accounts were) when none is. e2e/run.sh takes a fresh one from the cloud for each run: a
  sign-in's refresh token goes once, so a copy another core has refreshed is used up. The browser sign-in itself is not run: the local
  cloud's Google is mocked only for its own tests (a browser would be sent to the real Google).
- The flows are scripts for src/ui/drive.mbt (MBUI_DRIVE, or MBUI_DRIVE_B64): a step a line, finding what to tap by
  its words on screen (`tap 发消息`, `icon:arrow-up`, `=重试` for words that are exactly so), waiting on what should
  come (`until`, `untiln 2 …`, `gone`, `field` for a field's words), typing through the system's own ways (`mark`
  and `type`: on macOS the input method's setMarkedText and insertText; on Android the view's InputConnection;
  `paste`: the clipboard and Cmd+V, KEYCODE_PASTE), shots (`shot`), and `log do: …`, which has the runner do
  something beside the app (`peer send …`, `peer create …`, `freeze` / `thaw` the station, `reads`). It runs on any
  host; `Tester::drive` runs a script in tests.
- e2e/run.sh runs each flow (e2e/flows/NN-name.drive) in the app, in order, on one sign-in, then its check
  (NN-name.check) against the backend's own state, not the screen: the station's database (entries: the words, the
  author, the attachments' and quotes' JSON; reads: how far alice has read), the files it keeps (the photo and the
  9 MB file the same byte for byte; the long paste's 18000 bytes), the core's store on the device (drafts), and prints
  PASS or FAIL per flow (out/e2e/<platform>.txt; shots in out/e2e/<platform>/<flow>/). `scripts/e2e-local.sh mac`
  runs the flows against what `up` started (E2E_NOBUILD=1: the app as built), `android` the same on an emulator of
  our own (AVD=mbui-avd-e2e EMU_PORT=5586 by default: adb reverse brings the cloud's and the relay's ports to the
  emulator's 127.0.0.1, the files to attach go into the app's own files, MBUI_PICK_FILES answers the pickers, each
  flow recorded with screenrecord). `down` stops all of it.

To check a later slice the same way: add its flows and checks to e2e/flows, and what the runner must do beside the
app to `scripts/e2e-local.sh` (as `peer`, `freeze`, `reads`).
A flow's `#env K=V` lines are put in the app's environment for that flow (the drive's flows start on 文件 with
MBUI_OPEN_PAGE=files until the bottom bar reaches it). Before the flows, `scripts/e2e-local.sh drive-seed <tag>` makes
the drive flows' folder in the test station's home (e2e-<tag>: a text, a novel of made-up chapters, a folder with a
file), a run's own, which flow 15 lends through the app.

The flows (macOS, 390×844, and Android on the emulator, Pixel 7 size). On 2026-10-19 all 14 passed on macOS; on
Android 13 of 14 in the full run and 11 (the quote) alone, twice, once it waited for the all-done card (it had held
while the card moved the list):

| Flow | What the app does | Checked on the backend's side |
|---|---|---|
| 01 signin | signed in with the mock account; Home lists the test chat, the agent's answer as where it stands | the core's store holds alice's sign-in |
| 02 home-new-chat | on Home while alice's other device makes a chat: its row comes in, then its agent's answer as the row's last words | the station has the second chat and the agent's answer in it |
| 03 send-text | a chat opened from Home, words typed and sent (正在发送, then sent) | the station's entry: the words, once, as alice's |
| 04 chinese-enter | Chinese composed and committed through the input method, Enter a new line, sent | one entry of both lines; none of the first line alone |
| 05 agent-reply | a question; the fake agent's answer comes while the chat shows, the list following its end | the agent's entry; the answer shown in the window |
| 06 draft | words left in the field, the chat left and opened again: they are back | the draft in the core's store on the device, nothing of it at the station |
| 07 draft-restart | the app started again: the draft is back; emptied | the core keeps no draft of it any more |
| 08 paste-short | a short paste (Cmd+V, KEYCODE_PASTE) goes into the field, sent | the entry's words are the pasted ones |
| 09 paste-long | 6000 characters pasted become a text file's card (6000 字符), put up at once, sent with words | the entry's attachment, a .txt; the station keeps it whole (18000 bytes) |
| 10 attachments | ＋ → 文件: a photo and a 9 MB file, each put up at once in 4 MB parts (three for the file), sent | the entry's two attachments; both files at the station, byte for byte |
| 11 quote | the agent's words held still: 引用, a comment on the quote, sent | the entry's quote: the agent's words, its role, the comment |
| 12 offline-retry | the station frozen (SIGSTOP) as a message goes: 未发送 after some 30 s; thawed, 重试 | the station has the message, once |
| 13 delete-failed | the same, 删除 | the station never gets it, even once thawed |
| 14 mark-read | on Home, the other device asks; the answer comes unread; the chat opened at its end | the station's reads: alice unread before, read to the end after |
| 15 drive-lend | 文件 (MBUI_OPEN_PAGE=files): the station's home; ＋, the folder picker into the station's home, this run's e2e-<tag>, 选择此文件夹 | the station's config lends the folder (drive.roots) |
| 16 drive-list | the folder: 1 个文件夹 · 2 个文件, its entries; into its folder and back by the crumbs | the station's folder holds what was listed; nothing written |
| 17 drive-read | a novel of made-up chapters read: the bars, 目录 → 第三章; left, its row says how far | drive.read through the core; drive.place past the second chapter; the core keeps the place on the device |
| 18 drive-upload | ＋ → 上传文件: a photo and a 9 MB file, each a row going up in parts, then entries | both files in the station's folder, byte for byte; several drive.upload.part |
| 19 drive-rename | the photo held: 已选 1 项, ⋯ → 重命名, a new name typed, 保存 | the station has it under the new name, the same bytes; the old name gone |
| 20 drive-delete | the renamed file held, ⋯ → 删除, asked (the test station has no trash), 删除 | gone from the station's folder, the others there |
| 21 station-files | in the chat, ＋ → Station 文件: the lent folder, a file ticked, 添加 1 个: its card; sent with words | the station's entry: the words and studio 上的文件：<path> under them; no attachment |

Found by it and fixed: the app never told the core it was shown (`client.focus {visible, focused}`), so the core
never marked a chat read (the station's reads stayed empty: every chat opened at its first unread message however
often it had been read) and held back no notice for the chat on screen; it now does, as Home shows a workspace and as
the system says the app came to the front or left it (@host.set_app_state). A scripted run counts as in front: on
Studio, whose screen is locked, the window is reported covered. Also corrected on Android: while a composition was under way the field
told the input method its words without it and no composing region (`updateSelection(…, -1, -1)`), against
InputMethodManager's contract; Host.setIme now gives it the words with the composition in, the selection after it and
its region (MBInput keeps what it composes; MBUI_IME_LOG=1 logs what passes). On the emulator Gboard ends any
composition it did not make itself (finishComposingText at once, with or without the region), so flow 04 turns the
emulator's keyboard off while it composes (`log do: android-ime off`): the run is then the only input method.

Each run marks the words its flows send with its own tag (`{T}` in a flow, `$TAG` in its check), so the same station
can take any number of runs, on either platform, and a check counts only its own run's messages.

What the fake backend shows that the real one would not: a message without `post:` gets the station's ⚠ notice (本轮
agent 未在对话中回复…) as the fake claude only echoes it, and a station frozen for a minute ends its agent's turn
(出错：意外停止). Not checked here: the browser sign-in itself (the local cloud's Google is mocked only inside its own
tests; the mock account is taken in through `migrate` instead), pushes, the camera and the system's photo picker
(MBUI_PICK_FILES stands for the pickers), the soft keyboard's own typing (the InputConnection is driven, not the
keyboard), and anything only a real agent runtime does.

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

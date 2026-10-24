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
  for IO, as the current app runs it, in Hermes everywhere (React Native
  0.81.4's, the same `core.hbc`): on Android the prebuilt `engine` and
  `shell` parts (`node scripts/native.ts path engine android-arm64`), on
  macOS and iOS src/host/apple_core.mm on Hermes's Apple frameworks (until
  2026-10-19 JavaScriptCore), later on Windows. The protocol is the one src/core speaks (docs/client-core.md
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
  the core reads Markdown (client/core-ts/src/markdown.ts, GFM's tables too) and `@sf.markdown` draws its tree as a
  message does (Markdown.kt): tables in a card's frame, their columns as wide as their words allow up to the message's
  width, then scrolled sideways; code in the colours the core says (`ink`, painted as the web's Shiki: vitesse light
  and dark, src/sf/ink.mbt) and scrolled sideways rather than wrapped (mbui's `Ctx::sideways`: a finger moving sideways first
  drags it, up or down first the list); a link held is its menu (打开链接, 复制链接; src/sfapp/link_menu.mbt, Links.kt
  linkHold over mbui's `on_link_hold`). Selection: slice 5's picking.
- 2, the page stack: `Nav[P]` and `Ctx::nav` (src/ui/nav.mbt), App.kt's
  Pages: push/pop sliding side by side (300 ms, standard curve), the left
  edge's swipe and the system's back gesture (`@hostapi.set_back`; Android's
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
  drawable_data.mbt, which scripts/drawables (tools/drawables) makes from apps/android's
  res/drawable and ui/Icons.kt): the makers' marks, Slack's, still.fail's
  mark, the illustrations and the 314 station glyphs.
- `APP=sffix` (src/sffix) is the same Home over made-up chats in the core's
  shapes (src/sfapp/fixture.mbt), no core: `scripts/shots.sh home web-home`
  pictures it (out/shots/mac-home*.png and web-home.png).

Not yet, against the current app: the bottom bar (slice 7: 奏 N and 令 in
it, so no new-chat button here), the long-press menu (pin, rename, copy link)
and swiping a row away, the rows' motion as the list changes, the open jobs
banner and the changelog's note, pull to refresh (the app has none either),
the update button, inviting and new workspaces in the sheet, English (the
words are the Chinese catalog's), avatars' pictures on Android (no image
decoding there yet), `client.focus`, and picking the first workspace into the
prefs at start (only a switch made here writes them).

The search (src/sfapp/search.mbt, Search.kt; branch mbui-search-composer, 2026-10-21): the list starts at its first
row with the field above it out of view (Home.kt top); the field tapped, the search opens over Home: its field comes
up from where it was to the top in 280 ms (Ease.Arrive), narrowing as 取消 comes in from the right, the list going up
56 and fading with the top bar, the bottom bar out of its way; 取消 or back, all of it back in 240 ms (Ease.Standard).
What the words find (the core's `search` topic): the chats (as Home lists them; one found by a line of it, that line
over its title), the messages, then a section per kind (services and tasks, files, stations, members), 查看更多 under
one that has more (that kind alone, from the top; 全部结果 or back, every kind again); under it all the stations still
answering, those that could not be searched in red, the core's note; 未找到结果, 更新后才能搜索. A found line is one line
cut at its end (mbui's rich `max_lines`), the words bold with a hand-drawn stroke in the accent under each, drawn in
one after another (520 ms each, 180 apart: src/sf/stroke.mbt). A message opens its chat at it with the words marked
there (bold, stroked, kept while the chat shows; its first word put in the middle when it lies low; nothing flashes:
search_marks.mbt); a service its chat and its page, a station its page, a member the workspace's, a file its place in
its station's files (a folder entered, a text read, a video played). `APP=sffix MBUI_FIXTURE=search-results` (and
search-jobs) is the Android app's SearchResultsTest's search; scripts/motion/search.drive records the open and close.
Not yet: the keyboard's 搜索 key (mbui's editor has no IME action).

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
  the options, 忽略), login cards (the `machineLogin` topic), the unread
  line, the activity line of an
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
  MBUI_CHAT_BENCH=1 with MBUI_BENCH=3 (mbui's bench_app: every frame drawn while it asks)
  scrolls it up 600 frames and says the frames' times.
- Scrolling (MBUI_CHAT_BENCH, Studio, 390×844, 600 frames at 40 a frame,
  build + layout + paint): the made-up chat of 3000 messages 0.34–0.57 ms a
  frame on average (p99 0.8–2.5 ms, none over 8 ms); the long real chat
  (its 151 messages, every page brought in) 0.58–0.71 ms (p99 under 4 ms,
  none over 8 ms). Only the rows in view are built; the views are read once
  a version, Markdown parsed once a text.
- `APP=sffix MBUI_FIXTURE=chat` opens a made-up chat with every kind of
  message (src/sfapp/chat_fixture.mbt; `chat-loading`, `chat-long` with
  3000 messages): `scripts/shots.sh chat web-chat` pictures it
  (out/shots/mac-chat*.png and web-chat.png).

Not yet, against the current app:
the file preview (slice 11); the activity's floor (the room it leaves kept as it
folds away), the crossfade of what it says and its stepping ring; a new message followed from its top when it is taller than the
screen; the asks' bell; the chat's sheets ("…", the agent's card, jobs);
images on Android (no decoding there yet: their boxes and likenesses only);
the station's update control in the bar.

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
  macOS (`@hostapi.pick`, src/hostapi/pick.mbt; Picks.java); the camera tile takes
  a photo on Android (ACTION_IMAGE_CAPTURE's picture, as the app's
  TakePicturePreview); the recent photos across the top and Station 文件 (both
  branch mbui-media-complete, below); on iOS the photo picker, the document picker and the camera. Not yet: any
  picker on Windows and the web (a toast says so).
- Quoting: a message's words held still a long press's time (400 ms) pick the word under the finger, widened by
  words as it slides on (the list holds still meanwhile: `Ctx::take_press`), the passage drawn behind the words in the
  accent at 26%; lifted, handles at its ends (a line down its side with a knob, the finger's room 36 round it) move
  them, and a bar over it (under it when the top bar is too near; gone while it changes or the list moves) has 引用
  (into the draft as a quote), 复制 (已复制) and 全选. A tap anywhere else, or back, lets go (src/sfapp/pick.mbt,
  MessagePick.kt, ui/Pick.kt). The words are mbui's (`Ctx::words`: a box's rich paragraphs as one text, kept as laid
  out, their offsets, rects and the passage drawn behind them; `@ui.word_at`: the host's word boundaries, Android's
  ICU BreakIterator, Apple's CFStringTokenizer, the browser's Intl.Segmenter, else letters and digits together and a
  Han character alone, as on Windows and in the tests).
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
  composer so: `scripts/shots.sh composer web-composer` pictures them
  (out/shots/mac-composer-*.png and web-composer-*.png).

Words with a reference to another chat (`@[title]`) are looked at before they
go (`chat.outsideRefs`, src/sfapp/outside.mbt): another workspace's chats they
name are shared first from a sheet (`chat.xshareAdd`; 仍然发送 when none may
be), in a chat and a new chat's first message alike. A picture waiting in the
composer opens in the viewer from its tile; a link shared in opens; the draft's
files and its station files are one row, in the order put in, scrolled
sideways; a file going up says how far while a part goes (`progress`); files
sent fly from their tiles to their places in the message (flight.mbt).
`MBUI_FIXTURE=chat-attach-row` is the row wider than the capsule.

Not yet, against the current app, for want of mbui's (its editor has no caret
or selection to read or set, no styled ranges, no say in an edit; its hosts
paste words only): `@` references to other chats and pasted chat links as
marks (chat.ref, chatSearch), the marks drawn in the accent and taken whole by
a backspace, files pasted or sent by the keyboard, the text toolbar of the
field (select, cut, copy by touch; the keyboard's own paste works), links drawn but not tapped while words are picked (a tap
on one lets go of the pick and follows it), the long press's haptic tick (no host haptics yet), a new chat
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
  `open_file` (src/sfapp/open_file.mbt: the file preview, slice 11, its bytes read by `drive.read`). Held, a row is chosen (others by a tap; 已选 n 项, 全选, ⋯): one renamed (the ask sheet,
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
  web-drive` pictures them (out/shots/mac-<mode>.png and web-<mode>.png).

Not yet, against the current app (GB18030, the serif face, the system bars following the paper: branch
mbui-media-complete, below): 跟随's swatch drawn half and half on a diagonal (here the dark page as a disc in the light
one), the frosted glass of the bars and sheets (their tint only), the
system's back closing a sheet or ending a choice (it goes back a page), dragging sheets by the grabber, the
long-press ripple, station files kept with the draft on the device, the station page's way into a drive (slice 13).

The rest of slice 12, the player (branch player-share, 2026-10-19; ember apps/android drive/Player.kt, Playlist.kt,
chat/screens/VideoViewer.kt AudioViewer): a video or a song of a drive, or a song of a chat, played as it streams through
the core.

- src/player, a package of its own that the media app can take as it is (it knows nothing of still.fail's core: a
  `Track` is a name, a media type and a `read(offset, length, answer)`): `Player` over a page (Player.kt PlayerScreen) and
  `audio_strip` (AudioViewer), the folder's order (`playlist_of`, numbers as numbers), `next_in`, `pick_subtitle`
  (E01.srt for E01.mp4, a tag between, SubRip first), `clock`, `speed_label`, and subtitles read here (`parse_subtitles`:
  SubRip, WebVTT, ASS/SSA's dialogue; their tags and overrides dropped) and drawn by the player, so every host shows them
  alike (the Android app hands them to media3).
- The player (Page `DrivePlay(DriveAt)`, src/sfapp/play.mbt; a folder's video or song row pushes it): black whatever the
  theme, the system's player in a native view (slice 11's: ExoPlayer, AVPlayer), its bytes read through the core a part at a
  time (`drive.read`), the picture fitted in the page; the bar at the top (back, the name, which of the folder's it is:
  2 / 3), at the foot the time over the timeline (what is buffered lighter on it: the hosts now tell it, and whether it
  played to its end; tapped or dragged along, the time follows the finger and the player goes there once let go), the
  one before, 15 s back, play, 15 s on, the one after, the speed (1× 1.25× 1.5× 2× 0.5× 0.75×), the subtitle's key, fit or
  fill (sideways), sideways (`@hostapi.set_sideways`: Android asks for landscape and puts the system bars away; back turns it
  upright first). Left alone while it plays, the controls fade (200 ms) after 2.5 s; a tap brings them back or sends them
  away (waiting out a double tap's 300 ms); a double tap on the left or right third jumps 15 s (快退 / 快进 15 秒 said a
  moment), in the middle it pauses or plays (已暂停 / 继续播放). 正在打开 and 正在缓冲 as a pill in the middle, 播放失败 with
  重试, at its end 播放结束 with 下一个：<name>; the next or the one before take the page's place. A song: its mark and name
  in the middle, the controls staying, no sideways. The system bars' icons are light over it (the host told the page is
  dark). Where it is goes to the core (`drive.place` with its time and length in ms, every 5 s while it is open and as
  the page goes; the drivePlace topic), and it opens there next time unless it was left within 5 s of its end.
- A chat's song in the preview (FilePreview.kt's Audio, AudioViewer): its name and the capsule in the page's colours (play
  on the ink, the timeline in the accent, `m:ss / m:ss` in the code face, 播放失败), read through the core a part at a time
  (`station.file.part`); the preview's bar over it as over any file.
- `APP=sffix MBUI_FIXTURE=player-video|player-audio|player-ended|player-opening` (src/sfapp/play_fixture.mbt: a folder
  no listing shows, its films' reads never answered, how the player stands pinned for the shot) and `chat-preview-audio`:
  `scripts/shots.sh player web-player` and `preview web-preview` picture them (out/shots/mac-player-*.png,
  web-player-*.png, mac-preview-audio.png and web-preview-audio.png).

Not yet, against the current app: the frosted glass of the player's bars (a native view under them cannot be blurred: a
deeper solid tint, as the preview's), the subtitle's shadow (a dark ground under its words only), the bytes played kept on
the device to play again without the station (DriveCache's played: each play reads through the core again), why it
failed in words (the host logs the player's error; the page says 播放失败), the tabular figures of the time (the UI
face's own).

Slice 8, decisions, history, tool steps, a chat's sheets, jobs (branch decisions, 2026-10-19): what a chat asks is
answered from it, and an agent's work can be looked into (src/sfapp/decide.mbt, sheets.mbt, history.mbt,
decisions.mbt; Decisions.kt, Chat.kt AskDismiss and ArchiveUnder, LoginCards.kt, ChatInfo.kt, AgentSheet.kt, Jobs.kt,
OpenJobs.kt, History.kt, ui/ToolStep.kt, ui/Sheet.kt):

- The cards in a chat do what they say: an options card's option tapped answers it (`decision.answer`: the core sends
  the viewer's message quoting the post, or, for an option the agent made with action=close, closes the card with no
  message: `decision.close`), a spinner on it meanwhile, its row pressed as the Android app's ripple; 忽略 lets the ask
  go (`decision.dismiss`), at once, back if it failed; the bar's 归档 archives the chat (`chat.archive`: Home at once,
  已归档 said); a login card for one who may finish it
  (the station's `machineLogins.canLogin`) says what to do now by its step, with its pill and 取消
  (`machineLogin.cancel`). Anything that fails is said in a toast (无法…：…), as AppState.act says it.
- Their states and motion (branch mbui-chat-complete, src/sfapp/decide.mbt `under_post`): an option pressed is drawn at
  97% (80 ms in, 180 out, Ease.Out) on the ripple's ground; answered, the options stay as they were (the one picked
  whole, the rest at half) while they go (200 ms, CSS's ease-out: fading, to 90%), their room closing on the rows'
  spring 100 ms late (ListMotion.kt closeGap), 忽略 going with them, and how it went (你 选择了「…」) fades in once they
  have gone (200 after 200), its room opening on the same spring; 忽略 tapped goes on ArchiveEase (280 ms, fading, to 85%
  from its top left, its room closing); the bar's
  归档 comes and goes as nothing is left in the chat or something is again (280 ms, ArchiveEase, fading, from 85%, its
  width from its end). Only drawn, but for the rooms (as the Android app lays them out): going, they take no tap. Each
  is in the motion log (`under/options/…`, `under/outcome/…`, `under/dismiss/…`, `under/archive/…`, `bar-archive/…`).
  `APP=sffix MBUI_FIXTURE=chat-cards|chat-answering` (the fixture answers, lets go and keeps as the core does; 保留
  fails in chat-cards): `scripts/shots.sh cards web-cards`.
- Sheets over the chat, one at a time, coming up over the scrim (Sheet.kt's 26 corners, the grabber, as tall as what
  they show): "…" opens the chat's own (its name with renaming it, `chat.rename`; who started it, how many take part,
  its latest; its agents with where each stands and its account's allowance; 固定到列表顶部 / 取消固定 `chat.pin`, 复制会话
  链接, its sharing, 在 Slack 中打开, 归档对话); an agent's mark in the bar, its name over its messages or its row there opens
  its card (what it runs and where it stands with 停止 while it works, `session.stop`; its latest lines; 费用估算, 缓存
  命中, 上下文; its station, account, 历史, 后台); the bar's jobs button (its dot when one died lately or a service
  restarts) its services and jobs (`chatJobs`: those that matter now, 全部 N 个, 清掉已结束的 `job.clearEnded`) and each
  job's own (通知 / 输出 as it grows, `jobLog`; 停止 `job.stop`).
- An agent's execution history, a page pushed from its card's 历史 or its activity row (the `history` view): its head
  (停止, 释放进程 `session.evict`, 步骤 / 详情), what it received and posted drawn alike (a line, the words in brief beside a
  bar, opened whole on a page of their own as Markdown), the states it marked, its own words, its groups of steps
  opening to calls and thoughts; a call in brief is read whole as it is opened (`history.detail`), the page before as
  the reader nears the top (`history.older`). A call is drawn by what it is (ToolStep.kt): a command, an edit as a diff
  with its context, a file written or read (Claude's `cat -n` lines without their numbers), a patch, a plan, the
  search's words, its fields; what came back (Codex's exit code and time, DeepSeek Harness's tags and exit marker,
  output on red when it failed). Its details: where it stands, its figures, how it runs (the model, effort, account),
  runtime, process, turns, usage, the station and its machine.
- The 奏 page (decisions.mbt; `decisions {scope}`): the cards waiting for the viewer one at a time, the chat's title
  over the messages before the post and the post as the chat draws them, the options under it (tapped: it flies up and
  the next comes in), the reply field at its foot (a text card's placeholder; `decision.reply`), swiped left 待定
  (`decision.defer`, last) or right 不再提醒 (`decision.dismiss`) past a third of the width or flung, springing back
  short of that; none left, how the day went (今日已批, 平均等待, 办理中), where the next may come from, what was
  answered today. Its way in is the bottom bar's 奏 (slice 7's): `open_decisions()`, and `decisions_capsule` draws
  奏 N (Home.kt DecisionsCapsule) where the bar puts it; MBUI_OPEN_PAGE=decisions opens it at the start for scripted
  runs.
- Home's list has the jobs left up a long while at its top (OpenJobs.kt, `longJobs`): a row to its chat, stop at its
  end, 还有 N 个 folding the rest. A message's files in a chat (ChatFiles.kt) were slice 4's.
- `APP=sffix MBUI_FIXTURE=decisions | decisions-text | decisions-idle | history | history-details | chat-info |
  chat-agent | chat-jobs | chat-job | home-jobs` (src/sfapp/decide_fixture.mbt): `scripts/shots.sh decide web-decide`
  pictures them (out/shots/mac-decide-*.png and web-decide-*.png).

Tool steps' code is highlighted by its language (a command as shell, a file by its extension: ToolStep.kt Block) and
a capped block scrolls within its height (mbui's `Ctx::capped`: a finger up or down moves it while it can go that way,
else the page), branch mbui-chat-complete.

Not yet, against the current app: the run settings page (RunSettings: its rows are shown, not
opened); the station's card from an agent's; sharing the chat with other
workspaces and making it public (their rows are shown); a watched chat's question before archiving; the
reply on the 奏 page takes words only (no files, quotes or its own draft kept by the core) and its card neither tilts
nor shrinks as it goes (boxes have no rotation or scale yet); a sheet dragged by its grabber; the segmented control's
sliding thumb; a history opened at an entry; a Slack user's 这是我.

Slice 14's web previews, a service's page (branch player-share, 2026-10-19; ember apps/android chat/screens/Preview.kt,
PreviewWeb.kt, PreviewLoad.kt): a web service an agent started (a dev server, a report it serves) opened over its chat
(src/sfapp/service.mbt, Page `Service(station, job)`), from its row in the chat's jobs sheet (a service up or being
started again; one that did not start, or is over, opens its sheet as before) or Home's services left up a long while
(its chat, then its page over it).

- Found by its job (the `job` topic), known by its name, never its port: the compact bar (对话 back, its name, its
  station under it); 找不到此服务 / 正在读取 / 「名字」已停止 in its place while it cannot be shown.
- The page is a site view (src/ui/native.mbt `NativeView::site`, host_native.mbt `view_site_*`): a web view of a host of
  its own whose every request is said to the app and answered by it, head then body a piece at a time, let go when the
  page lets go. Android: a WebView whose requests of https://preview.stillfail.invalid are intercepted
  (shouldInterceptRequest; its thread waits for the head a minute at most, then reads the body as it comes:
  NativeViews.Site); scripts and DOM storage on; a link elsewhere is said, not followed. macOS and iOS: a WKWebView with a
  URL scheme of its own (stillfail-preview://svc, WKURLSchemeHandler), the requests' bodies handed over. The browser
  and Windows open none. The app answers each from the station through the core (`station.preview` with `stream`: the
  core client now hears a call's values before its answer, `@core.stream`, and stops one, `@core.cancel`; Source.stream
  and cancel), the service's redirects followed here (to the service only, 5 at most, a 303 or a POST's 301/302 as GET),
  its cookies kept here by name and sent along, a request with no answer said to the page in words (502, 508).
- The page's bar: back and forward in its own history, reload, how far its resources came (the `previewLoad` topic's
  ring, red with one failed; tapped, a sheet of each: its path, its status or 失败, how long), where it is (the 🌐, its
  name, its path; tapped, typed, Enter goes there). The stage: all of the room, or the page laid out at a size of its
  own (手机 390 × 844, 平板, 笔记本, 桌面) fitted on the canvas's grey, centred, 16 round it, its screen's corners
  (the host lays it out at its rect over the scale and draws it scaled: view_control 8). The toolbar under it: 自适应, the
  sizes, 自定义 (a sheet of them), turned; held half a second it folds away and the bar's size button opens it. A service
  being started again is said over the page (its dot, 名字正在重启, 第 n 次 · 恢复后自动刷新), which loads anew once back.
- `APP=sffix MBUI_FIXTURE=service|service-sized|service-restart|service-stopped` (src/sfapp/service_fixture.mbt: the first
  row's chat's service, its station's answers made up): `scripts/shots.sh service web-service`.

Not yet, against the current app: marking the page for the chat's agent (the edit key, the marks and their shots, into
the draft), its page script (assets/preview/page.js: WebSockets, request bodies on Android, marks) and so a service's
sockets (a dev server's hot reload), the sized page moved and pinched on its canvas, typing a size of one's own (自定义
lists the sizes), the size and the toolbar's folding kept on the device (kept while the app runs), a visualization's
page (PreviewFileScreen), document.cookie (the cookies are the app's, not the web view's), the opening and closing motion of the page's own,
the sized page's screen corners (a native view is clipped to a rectangle: its shadow and square corners on the canvas).

Slice 14's updates (branch player-share, 2026-10-19; ember apps/android app/Updates.kt, shared/Install.kt, Home.kt's
update button, SettingsHome.kt Version): the app keeping itself current (src/sfapp/updates.mbt, Updates.java).

- Where a build comes from is an `UpdateSource` the app is given (`set_update_source`): `check(version, now)` answers
  the newest build when newer (an AppRelease: versionCode, versionName, file, sha256, size, news), `url(file)` where its
  file is. `cloud_updates(feed)` is still.fail cloud's, as the Android app has it (the core's `app.update`, at most
  hourly unless asked now: /releases/<feed>/latest.json, the file under /releases/ or a whole URL). The mbui build ships
  apart from still.fail's (its own package and key, a release of its own), so src/stillfail gives no source by default:
  MBUI_UPDATE_FEED=<feed> gives the cloud's (the local cloud's in e2e). A release published elsewhere meets it with a
  latest.json of the same AppRelease shape beside its APK (and a source that reads it).
- Asked once the app is signed in. Home's top bar offers a build that brings something (its `news`): the download key
  with its accent dot, how far while it downloads (40%); the settings' version row any build (更新到 0.1.1, in the accent;
  检查更新 asks now: 正在检查, then 已是最新 or why it failed). Tapped: asked again now, then the host downloads it
  (@hostapi.update_install; Android's Updates.java: into the cache, a cut connection picked up by a range, six tries with
  growing pauses, 网络中断，正在继续下载 meanwhile; checked against its sha256: 下载的文件不完整 when not), and hands it
  to the system's installer (PackageInstaller, as this app's own newer build; the confirmation the installer asks for
  opened by InstallResult); without leave to install apps the system's page for it opens (允许 still.fail 安装应用后，
  再点一次更新). What failed is said in a toast (无法更新：…). Hosts with no version code (all but Android) never ask.

Not yet, against the current app: checking again as the app comes back to the front (only at its start), an APK of a
chat installed from the file preview (安装), a source for the mbui build's own release (it is to publish a latest.json
in the AppRelease shape beside its APK; no host here reads a JSON from a URL of its own yet).

Slice 14's share sheet (branch player-share, 2026-10-19; ember apps/android app/share/ShareActivity.kt, ShareSheet.kt,
drive/DriveScreen.kt hand; docs/share-in.md): src/sfapp/share.mbt, Shares.java.

- In: another app's share sheet hands still.fail a link or some text (Android's ACTION_SEND of text/plain, taken by
  MainActivity: @hostapi.shared_in; MBUI_SHARE_TEXT and MBUI_SHARE_TITLE for scripted runs). One sheet (72%, draggable): what
  is shared (a link's mark or text's, its title bold: the app's subject or its first line, its first line under a
  subject), 发到 the chats it can go to (the core's `shareIn` view: the one a thing from the same site went to last first,
  saying so; 搜索 from six chats, its field 找 chat), 新 chat last (在 Studio 上开; with several stations up, which one). A
  tap: `shareIn.open` puts it in that chat's composer (a link as a card among its files: its title, its site; the words
  around it after what is written) and the chat opens (a new chat rises on that station), where it is added to and sent:
  the composer reads the draft anew, keeps the links with it (the core's DraftView `links`) and sends them as words
  after what is written (its title on a line, then the link), as the core's composer does. 没能打开：… in red when it
  fails.
- Out: a file of a drive (its sheet's 分享) read whole through the core (`drive.read`), then handed to the system's share
  sheet (@hostapi.share: Android's chooser, the file in the cache's shared/ read through a provider of the app's own,
  Shares.Files, that lets another app read only what was handed to it; macOS's sharing picker over the window); 本机没有
  可打开此文件的应用 when none takes it. Words can go the same way (`share(text, …)`).
- `APP=sffix MBUI_FIXTURE=share-in|share-in-stations` (src/sfapp/share_fixture.mbt): `scripts/shots.sh share web-share`.

Not yet, against the current app: the sheet over the app it came from (Android's ShareActivity is an activity of its own,
translucent over that app; here still.fail comes to the front and shows it over itself), signing in first from the sheet
(signed out, the app's sign-in page shows and the share waits), sharing on iOS, Windows and the web (no share sheet
there yet).

Glass (branch glass, 2026-10-19): frosted glass and liquid glass, a pass of every renderer (Metal on macOS and iOS,
GLES3 on Android, D3D11 on Windows, WebGL2 on the web), src/ui/glass.mbt:

- A box takes `glass=` (`@ui.Glass::frosted(blur=, tint=, solid=, saturation=, rim_*=)` or `@ui.Glass::liquid(…)`)
  in place of its `bg`. Painted, it is an instance of its own (kind 5 frosted, 6 liquid) that shares a capture with
  the glass right before it (nothing drawn between, the same blur, not over it): slot 20 carries the capture's
  number, negative, so the renderers' runs of one image are runs of one capture too. When a renderer reaches a run it
  ends its pass, copies what is drawn so far under the run's rects (with three deviations of room round them) out of
  the target, halves it down to where the blur's deviation is two texels or more (dual Kawase's downsample, 1/2 to
  1/8), blurs it there with a Gaussian of what deviation is left once the halvings' and the bilinear look's spread
  are taken out, and draws on through it: the copy saturated, the tint over it, the rim (a hairline inside the edge,
  the top left lit, the foot and right less: Bar.kt's) on top. A glass box's shadow is drawn after it and only
  outside it, so the glass does not frost its own shadow (Haze's source is the page alone).
- still.fail's glass is src/sf/glass.mbt, from Glass.kt (Haze: `cssBlur(px)` is a deviation of px dp, CSS
  blur()'s), Bar.kt, Sheet.kt and the web's mobile/styles/pages.css.ts: `glass_bar` (the page's paper at 70% over a
  24px blur: Home's, 文件's (a place's) and the chat's top bars, the hairline the bar's own), `glass_floating` (`raised` at 72% over a
  20px blur: the composer's capsule, the way to the newest), `glass_bottom_bar`, `glass_bar_ball`, `glass_action`
  (Bar.kt's, rims lit) and `glass_sheet` (the surface at 80% over 28px) for the bar and sheets to take.
- A notch cut into a box's top (`c.box(notch_y=, notch_r=, notch_fillet=)`: a circle about its top's middle, met by
  the edge through fillets, Bar.kt's outline): slots 21-23 of a rectangle's or frosted glass's instance, the renderers'
  shape the rounded intersection of the box and what is outside the circle (its ground, border, glass and lit rim
  alike, and its solid ground where glass is drawn solid). `Glass::sharing` (`shares_capture`): frosted glass that
  frosts what the glass before it frosts (its capture, at its blur), whatever has been drawn since and over that glass
  too: the bar's ball and its action frost the page under the bar, not the bar (Bar.kt: Haze's one source is the
  pages); a renderer copies what is under every instance of a capture when it reaches the first.
- Liquid glass (the demo's MBUI_SCREEN=glass, not on still.fail's pages): each shape's rounded-box distance, the
  shapes of a `glass_group=true` box drawn first as one capture and merged by a smooth minimum (`merge`); what is
  under it bent along a bezel (`bezel` wide, by up to `refraction`, a circle's profile), the colours split by
  `chroma`, a rim lit from the top left; text in it (`adaptive`) is a glyph kind of its own (7) whose ink the
  renderer picks from how light the copy is round the glass's middle.
- Solid where the system asks for less transparency: macOS's and iOS's Reduce Transparency, Windows' transparency
  effects off, the browser's prefers-reduced-transparency (asked every 30 frames); Android has no such setting.
  MBUI_GLASS=solid (or `@ui.set_glass_solid`) forces it; solid is the glass's `solid` ground (the paper under its tint).
- `@hostapi.gpu_ms` (Metal's command buffers' times; -1 elsewhere) goes into the in-app bench's lines (MBUI_BENCH=1);
  src/bench has `glass`, `glass-solid` and `liquid` scenes (BENCH_SCENES=…, not in the default set).
- What it costs (Studio, M2 Max, 2026-10-19, Metal). Offscreen, 900×640 at 2x (src/bench, 300 frames, median): the
  list scene with a top bar, a jump button and a composer of glass (three captures) 0.56 ms of GPU and 0.15 ms of
  encoding a frame, against 0.12 and 0.01 drawn solid; liquid glass (a merged group and a capsule) 0.49 and 0.11;
  building, laying out and painting the same (0.06-0.08 ms). The copies take about 26 MB at that size (the level
  textures are the target's size, kept). In the app's window (390×844 at 1x, MBUI_BENCH=1, 600 frames scrolled, two
  runs each): Home (one capture) 0.26-0.28 ms of GPU and 0.15-0.19 ms presenting, against 0.09-0.10 and 0.10-0.11
  solid; a long chat (bar and composer, two captures) 0.42-0.56 and 0.21-0.43, against 0.09-0.10 and 0.08-0.10. On
  the Android emulator (SwiftShader, so only a smoke test) both looks draw.
- Shots: mac-glass, mac-glass-dark, web-glass (the demo's screen), mac-home-dark, mac-chat-dark, mac-chat-glass (a
  picture under the chat's bar), mac-chat-solid; MBUI_DARK=1 for sffix and the demo.

Slices 6 and 7, a new chat becoming its chat and the bottom bar with sheets in use (branch newchat-bar, 2026-10-19;
src/sfapp/bar.mbt, sheet.mbt, newchat.mbt; src/ui/drag.mbt; Bar.kt, Places.kt, Sheet.kt, NewChat.kt, ChatHost.kt):

- The bottom bar on a place's top page with nothing over it (Places.kt PlaceBar, Bar.kt BottomBar): the places of the
  bar in view (the core's prefs `barsBy[workspace]`, else `bars`, else [对话, 文件, Profile, Station] and [奏, 用量, 连接,
  已归档]), 22 from the screen's sides and foot (the system's bars are the hosts': the view is laid out inside them on
  Android and iOS); the ball over the place shown, on its spring (tension as stiff as the way is short, ZETA 0.635),
  stretched by its speed, held (6% bigger) and led by a finger sliding on the bar; 令 (a new chat) in the notch cut
  into the bar's top on the chats' family's pages (对话, 奏, 已归档), the notch and the places' spacing on their spring;
  the 奏 place's accent dot while decisions wait (`workspaceMarks`; the Android app shows a dot, no number), the
  stations' red one while one is in trouble. Drawn up past 24 (closed under 16, leaning a quarter toward the finger),
  the glass grows into the panel of the other bars; let go on a place in it, or a row tapped, that bar is the one in
  view (`prefs.set {barsBy}`) and its place opens. A place tapped is its page at the stack's root, in place, coming in
  30 from the side the ball goes to and fading in (220 ms; 180 from no side); back on another place's page goes to the
  chats. It goes down out of the way (300 ms) under a page pushed and comes back (380 ms). Home keeps its room at the
  list's foot (BAR_ROOM, 126). 文件 is the drive's page (drive.mbt `files_page` as a place), its ＋ (another folder
  lent, `files_lend`) in the notch while it can lend; 奏 is the decisions page (slice 8's, a place's top bar over it
  and the bar's room at its foot); the other places are their top bar over nothing yet (PlacePage.kt; their pages are
  later slices'). The sheets of a chat (slice 8's, decide.mbt's frame) are not on this sheet host yet: they neither
  drag nor snap.
- The bar and its sheets on frosted glass (branch glass-bars): the bar is `glass_bottom_bar` with the notch cut into it
  (a box's `notch_*`, above: Bar.kt's outline, the circle and its two fillets, its lit rim along the notch too) and the
  notch's own edge lit (1 wide, white at 70%, 22% dark); 令 (or 文件's ＋) is `glass_action`, the ball
  `glass_bar_ball`, both `sharing` the bar's capture, so the three frost the page under them and not each other, one
  copy a frame as on the phone. Every sheet (the sheet host's, slice 8's chat sheets, the drive's, the settings', ＋'s
  in the composer) is `glass_sheet` over the page and its scrim (sheet.mbt `sheet_glass`: drawn solid, the paper, the
  scrim's black and the surface at 80%). A new chat's choices over the composer are on the composer's glass
  (`glass_floating`). The shadow is cast below and to the sides only.
- What moves in the bar is only drawn (src/motion's rule, branch glass-bars): the bar laid out where it rests, drawn
  going down out of the way (300 ms) and coming back (380 ms), only drawn as it goes (a tap meanwhile is what is under
  it's: the page pushed); the action laid out whole in the notch and drawn growing out of it and shrinking (as the
  notch opens and closes, about its middle, which comes up to the edge); its icon swapping between 令 and a page's ＋
  while the notch stays open (Bar.kt showIcon: 300 ms, the one going out by 120 ms on CSS's ease to half its size,
  drawn only, the one coming in from 60 ms, faded in over 180, grown from half over 240 on Arrive; closed, at once);
  a bar chosen in the panel sliding down into the bar's place as the panel closes (Bar.kt Swap: the stack of bars
  inside the closing glass, the chosen bar's places laid out where they end and drawn coming from their row, from the
  rows' fade and offset and each place as lit as it was to the bar's look; the others and the bar left drawn only,
  cut by the glass's top; the ball riding the place tapped; a finger drawn on the bar meanwhile takes neither the
  ball nor the panel until it has landed (Bar.kt), but a place tapped on it is that place's at once, where it is laid
  out).
- Sheets (Sheet.kt SheetHost): one at a time over a scrim (black at 28%, 300 ms), rising on SheetSpring (critically
  damped, stiffness (2π / 1.2·0.32)²); its top 64 drags it: a draggable one between 55% and 94% (or closed under 30%),
  any other only down (closed past 80, else back), let go at the finger's speed; a tap on a draggable one's grabber
  switches half and full; a tap on the scrim, back, or dragged down closes it. `Ctx::drag_area` (src/ui/drag.mbt) is
  what takes those drags: a box that takes the presses landing on it as a list does, so nothing behind a sheet (or the
  bar) scrolls, and says where the finger has it, past the slop on its axis, let go and how fast. In use: the
  workspaces' sheet (70%, draggable, as Workspaces.kt has it; it was a fixed one before), a new chat's station (50%)
  and what it runs on (66%). (＋'s sheet in the composer is still its own, as slice 5 made it.)
- A new chat (NewChat.kt): 令 raises it from the bottom (380 ms, (.2, .8, .2, 1): `Nav::rise`; back or the edge swipe
  sinks it), its bar 取消 · 新对话, the `newChat` topic's page: while its stations are read their first read, with no
  station the first one to add, with none up said so; on a station the illustration, 想让 agent 做什么？, where it runs,
  the combinations used often (one tap: `newChat.pick`), what keeps it from starting (`problem`, 添加 Profile when it has
  none); at its foot the choices over the composer: the station (its sheet of the stations up: `newChat.pick
  {station}`) and what it runs on, as one control (the model · the runtime where there is a choice · how hard it
  thinks · how fast · who runs it; its sheet of the models by series beside the runtime, the depth and the speed, the
  accounts in its foot, `pick.set` until 确定 `pick.save`; with no model enabled, 没有可用模型 · 前往勾选). The composer
  is the chat's (composer.mbt, its draft `new:<station>`: words, files, quotes as in a chat). Sent: the composer empties,
  the chat is made (`newChat.create`, once for what is picked: picked anew before a message went, made anew) and the
  message goes to it by its key (`chat.send {session}`); then the page becomes that chat in place (`Nav::become`: the
  same page, its composer's field and focus kept; back from it goes sideways), the new chat's scene going up out of
  view as it fades (140 ms) and its choices fading (80 ms), the chat's list coming up out of the composer (480 ms after
  90); Home lists it at once (the core's row). Refused, the words come back and why is said.
- `APP=sffix MBUI_FIXTURE=newchat|newchat-station|newchat-model|home-bars|place` (src/sfapp/newchat_fixture.mbt):
  `scripts/shots.sh newchat web-newchat` pictures them (out/shots/mac-newchat-*.png and web-newchat-*.png). Home's
  pictures (mac-home, mac-home-dark, mac-home-sheet, mac-home-swipe, web-home, and slice 8's mac-decide-home-jobs and
  web-decide-home-jobs) changed on purpose: the bar on Home, the workspaces' sheet in the new sheet.
- MBUI_DRIVE has `drag X Y DX DY [MS]` and `dragon DX DY MS TEXT` (a finger moved a frame at a time, then lifted).

Not yet, against the current app: the stations' place's glyph of their states (the
server's mark here), the bar going away while the keyboard is up (no page with the bar has a field yet), the words
flying from the composer into their bubble (the list comes up with them; the words leave the field at once), the
machine's own sessions to go on with (MachineSessions), borrowing another station's model (the note only), a wide
screen's column, the offline station's illustration (not among the drawables yet), the profile and models pages the
new chat leads to (place pages over nothing).

Slice 11, the file preview (branch preview, 2026-10-19): a file of a chat tapped (its image, its video's box, its
card) opens over everything (src/sfapp/preview.mbt; FilePreview.kt, VideoViewer.kt, FileKinds.kt kindOf, ChatFiles.kt
FileData; Zoom.kt):

- The bar floating at the top (44 high, its corner 14, 12 in): the file's name (15 semibold), its tools, 下载 and ×;
  over a picture or a video the dark tint, over a document the page's white with its shadow; it fades after 2 s left
  alone (4 s after a tap brought it back), a tap on the stage brings it back. It fades in and out (140 ms), as the
  Android app does when the thumbnail is not on the screen. Back (the system's, ×) closes it.
- What it shows, by the file's name (kindOf's tables), or for a name of no kind by its first 8 KB (`station.file.part`:
  UTF-8 with no NULs is text): an image read whole through the core (`station.file`), the chat's thumbnail standing in
  meanwhile, fitted with a margin (12, or 32 on a wide screen), a double tap to 2.5× the fitted size (at least 100%)
  around it and back, the bar's − / % / + (×1.25, the % back to fitted), two fingers pinching it round the point
  between them (Android tells mbui of a second finger now: pointer kinds 4, 5, 6, `Ctx::second_pointer`), a finger
  panning it when larger (let go moving, it goes on at the finger's speed, slowing, to its edge; dragged on past its edge,
  the one beside it comes in as a fitted swipe brings it), the wheel zooming round the pointer; a video played by the system's player in a native view (below), its bytes read through
  the core a part at a time (`station.file.part`, as the drive's DriveSource reads `drive.read`: never the whole file
  first, where the Android app's chat viewer fetches it to the disk before playing), its controls over its foot (where
  it is, to tap or drag along; a frame back, play, a frame on; which frame of how many; 1× 0.5× 0.25× 0.1×); a PDF's
  pages drawn by the system as they scroll near (12 round them, their shape on the waiting grey before), HTML in a
  page of its own (a native web view under the bar: its scripts run, nothing of the device's files reachable, no link
  followed) or its source; Markdown rendered (`@sf.markdown`) or its source; CSV as a table (a row number, its columns
  as wide as what they hold, the head with a hairline, 2000 rows at most); code and text in the code face (12.5 on 20,
  a file over 2 MB cut with the warning's line). Anything else (or bigger than 16 MB) is told of: its kind's mark, its
  name, its size and extension, why it is not shown, 下载 (fetched, then put in the system's downloads: MediaStore's
  Downloads on Android, ~/Downloads on macOS, MBUI_DOWNLOADS_DIR there for runs).
- A file of a station's drive opens here too (the drive's `open_file`, src/sfapp/open_file.mbt): the same viewer, its
  bytes read by `drive.read` (4 MB a part, the whole for what is shown whole, ranges for the player); stepping
  through the folder's pictures is not done yet.
- Native views over the canvas (src/ui/native.mbt, host_native.mbt `view_*`): a system view the host keeps under the
  app's surface, shown through a hole the app paints where it is (instances of kind 9: transparent, written without
  blending); what is painted after the hole draws over the view (the bar, the video's controls), what is painted
  round it (or a clip) hides the rest of it, so it scrolls and clips with the canvas. `Ctx::native(view, content=)`
  places it each frame it is painted and hides it on the frames it is not. Android (NativeViews.java): the GL surface
  is on top of the window and translucent (setZOrderOnTop), the views in a layer over it in the view tree (a page
  takes its touches) under it on the screen; the video is Media3's ExoPlayer (1.8.0, as the Android app's) on a
  TextureView whose transform puts the picture in its rect, reading through ViewSource (DriveSource.kt's window: 256 KB
  first, doubling to 4 MB while reads run on, kept on the disk while the view is open), each read asked of the app
  (`view_read_next`) and answered from the core as its bytes come (`view_read_answer` piece by piece: the core's part
  read with `stream`), the player going on with the first of them while the rest is on its way (on a slow link it
  waits for what it needs, not for the 4 MB around it); a read no reader is on any more (a seek elsewhere) is let go
  of, the app stopping the core's read; the page is a WebView with the
  Android app's HtmlPage settings (JavaScript on, no file or content access, no DOM storage, shouldOverrideUrlLoading
  true). macOS and iOS (apple_views.m): the Metal layer non-opaque over a views root, AVPlayerLayer with an
  AVAssetResourceLoaderDelegate on a scheme of its own reading through the same calls, WKWebView with a
  non-persistent store and no navigation but the first; the window's snapshots composite the views' content under the
  canvas. The browser (web/host.js): a <video> from the bytes read whole, a sandboxed <iframe> (scripts only), in a
  layer under the canvas. Windows: none yet (no view opens: the app says it cannot show it).
- PDFs (`@ui.Pdf`, host_native.mbt `pdf_*`): opened from their bytes, each page an image the host draws at the size it
  is shown (Android's PdfRenderer from a file of the app's cache, one page at a time; Core Graphics' CGPDF); the
  browser and Windows draw none (said so on the page).
- Images on Android are ImageDecoder's already (Images.java): the chat's pictures and the viewer's show there too.
- The glass: the Android app blurs under the bar and the video's controls (Haze, darkGlass: 0x121214 at 62% over a
  24 dp blur); a native view under them cannot be blurred (the glass pass copies the canvas, where a view is only
  its hole), so here they are a deeper solid tint (0x121214 at 85%) whatever is under them (the page's white at 92%
  over a document). In the renderers a hole is a run of its own inside the glass's runs: glass painted after a hole
  sees the hole, not the view.
- `APP=sffix MBUI_FIXTURE=chat-preview-image|pdf|video|audio|html|code|md|csv|none` opens a made-up file
  (src/sfapp/preview_fixture.mbt: a picture, a PDF of two pages, a video whose reads are never answered, a page with a
  script, code, Markdown, a table, a file of no kind): `scripts/shots.sh preview web-preview` pictures them
  (out/shots/mac-preview-*.png and web-preview-*.png).

Not yet, against the current app (the viewer's flight, stepping, pinching on iOS, marking, a video's frames and
landscape: branch mbui-media-complete, below): code highlighting and a code file's sideways scroll,
installing an APK, an SVG drawn by a page when it is not a bitmap, the progress of a whole file coming (`progress`), a
big file read to the disk, a web view's own scrolling under the canvas on macOS while something is painted over it,
the frosted glass over a picture or a document (where nothing native is under it: `@sf` glass could take it).

Slices 9 and 13, settings and the pages under it (branch settings, 2026-10-19): Home's gear pushes settings
(src/sfapp/settings, a package of its own that the app hands what it reads and calls and how it moves: `Core`), and
from it the pages the Android app has there (app/screens/SettingsHome.kt; settings/Me.kt, Archive.kt, Usage.kt,
Stations.kt, Profiles.kt, Connects.kt, Vault.kt, Security.kt, Settings.kt's Workspace, Memory.kt), with their parts
(Parts.kt NavBar, LargeTitle, SectionHeader, Card, ListCard, ListRow, Seg, Avatar; SettingParts.kt GoRow; PageParts.kt
Switch, PresenceDot; Controls.kt Button, PickRow, DoingMark; Waiting.kt's cards and rows; Sheet.kt's sheet host and
the menu from a button):

- Settings: the account's card, the workspace's rows each saying how things stand (its people and who waits, security
  mode, the vault, stations online, connects failing, profiles short of allowance), this device's (外观, notifications,
  this build).
- 外观: the theme (跟随系统 / 浅色 / 深色), motion, language, when a done chat is offered to archive, each the core's
  prefs (`prefs.set`), shown at once. The theme is applied every frame: the prefs' `appearance`, or the system's when
  it follows it, which the hosts now tell (`@hostapi.system_dark`: macOS's effective appearance, asked again when the
  system switches; Android's night mode, MainActivity's configuration; iOS's interface style; the browser's
  prefers-color-scheme; Windows says light), and the host follows the app's (`@hostapi.set_dark`: Android's status and
  navigation bars' icons and the ground under them, the Mac window's title bar).
- 账号: the accounts on the device (signing each out: `auth.signOut`, adding another), where the account is signed in
  (`loginSessions`; one not this signed out: `loginSession.revoke`).
- Workspace: its name (renamed by a tap: `workspace.rename`), its people, those added who have not signed in
  (`workspace.removeAdded`), the invitations out (`workspace.revokeInvitation`), a person's sheet (their role:
  `workspace.setRole`, moving them out), its relays (`workspace.setRelays`), leaving or deleting it.
- 安全: off (what it is, who may turn it on) or on (how many sign, the devices waiting, each a sheet with its code:
  `lock.confirm` / `lock.deny`; the people and their devices, a web page's renewed: `lock.renew`; the stations, one taken
  in: `lock.joinStation`; turning it off once the workspace's name is typed: `lock.disable`); 开启 (`lockDraft`,
  `lock.toggle`, `lock.open`).
- 密钥 (the vault): what has to come first, then the requests waiting on the viewer (允许一次 / 一小时内 / 拒绝:
  `vault.approve`, `vault.deny`), whether the library is locked, the profiles' accounts, each vault's items by kind,
  the devices holding the keys.
- Station: a card each (the buddy's face, its mark and name, what of its load runs low, its network; offline asleep);
  a station's page (its machine's dials, network and details, or that it is offline with 重试: `client.wake`; what runs
  on it, its drive's folders opening the drive's page), its "…" for owners and admins: 重命名 (`workspace.renameStation`), taking it out (`workspace.removeStation`).
- Profile: the workspace's list by kind (the core's `profiles`), a station's; a profile's page: its check, its
  allowance (read again: `profile.quota`), its models ticked on and off (`profile.put`), read again (`profile.check`),
  who uses it, its key masked, its variables.
- 连接: every station's (all or the viewer's, the filter's menu), the Slack apps waiting; a connect's page: who it is,
  what is wrong with its link, how it runs, its recent sessions (each opening its chat).
- 记忆: every station's, a station's (`memory.get`: the global memory by its parts, the projects', the skills, the
  built-in ones folded), a page each (Markdown, its files as pills).
- 用量: the totals, each day's cost as a bar split by person (tapped, its numbers), the lists by chat, person, model;
  7 or 30 days in the bar.
- 已归档 (from Home's filter menu): by the day archived, the words looked for, more as it is scrolled; restored
  (`chat.archive` with archived false) or deleted (`session.delete`, asked first); a row opens its chat.
- The bottom bar's places (slices 6 and 7) Station, Profile, 连接, 用量 and 已归档 are these pages at the stack's root,
  under the place's top bar (bar.mbt `place_page`, PlacePage.kt): without their own compact bar, their actions (用量's
  7 or 30 days, 连接's filter) in a row over what they show.
- Every write goes through the core's own call, as the Android app's (`act`: said in a toast how it ended; spinners and
  red marks from the core's `doing`). `APP=sffix MBUI_FIXTURE=settings-<page>` shows a page over made-up settings
  (src/sfapp/settings/fixture.mbt): `scripts/shots.sh settings web-settings`.

Completed (branch mbui-settings-complete, 2026-10-19), what the slice left drawn and not opened:

- Stations: adding one (Station's ＋, the bar's notch at the stack's root: a new machine named, `workspace.enroll`'s
  command copied, the wait until it joins, said in green; a station of another workspace the viewer manages joined as
  it is, `station.join`), the first one in the page itself (FirstStation); a station's page in full: its mark picked
  (station_mark.mbt: still.fail's 314 icons searched by their words, in a colour, an emoji typed or pasted, a picture,
  none; `workspace.renameStation` with emoji and icon), its screens (`screens`), 共享调试 (its page: AdbShare.kt's), its
  drive, the macOS grants (`permissions.request`), the agents' variables (their sheet over `agentEnvForm`), what its
  search finds (`search.setPersonal`), the workspaces it is in (`memberships`), its versions (`software.update`,
  `.check`, `.channel`, `.auto`); the bar's Station place drawn as the stations' glyph of their states (src/sf
  glyph.mbt, StationGlyph.kt's: arcs, failing dots, the robot blinking, asleep).
- Profiles and connects: adding a profile (`profileFlow`: the providers, a plan signed in through `login.new` and its
  steps, a key checked first by `profile.flow.submit`) or a connect (`connectFlow`, a step a screen: the Slack
  workspace's configuration token, the app made and installed, its tokens, the model and the mode); a subscription
  signed in (`profile.login`, its steps: the page handed to the system's browser, `@ui.open_url`, as
  LocalUriHandler; 无法打开此链接 where nothing took it); a profile's "…" (renamed, checked, deleted or stopped), its sharing (`profile.share`, `.move`), its
  workspaces, its run switches, its key and its variables changed, what to do in trouble; the machine's own logins
  offered; an account on several stations; a connect's "…" (reconnect, its tokens checked by `slack.tokens.verify`,
  Slack, off and on, its owner, deleted), its mode and session sheets, what it runs (`pick` of `connect:<id>`, another
  station's model borrowed once asked again), its Slack app page (`slackApp`, `connect.putSlackApp`), the apps made and
  not connected yet. A new profile is what a new chat's 添加 Profile opens.
- Vault: an item's page (masked until shown by `vault.open`, each field shown and copied: a secret cleared from the
  clipboard 30 s later), its editor (`vault.putItem`, `.deleteItem`), 添加, setting the vault up (`vault.setup`) and its
  24 recovery words shown that once (never kept), the key given to devices set up since, this device keyed again by
  the words (`vault.recover`). Every secret is typed into a secret's field (mbui `Ctx::editor(secret=true)`: dots, never
  copied out); the call log (MBUI_CALL_LOG) redacts every secret's value (stillfail/main.mbt `logged`).
- The rest: the automatic decisions (the rule's page, each station's settings of it over `decisionForm`, a station's
  archive policy over `policyForm`), 下方栏, 本机缓存 (what the core keeps of each chat: `cache.usage`, `cache.clear`),
  更新日志 (`changelog`, `changelog.seen`), 价目表, adding people (`workspace.addMembers`, from Slack: `slack.people`) and
  the workspace's mark, how a chat's agent runs (RunSettings: `pick` of `session:<key>`, opened from its history's
  details), the machine's own sessions to go on with (`machineSessions.*`), another station's model borrowed from a new
  chat's picker, asked again first.
- `APP=sffix MBUI_FIXTURE=settings-<page>` has each (src/sfapp/settings/fixture.mbt): `scripts/shots.sh settings
  web-settings`.

Not yet, against the current app: the language changing the app's own words (they are the Chinese catalog's); the
sheets' drag; opening a station's screen (the remote screen's viewer is slice 14's: its row says it cannot be opened);
lending this device's adb (the host does not find Wireless debugging's ports: the page says the device cannot); a
picture as a mark cropped to its middle 96 px square (one small enough is put up as it is, a larger one refused); a
Slack app's icon drawn from still.fail's buddies (no way to draw one into a JPEG yet); the times of day that need a
clock (上次检查 …, 还剩 N 分钟); 本机缓存's files outside the core (this app keeps none of its own); a field's input
type told to the system's keyboard as a password's; a secret marked sensitive for the system's clipboard preview.

Slice 10, notifications and pushes (branch notify, 2026-10-19; ember apps/android app/Notices.kt, Push.kt, App.kt,
MainActivity.kt, screens/SettingsHome.kt Notify; docs/notifications.md → Clients): src/sfapp/notices.mbt over the host's
notifications (src/hostapi/notify.mbt).

- While the app is shown it follows the core's `notify {workspace}` (client/core-ts attend.ts decides: none while
  off, none for the chat looked at, only the workspace in view), takes each notice (`notice.claim`) and has the system
  show the ones it took: one channel (消息, IMPORTANCE_HIGH), one notification per chat (its `tag`, the same id: a newer
  one replaces the older), still.fail's mark as the small icon in the accent, the chat's title, its one line
  (BigTextStyle), CATEGORY_MESSAGE, gone once tapped. Hidden, the topic is left (Notices.kt's flow ends with onStop).
- A tap brings MainActivity back (singleTask, the notification's PendingIntent) with its link: the core reads it
  (`link.parse`), its workspace is switched to, Home is the root and the chat is pushed over it (Back: Home), and the
  chat goes to the message it is about once its list is in place (Screen.Chat.at, ChatHost.kt goTo: the pages before
  brought in until it is there), which flashes (ChatMotion.kt flash: the accent's ground round someone's message, 10
  past it each side and 8 above and below, corners of 14, in over 160 ms on Ease.Out, held to 900, gone by 1700 on the
  standard curve; your bubble takes it instead; with motion reduced held as long, then gone). The flash is only drawn
  (under the list's rows: @ui.on_list_underlay, Ctx::paint_rect), never laid out.
- A chat on top takes its notification off (App.kt), however it was opened.
- What the system lets the app show is told to the core as the app starts and each time it is shown again
  (`notify.permission`: granted, denied, or default while Android 13+ was never asked); the system is asked once, the
  first time signed in with notifications on (`notify.set {asked}`, POST_NOTIFICATIONS), and again as they are turned
  on in settings, where a refusal says 在系统设置里允许 still.fail 发通知.
- Settings → 通知 switches them (`notify.set {on}`): at once, a spinner while the core has not answered (its `doing`),
  back with 无法开启/关闭通知：… when it fails; the push registration then follows what the core answered (Push.sync:
  `push.unregister` while off, `push.register {kind: fcm, token}` with the host's token while on), as it does at
  every start.
- A push delivered is shown unless the core says not (`notice.pushed`: off, a page in view, another workspace's, its
  kind off), and what it is about is brought onto the device (`notice.bring`), by the push service (Push.java).
- `APP=sffix MBUI_FIXTURE=chat-flash|chat-flash-mine` (a message gone to, its flash held at its peak) and
  `settings-notify-off`: `scripts/shots.sh notify web-notify` (mac-notify-*, web-notify-* pictures).

Hosts (@hostapi.notice_show, notice_cancel, notice_permission, notice_ask, notice_answer, notice_opened, push_token):
Android is the system's (android/…/Notices.java, POST_NOTIFICATIONS in the manifest, the activity's
permission answer and the tap's intent). macOS keeps what would be shown and says it on the log (`NOTICE <tag>\t<title>\t
<body>`, `NOTICE CANCEL`, `NOTICE TAP`): the app there is a bare executable, which UNUserNotificationCenter does not
take (it wants a bundle); what it allows is unknown. iOS's are the system's (UNUserNotificationCenter, no pushes).
Windows shows none yet (toast notifications and WNS: a later slice's), nor the web page (it logs). A scripted run looks for and taps a
notification by its words on Android (the app's own active notifications; the tap its PendingIntent sent) and on
macOS (the kept ones): drive.mbt `noticed`, `nonotice`, `notice`.

Firebase Cloud Messaging (android/…/Push.java, as the Android app's Push.kt): Firebase set up by hand from the app's
resources (res/values/push.xml, firebase.properties' values) for the package's Firebase app (fail.still.android.beta's;
none registered for the others, whose pushes stay off), its components merged into the app's manifest by hand (apk.json
`merged`). The token is asked for as the process starts; the app registers it as the core's `notify` says, at its
start and as a token comes later. The FirebaseMessagingService does what PushService does, on FCM's thread, with the
core: the app's where it runs (its own Java client, AdbCore's ids), else one started for the push
(android_core.c CoreHost.startAlone: the app takes it as its own if it opens meanwhile, else it stops once the push is
handled). A new token is registered; a push is asked of the core (`notice.pushed`; it not answering, shown unless the
app is in front), shown, then `client.wake` (the app off screen: how long, since it went or the push before woke it)
and `notice.bring`. The app's frames stop while it is behind, so none of it is the MoonBit side's. Still not: the
notification's language when the app is not running (KeptLang: the app's words are the Chinese catalog's).

Files and media, kept on the device (branch mbui-media-complete, 2026-10-19; ember apps/android shared/screens/
FileKinds.kt download, drive/DriveScreen.kt saveToDownloads, saveZip, DriveFetches, ui/Parts.kt DownloadChip):

- mbui's host keeps a file the app has read (@hostapi.keep_begin / append / finish, src/hostapi/keep.mbt): its bytes put a
  part at a time into a file of the host's temporary directory (never whole in memory), then moved where the person
  keeps files: Android's MediaStore Downloads (no permission asked; `Choose` the documents UI's ACTION_CREATE_DOCUMENT),
  macOS's ~/Downloads (`Choose` a save panel over the window), iOS's Files sheet either way, Windows' Downloads known
  folder; MBUI_DOWNLOADS_DIR the downloads for scripted runs. How it went comes back a frame later (Keeping, KeptAt,
  CalledOff, Failed).
- A drive's file 下载 (its sheet, or several chosen: 下载 n 个文件, each at once): 正在下载「名字」, read through the core
  a part at a time (`drive.read`) straight into the keep, how far on its row meanwhile (n% in the accent's filling box,
  DownloadChip, moving smoothly over 500 ms), then 已保存到「下载」 or 下载失败; 无法获取「名字」：… when the station could
  not give it (src/sfapp/keep.mbt). A folder's 下载为 zip: the station zips it (`drive.zip`: where the zip is, a root of
  its own), then it is read and kept as any file; the folder's row shows it under way (0% while zipped, then how far:
  the Android app shows nothing there). 分享 reads the same way, its row's progress shown too. The chat's preview's 下载
  keeps its file through the same host (a save panel nowhere: Downloads as the Android app has it).
- `APP=sffix MBUI_FIXTURE=drive-download` (a file and a folder under way): out/shots/mac-drive-download.png,
  web-drive-download.png.

Not yet: the bytes downloaded kept for the drive's next open (DriveCache: each download reads through the core again),
a big file's download going on while the app is away (it is the app's: Android stops it with the process).

Files shared in (branch mbui-media-complete): another app's share sheet hands still.fail files, not only words and
links (the Android app takes text only; its sheet and composer are the reference): ACTION_SEND with a stream and
ACTION_SEND_MULTIPLE of any type, read whole by mbui's host (Shares.java; 1 GB each at most, as the composer takes)
and taken by the app (@hostapi.shared_in's `files`, shared_in_file). The sheet heads with them as the composer shows files
(pictures as 56 tiles, a file's mark, its name and size, n 个文件 and their names for several), 发到 the chats as for a
link (the site's last chat not said: files have none); a tap opens that chat (or a new chat on that station, made the
one new chats start on: `newChat.pick`) with the files in its composer, going up at once as ＋'s do; words shared with
them still go in through `shareIn.open`. MBUI_SHARE_FILES (paths split by |) stands for another app on macOS.
`APP=sffix MBUI_FIXTURE=share-in-files`: out/shots/mac-share-in-files.png, web-share-in-files.png. Flow 93 share-files
(Android: an ACTION_SEND intent with the photo through the app's own provider, `#android-intent`; macOS: a photo and a
PDF).

Recent photos and Station 文件 in ＋'s sheet (branch mbui-media-complete; Attach.kt RecentPhotos, latest; StationFiles.kt
RefCard, openRefSheet, sendUp):

- The recent photos: across the top of ＋'s sheet after the camera, the gallery's latest 30 (mbui's @hostapi.gallery_*:
  MediaStore's images and their times, read off the app's thread; ranked here as Attach.kt `latest` does: each by the
  latest of its times that can be believed, one in milliseconds taken as the seconds it means, one ahead of now left
  out), each its thumbnail as the gallery has it (Images.java loads a content:// source by loadThumbnail), 92 × 122 on
  14 corners; a tap reads it whole (@hostapi.pick_photo) into the draft, up at once. Without leave to read the gallery
  the last tile asks (显示最近照片: the system's dialog; asked and refused for good, the app's settings), with only the
  photos chosen for the app (Android 14 on) it chooses more (选择更多照片); read again as the sheet opens and as the
  system answers. The strip moves sideways under a finger and glides on once let go (a drag area: it is no list).
  iOS's is the photo library (Photos: all of it, or the photos chosen; its picker of more). macOS and Windows have no
  gallery here: the tile says so (as before). 照片 is the open panel on macOS, the photo picker on iOS.
- Station 文件: ticked files go in named by their path, or as files where the chat says so (此对话默认发送文件: the
  core's prefs `dropFiles` by the chat's key, else `dropAs`); a card tapped opens its sheet (where it is, 发送方式 路径 /
  文件 (a folder of the chat's own station: zip), the chat's say as a switch). As a file it is staged on the chat's
  own station (`drive.stage`: a folder zipped there) or read from the station that has it (`drive.read`) and put up to
  the chat's (`station.upload.part`); the card turns the bubble's grey with a spinner, how far, its size once up, why it
  failed; the message carries it as an attachment, nothing goes while it goes up.
- `APP=sffix MBUI_FIXTURE=chat-station-file | chat-station-sheet` (one sent as a file, a folder as a zip going up; a
  card's sheet); the recent photos' strip is Android's (its shots from the emulator, flow 95). Flows 94
  station-file-sent, 95 recent-photos (Android).

The image viewer, complete (branch mbui-media-complete; FilePreview.kt ViewerLayer, Viewer, Gallery, Leaving, Beside;
VideoViewer.kt frameStarts, saveFrame, landscape; ImageMarks.kt):

- Stepping through a chat's images: the core says those beside the one shown (`imageNear` by the chat's thread, else
  its session: each with the session that keeps it), a drive's folder its pictures in its order. The one shown and those
  beside it are one strip, the stage's width and 24 apart: fitted (not zoomed), a finger sideways carries it (past the
  first or the last a third as far), let go past 80 (or a fifth of the width) or flung that way it goes on to that one,
  else back, on SLIDE (critically damped, stiffness 400) at the finger's speed; the one going is drawn from its
  picture where it was. Over the image's sides, in the middle, while the bars show, the ways to the one before and
  after (36 discs of the dark canvas at 80%). Those beside it are read ahead (and the last few read kept), so a step
  shows the next at once; their thumbnails stand in meanwhile.
- The flight: an image opened from the chat grows from its thumbnail (its box, its corners, the picture cropped as the
  chat crops it) to its place on the stage in 320 ms on (.2, .8, .2, 1), the black and the bars coming with it; closed,
  it shrinks back into its thumbnail in 280 ms (from where a flight in had got to); the thumbnail hidden meanwhile (one
  picture on the screen, never two). With no thumbnail on the screen (or its size not known yet) it fades as before.
- Pinching on iOS: the host tells a second finger now (4 down, 5 moved, 6 up, as Android's).
- Marking an image (标注图片, its whole picture here): 选择, 框, 箭头, 画笔, 文字 at the foot on the dark glass, the
  colour (seven, each with the halo that edges its words), 删除 the picked mark, 撤销 / 重做; boxes and arrows numbered,
  a pin on each (tapped: its note), the note written in a box at the foot (完成, 删除), the notes as cards over the tools.
  The marks are in the picture's own pixels, drawn on the screen at its zoom (boxes bordered, lines and arrows as dots
  along them, words with their halo round them); a picked mark moves with the finger, an arrow's end stretches it. 取消
  / 下载标注后的图片 / 添加到对话 in the bar: the host draws the marks on the picture at its own size (mbui's
  @hostapi.draw_marks: Android's Canvas, Core Graphics), then it is kept with the downloads or put in the chat's draft with
  a quote per numbered mark (图片 … 标注 n: where it is, on which image, what was said), and the viewer closes to the
  chat (已添加到对话，返回对话发送). Back steps out of a note, the words, the colours, the pick, then marking.
- A video's frames: their times read from the file's index (mbui's NativeView::frames: Android's Mp4Extractor reading
  an MP4's or a QuickTime file's moov over the same reads as the player, Apple's sample cursor; never the samples, which
  would be the whole video track read beside the player), so ‹ › step to the very next frame the file has whatever its
  rate, and n / N 帧 counts them (正在读取帧 meanwhile; a 60th of a second where none are read). 保存此帧
  (paused): the frame showing grabbed at its own size (MediaMetadataRetriever, AVAssetImageGenerator) and kept with the
  downloads as name-n.png. 横屏: the phone turned for it, upright again as the viewer closes.
- `APP=sffix MBUI_FIXTURE=chat-preview-step | chat-preview-swipe` (a second picture beside the first: the ways to it;
  halfway to it under a finger): out/shots/mac-preview-step.png, mac-preview-swipe.png; mac-preview-image changed on
  purpose (标注图片 in its bar, as the Android app's).

Not yet: a video flown back into its thumbnail at the frame it was left at (videos fade), marks' text drawn with the
words' own shaping on the image (the host's face, not mbui's), a marked image bigger than memory (the Android app
draws it in bands), Windows' marks, frames and grabs.

The reader, the rest (branch mbui-media-complete; TextModel.kt decodeText, Reader.kt PaperBars, FontFamily.Serif; the
web's reader's download):

- GB18030: a text that is neither marked nor UTF-8 is read as GB18030 by the system's own tables (mbui's
  @hostapi.decode_charset: java.nio's Charset, CoreFoundation's encodings, Windows' code page 54936, the browser's
  TextDecoder), a character the end of a cut file halves dropped, as the Android app reads it.
- The serif face: 字体 宋体 draws the text in the serif face (mbui's run `serif`: Noto Serif and its CJK on Android,
  Songti SC on Apple, SimSun on Windows).
- 下载 in the top bar's right end (the web's reader has it): the whole file kept on the device as the drive's 下载 keeps
  it (keep.mbt), a novel cut at 16 MB too. reader-bars' picture changed on purpose.
- The system bars follow the paper: a reader's as dark as its paper (night on a light theme, white on a dark one), the
  viewer over a picture or a video dark, the player dark; the theme's again as each goes.
- Flow 98 reader.

## Checked end to end, against a still.fail of its own (branch e2e-local, 2026-10-19)

`scripts/e2e-local.sh all` runs the app (APP=stillfail) through what the slices do, against a still.fail that lives
only on this machine, never the real account: ember's local cloud (cloud/test/dev.ts: its Workers in Miniflare,
Google mocked, the test identities, alice in the workspace "Dev"), an iroh-relay of its own (dev mode, loopback), and
a test station enrolled there from a clone of ember (built in it, never in ember-src), its agent ember's fake claude
(station/test/fake: it answers `post:<words>` with those words through the agents' door, as an agent's chat_post),
its one profile with a model enabled (`models: [claude-sonnet-5-5]` in its config: a new chat is refused on a station
with none). Every part has its own ports (E2E_PORT, the cloud from 18787 to 18792; E2E_RELAY, 18740) and directories (E2E_WORK,
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

Found by flow 25, and not a bug of the app's or of still.fail's core: a chat made on another device while the app ran
came into Home's list as a row with no title (（暂无消息）) and stayed so. The probe's own dumps (runs 1–5) show why: each
chat's words reached the station a run late. The old e2e/peer.ts ended as soon as its own row showed the words, which
is while they are still in its core's outbox (chat.send answers with the outbox's id, not the station's), and its data
(E2E_PEER_DATA) was the same from run to run, so the next run's peer sent the last one's words; the app's core put them
in the row the moment the station had them. Rerun on still.fail main (2026-10-19, dev cloud, a station, two real cores:
5 runs with the app up throughout, 8 with the app started anew each run, 8 more with the old peer's ways) every row came
with its title and its last words. e2e/peer.ts now waits for the station to have the words (the chat's messages, not
the outbox) before it ends, and flow 25 makes its chat before the app starts (`#before`) and waits for the station to
have it (`scripts/e2e-local.sh wait-chat`). Two orderings that could leave a row stale were read in the code and never
met: core-ts `station/sync.ts` `#read`/`#whole` (a /chats read answered before a later `chat` event but arriving after
it), and the station's `api/events.ts` `open()`/`flush()` reading rows on two readers at once.

Slice 8 (branch decisions) added flows 22–28 and e2e/fake/claude.mjs, put first on the test station's PATH: ember's
fake claude for everything it knows, and beside it `card:<question>|<label>|<label>*|<label>!` (chat_post with an
options card ending need_human: `*` recommended, `!` action=close), `text-card:<question>|<placeholder>` and
`steps:<words>` (tool calls written to the runtime's own transcript, then chat_post all done). A flow's `#env K=V` lines
go to the app (mac and Android), its `#before WORDS` lines run before the app starts; `scripts/e2e-local.sh pins` says whether alice keeps the test chat pinned.

To check a later slice the same way: add its flows and checks to e2e/flows, and what the runner must do beside the
app to `scripts/e2e-local.sh` (as `peer`, `freeze`, `reads`).
A flow's `#env K=V` lines are put in the app's environment for that flow (the drive's flows start on 文件 with
MBUI_OPEN_PAGE=files until the bottom bar reaches it). Before the flows, `scripts/e2e-local.sh drive-seed <tag>` makes
the drive flows' folder in the test station's home (e2e-<tag>: a text, a novel of made-up chapters, a folder with a
file), a run's own, which flow 15 lends through the app.

The live client renders the local core's Markdown tree, including code colours and formula drawings, and asks it for
code's colours (`code.ink`) and a drive text as the reader shows it (`reader.*`). A run without a core (the Tester's
tests, the screenshots' app, and tapes older than those calls) has the real core's answers kept in `src/sfkept`
(`kept.mbt`, made by `client/core-ts/scripts/kept-answers.ts`): an answer asked and not kept is said on the run's output
and fails `scripts/test.sh`; `scripts/kept` runs the tests and has the core work out what they asked (`FRESH=1`: only
what they ask now). The check script verifies the kept answers are the core's own. This adds no backend messages or elapsed time
to the recordings. Formula glyphs are packaged once, their outlines packed and gzipped (`src/sf/math_glyphs.mbt`,
made with `client/math/font.json` by `client/core-ts/scripts/math-font.ts`), not in the core, which has the glyphs'
sizes alone; messages carry only glyph IDs, positions, rules and any native text (see `client/math/README.md`).

A run is also kept to be seen again without a backend: with MBUI_CORE_TRACE=1 (only on a local cloud) the app logs
every message between it and its core (CORETRACE lines on the flow's log, src/core/trace.mbt), `scripts/trace make
out/e2e/mac/NN-name.log NAME` makes it e2e/traces/NAME.trace (a sign-in's tokens put as
"-"), which the test reads as it runs (`@sfreplay.trace("NAME")`). The flow is then a test in src/sfreplay/flows, its steps written as a Tester's (src/sfreplay/steps.mbt:
`tap`, `see`, `gone`, `type_text`…, ending in `end`) over the app with that conversation as its core
(src/core/replay.mbt): an input draws only the frames it causes; what the core said comes at a frame's start, each
message once what it came after has been asked again; a step that looks looks then, waiting for nothing; time goes on
only by `run_for` a declared length. At its end every message was given, nothing asked that the run did not
(`diverged`) or with other params (`fuzzy`), every ask of the run's made again (`unmade`, but those the test names and
says why), and the app idle (`assert_idle`). Each flow runs as the run had it and again with what may come at once in
orders drawn from seeds (`Replay::shuffle`: answers to different asks in any order, an ask's own in theirs), ending on
the same screen each time (`orders`). 03 and 05 were recorded again on 2026-10-20 once the bottom bar asked the
core for its workspace's `status` (the stations' glyph asleep, as Places.kt). A flow's trace is recorded again from its test, one command: `scripts/rerecord.sh NAME…` (a test's name, or a flow
kept in e2e/flows that it needs before it) has the test write its steps as a scripted run (FLOW_EMIT,
src/sfreplay/emit.mbt: `tap` a `tap`, `see` an `until`, `peer` what alice's other device does), runs them against a
local still.fail of its own under the old trace's mark and station directory, makes the run's conversation the trace
again, says which of the app's asks are more or fewer (scripts/trace diff), and runs the test over it. The app
asking one more thing (a subscription the page now makes) is one command, not a flow fetched back from history.
Only a few flows stay end to end, as smoke (the whole chain: sign-in, send and
the agent's answer; parts going up; the preview's native views reading through the core; the system's notice; a
download kept on the device).

The flows' tests are in several packages so that `moon test` runs them side by side (a package's tests run one after
another, in one executable; check-mbui-native's macOS runner has three cores, 2026-10-20): `flows/chat` (the chat and
its messages: sending, drafts, quotes, links, marks read), `flows/cards` (the cards and the notices in a chat: an
answer's options, dismissing, pins, archiving, the notices; its first test makes it, its moon.pkg the others'),
`flows/drive` (the station's files: lending, listing, reading, playing, renaming, deleting, sending them),
`flows/wide` (the wide window's), `flows/pages` (the other pages, the bars, the sheets, settings). A new flow goes into
the one it is about; one that uses another test's helper goes beside it (the package is where it is seen). A package
added is found by scripts/test.sh and scripts/rerecord.sh by itself (src/sfreplay/flows).

Batch B (22–28, 36, 41–44, 67, 70–72; the replay's pace): a flow is first replayed strictly at the run's pace, each
message due its run's gap after its anchor, the latest event before it that has happened again (an ask made again, a
message given; `Replay::pace`, `clock`, `next_due`; a trace without a wall clock on its asks anchors to the messages
in), `Flow::core` stepping the clock a 16 ms frame at a time only up to what is due; then at once, twice as fast and
twice as slow, in seeded orders, ending the same, all it asked answered (their reports, `client.focus`, `chat.place`,
`draft.put`, as their timing makes them). What comes and goes under a post, the 奏 page's deck, a toast and the flash
of a message gone to say when they are at rest (`under_rest`, `deck_rest`, `@kit.toast_rest`, `flash_rest`), and 70/71
check the 忽略 and the archive buttons shrinking (to 85%) half way and gone at rest (`Flow::shrinks` over
`Tester::look_of`; the options' 90% once look_of can match words exactly, asked of mbui's owner). Still a stopgap: `Flow::core` draws the frames owed once nothing more is due, so that a motion told
by the last message given has started (a hidden next-frame convention); it goes when mbui starts a motion in the frame
it is told. 22, 41, 42 and 70 stay end to end too until their traces carry the asks' wall clock and they pass strictly.

The flows (macOS, 390×844, and Android on the emulator, Pixel 7 size). On 2026-10-19 all 14 passed on macOS; on
Android 13 of 14 in the full run and 11 (the quote) alone, twice, once it waited for the all-done card (it had held
while the card moved the list):

| Flow | What the app does | Checked on the backend's side |
|---|---|---|
| 01 signin | signed in with the mock account; Home lists the test chat, the agent's answer as where it stands | the core's store holds alice's sign-in |
| 02 home-new-chat | on Home while alice's other device makes a chat: its row comes in, then its agent's answer as the row's last words | the station has the second chat and the agent's answer in it · Tester 重放（src/sfreplay/flows/home_new_chat_test.mbt） |
| 03 send-text | a chat opened from Home, words typed and sent (正在发送, then sent) | the station's entry: the words, once, as alice's |
| 04 chinese-enter | Chinese composed and committed through the input method, Enter a new line, sent | one entry of both lines; none of the first line alone · Tester 重放（src/sfreplay/flows/chinese_enter_test.mbt） |
| 05 agent-reply | a question; the fake agent's answer comes while the chat shows, the list following its end | the agent's entry; the answer shown in the window |
| 06 draft | words left in the field, the chat left and opened again: they are back | the draft in the core's store on the device, nothing of it at the station · Tester 重放（src/sfreplay/flows/draft_test.mbt） |
| 07 draft-restart | the app started again: the draft is back; emptied | the core keeps no draft of it any more · Tester 重放（src/sfreplay/flows/draft_restart_test.mbt） |
| 08 paste-short | a short paste (Cmd+V, KEYCODE_PASTE) goes into the field, sent | the entry's words are the pasted ones · Tester 重放（src/sfreplay/flows/paste_short_test.mbt） |
| 09 paste-long | 6000 characters pasted become a text file's card (6000 字符), put up at once, sent with words | the entry's attachment, a .txt; the station keeps it whole (18000 bytes) · 仍走 e2e，待转严格重放：文本文件的 id 和文件名已只由文字和它在草稿里的位置算出（#770），要先重录 trace |
| 10 attachments | ＋ → 文件: a photo and a 9 MB file, each put up at once in 4 MB parts (three for the file), sent | the entry's two attachments; both files at the station, byte for byte |
| 11 quote | the agent's words held still: 引用, a comment on the quote, sent | the entry's quote: the agent's words, its role, the comment · Tester 重放（src/sfreplay/flows/quote_test.mbt） |
| 12 offline-retry | the station frozen (SIGSTOP) as a message goes: 未发送 after some 30 s; thawed, 重试 | the station has the message, once · Tester 重放（src/sfreplay/flows/offline_retry_test.mbt） |
| 13 delete-failed | the same, 删除 | the station never gets it, even once thawed · Tester 重放（src/sfreplay/flows/delete_failed_test.mbt） |
| 14 mark-read | on Home, the other device asks; the answer comes unread; the chat opened at its end | the station's reads: alice unread before, read to the end after · Tester 重放（src/sfreplay/flows/mark_read_test.mbt） |
| 15 drive-lend | 文件 (MBUI_OPEN_PAGE=files): the station's home; ＋, the folder picker into the station's home, this run's e2e-<tag>, 选择此文件夹 | the station's config lends the folder (drive.roots); Tester 重放（src/sfreplay/flows/drive_lend_test.mbt）；端到端里仍留着，借出文件夹是 18、21、35、45、48、52、90、91、92、98 等的前提 |
| 16 drive-list | the folder: 1 个文件夹 · 2 个文件, its entries; into its folder and back by the crumbs | the station's folder holds what was listed; nothing written; Tester 重放（src/sfreplay/flows/drive_list_test.mbt） |
| 17 drive-read | a novel of made-up chapters read: the bars, 目录 → 第三章; left, its row says how far | drive.read through the core; drive.place past the second chapter; the core keeps the place on the device; Tester 重放（src/sfreplay/flows/drive_read_test.mbt） |
| 18 drive-upload | ＋ → 上传文件: a photo and a 9 MB file, each a row going up in parts, then entries | both files in the station's folder, byte for byte; several drive.upload.part |
| 19 drive-rename | the photo held: 已选 1 项, ⋯ → 重命名, a new name typed, 保存 | the station has it under the new name, the same bytes; the old name gone; Tester 重放（src/sfreplay/flows/drive_rename_test.mbt） |
| 20 drive-delete | the renamed file held, ⋯ → 删除, asked (the test station has no trash), 删除 | gone from the station's folder, the others there; Tester 重放（src/sfreplay/flows/drive_delete_test.mbt） |
| 21 station-files | in the chat, ＋ → Station 文件: the lent folder, a file ticked, 添加 1 个: its card; sent with words | the station's entry: the words and studio 上的文件：<path> under them; no attachment · Tester 重放（src/sfreplay/flows/station_files_test.mbt） |
| 22 answer-option | the agent posts an options card (e2e/fake: `card:`), the recommended one marked; one tapped (decision.answer); 你 选择了「…」 under it | alice's message with the option's words, quoting the post; the card as posted, `recommended` on the one；暂留端到端：Tester 和真机对「列表是否在末尾」的判断不一样（client.focus end:false/true 发不发、发几次），已交确定性负责人查 |
| 23 dismiss | another card; 忽略 tapped: it and the options go at once (decision.dismiss) | `dismissed` has alice's row for the post; nothing answered；Tester 重放（src/sfreplay/flows/dismiss_test.mbt） |
| 24 close-option | a card with an option made to close it (action=close) tapped | `closed_cards` has the post; no message sent for it；Tester 重放（src/sfreplay/flows/close_option_test.mbt） |
| 26 history | the agent does steps (e2e/fake: `steps:` writes its transcript); "…" → its row → its card → 历史: received and posted, the group opened, the command opened to what it printed | the agent's post; its transcript (what the history is read from) has the steps；Tester 重放（src/sfreplay/flows/history_test.mbt） |
| 27 pin | "…" → 固定到列表顶部, then 取消固定 | the station's `pins` has alice's for the chat, then none；Tester 重放（src/sfreplay/flows/pin_test.mbt） |
| 28 decisions-page | the 奏 page (MBUI_OPEN_PAGE=decisions, a flow's `#env`); the other device asks with a card; the option tapped there; 奏折已全部批完 | alice's answer quoting the post；Tester 重放（src/sfreplay/flows/decisions_page_test.mbt） |
| 29 glass | four long messages sent from the composer's glass; the newest run under the top bar's glass, then, scrolled up, under the composer's | the four entries, as alice's; on macOS the bar's and the capsule's rows in the shots are not flat (what is under them shows through, blurred) · Tester 重放（src/sfreplay/flows/glass_test.mbt：顶栏和输入框的毛玻璃下压着消息的字，窗口 700 高，Tester 的字体折行比真机少） |
| 30 new-chat | 令 in the bar's notch: the new chat rises; the first message typed and sent; the page becomes its chat; the agent's answer comes there; back on Home | the station's entry: the words, once, alice's, in a thread of their own; the agent's answer in that thread; alice's other device lists the chat；Tester 重放（src/sfreplay/flows/new_chat_test.mbt） |
| 31 places | 文件 tapped on the bar (the drive's page in place); the bar drawn up into the other bar's panel and let go on 奏 (that bar, 奏's page); 用量; the panel again, back on the chats | the bar chosen kept as the workspace's in the core's store on the device (`prefs.set {barsBy}`)；Tester 重放（src/sfreplay/flows/places_test.mbt） |
| 32 sheet-drag | the workspaces' sheet drawn up to 94% and dragged closed; a new chat's station sheet dragged a little (back) and past 80 (closed), opened again and its station tapped | the sheet's settling as the app logs it; the core took the pick (`newChat.pick` answered)；Tester 重放（src/sfreplay/flows/sheet_drag_test.mbt） |
| 33 settings-appearance | Home's gear → settings → 外观 → 深色: the app turns dark at once | the host told (the log's theme: dark); the core's store on the device keeps appearance dark；Tester 重放（src/sfreplay/flows/settings_appearance_test.mbt） |
| 34 appearance-kept | the app started again: dark from its first frame; 跟随系统 chosen again | the first theme told is dark; the store keeps appearance system；Tester 重放（src/sfreplay/flows/appearance_kept_test.mbt） |
| 35 station-rename | settings → Station → the test station → "…" → 重命名: the new name shown, then the old one back | still.fail cloud's workspace (read by alice's other device) has the new name, then the old；Tester 重放（src/sfreplay/flows/station_rename_test.mbt） |
| 36 archive-restore | the other device archives a chat (chat.archive): it leaves Home; the filter → 已归档 shows it; 还原 from its row | the other device saw it in the archive; restored, the station's thread has no archived_at；Tester 重放（src/sfreplay/flows/archive_restore_test.mbt） |
| 37 workspace-members | settings → Workspace: its people, alice among them | the cloud's workspace has alice as a member；Tester 重放（src/sfreplay/flows/workspace_members_test.mbt） |
| 38 preview | the other device makes a chat with a picture, a PDF, a video and a page (`peer createfiles`: put up in parts, then the chat made with them, so the test chat's end stays as the other flows know it); opened from Home, each file opened in the preview, shot, closed | the station's entry has the four files; the app's log: the picture and the page read through the core, the PDF's 2 pages drawn, the player's reads through the core (`station.file.part`) and its first frame, the page loaded in the web view; each shot shows something in its place (e2e/pngstat.py) |
| 39 send-flying | two messages sent back to back, the second while the first's words still fly to their bubble | both at the station, once each, in order; the flight in the motion log · Tester 重放（src/sfreplay/flows/send_flying_test.mbt） |
| 40 notice-wait | on Home, the other device asks the agent for a card: the system shows the test chat's notice (待你决定 · …); tapped, the chat opens over Home at the card, which flashes; the notification gone; back, Home | the agent's card at the station; the core said to show it and the app took it (notice.claim); the notice was the test chat's (its tag); the chat opened at the card's seq and went to it; the station marks alice read to its end |
| 41 notice-failed | on Home, the other device says something the fake agent does not answer: the station's ⚠ makes a notice that something went wrong (出错 · …); tapped, the chat opens at it | the station's ⚠ entry after the words; the notice was the test chat's; the chat opened at the ⚠ entry's seq；暂留端到端：Tester 和真机对「列表是否在末尾」的判断不一样（client.focus end:false/true 发不发、发几次），已交确定性负责人查 |
| 42 notice-looking | the test chat open while the other device asks for a card in it: no notice, the card comes in the chat | the card at the station; no NOTICE for it; the app told the core it shows the chat (client.focus)；暂留端到端：Tester 和真机对「列表是否在末尾」的判断不一样（client.focus end:false/true 发不发、发几次），已交确定性负责人查；app 在状态没变时重复发 end:true，交 app 迁移 |
| 43 notify-off | settings → 通知 off (不接收通知); a card asked meanwhile shows no notice; on again | notify.set answered on false, then on true; push.unregister called; no NOTICE for the card; the card at the station; the core's store on the device keeps notifications on；Tester 重放（src/sfreplay/flows/notify_off_test.mbt） |
| 44 notice-cancel | a notice shown on Home; the chat then opened from its row: its notification goes | the test chat's NOTICE, then its NOTICE CANCEL；Tester 重放（src/sfreplay/flows/notice_cancel_test.mbt） |
| 45 drive-play | 影音 put in the lent folder (drive-media: two episodes with a subtitle, a song); the first episode played (2 / 3, its subtitle's words), left at 3 s, opened again; 15 s on to its end, 下一个 tapped; the song | drive.read a part at a time; the first frame and the subtitle; drive.place about 3 s of 8 kept on the device and played on from there; kept as seen at its end; the next and the song read and ready · Tester 重放（src/sfreplay/flows/drive_play_test.mbt：播放器经 core 读字节由 `view_reads` 照带子重放，播到哪由 `set_player` 给出录制时的数，`drive.place` 和录制一致） |
| 46 chat-audio | a song sent in a chat by the other device; its card opened: the preview's small player, its time going on | the station's entry has the song; station.file.part reads; the player ready · Tester 重放（src/sfreplay/flows/chat_audio_test.mbt：播放器读字节、就绪、播到 0:02 由 `view_reads`、`finish`、`set_player` 给出） |
| 47 service-page | the agent starts a web service (e2e/fake: serve:); the chat's jobs sheet → its row: the page; /b.html typed in the bar; back in its history; 手机 | the station's job has the port; station.preview for the page, its stylesheet and what its script fetched; the site view loaded each page |
| 48 share | a link shared in (MBUI_SHARE_TEXT): the sheet, the test chat tapped, the link a card in its composer, sent; a drive's file 分享 | shareIn.open; alice's entry has the title and the link; the file handed to the system's share sheet; on Android an ACTION_SEND intent taken in · Tester 重放（src/sfreplay/flows/share_test.mbt：分享进来由 `share_in` 给出，分享出去由 `t.shared_out()` 断言） |
| 49 update | (Android only: `#only`) settings' row says 更新到 0.1.1 (release-seed: the APK as built in the local cloud's releases); tapped | app.update found it; downloaded with the feed's sha256; handed to the installer, whose confirmation shows |
| 50 bar-glass | the bar of glass: 文件 and back (the notch's icon swapping between 令 and ＋), the panel drawn up and let go on 奏 (that bar sliding down into the bar's place), 用量 tapped on it as it lands (its page at once), the chats again from the panel | the swap and the landing in the motion log; 用量's page; the bar chosen kept on the device (`prefs.set {barsBy}`)；Tester 重放（src/sfreplay/flows/bar_glass_test.mbt） |
| 51 sheets-sinking | the workspaces' sheet let go of, the bar's 文件 tapped under it as it sinks; the chat's own sheet let go of, the composer tapped through it as it goes down, words typed and sent | 文件 opened; the words at the station, once, alice's; no pin of alice's at the station；Tester 重放（src/sfreplay/flows/sheets_sinking_test.mbt） |
| 52 drive-sheet-closing | a file held, ⋯ → its sheet, the scrim tapped, the sheet's rows tapped where they are drawn as it closes | no rename asked; the station keeps the file, its name and words；Tester 重放（src/sfreplay/flows/drive_sheet_closing_test.mbt） |
| 53 settings-sheet-sinking | settings → Station → the test station → … → 重命名, a name typed, the scrim tapped, 保存 tapped where it is drawn as the sheet goes down | the station's page as it was; still.fail cloud has the old name；Tester 重放（src/sfreplay/flows/settings_sheet_sinking_test.mbt） |
| 54 bar-going-down | the test chat opened from Home, the composer tapped under the bar still going down, words sent | the words at the station, once, alice's; the bar going down in the motion log；Tester 重放（src/sfreplay/flows/bar_going_down_test.mbt） |
| 60 wide-send | (1280×800) the test chat pressed in the sidebar's list opens beside it; words typed, Enter sends them | the station's entry: the words, once, alice's, in the test chat；Tester 重放（src/sfreplay/flows/wide_send_test.mbt） |
| 61 wide-newline | (1280×800) ⇧Enter a new line in the composer, Enter sends both | one entry of both lines; none of the first alone；Tester 重放（src/sfreplay/flows/wide_newline_test.mbt） |
| 62 wide-row-menu | (1280×800) the row hovered, right clicked: its menu; 固定 (the row goes under 已固定), then 取消固定 from the menu again | the station's `pins` has alice's for the chat, then none；Tester 重放（src/sfreplay/flows/wide_row_menu_test.mbt） |
| 63 wide-switcher | (1280×800) ⌘K, words typed, Enter opens the chat; ⌘K again, Esc closes it; words sent there | the entry in the test chat, once；Tester 重放（src/sfreplay/flows/wide_switcher_test.mbt） |
| 64 wide-new-chat | (1280×800) ⌘N: a new chat beside the list; its first words sent with Enter make the chat, the page becomes it, the agent answers (in the chat and its row) | the first message once, in a thread of its own; the agent's answer there；Tester 重放（src/sfreplay/flows/wide_new_chat_test.mbt） |
| 65 wide-places | (1280×800) the rail: 文件 (the stations' folders in the sidebar), the chats, settings (外观: 深色, then 跟随系统), back to the chats | the host told dark; the core's store on the device keeps appearance system；Tester 重放（src/sfreplay/flows/wide_places_test.mbt） |
| 66 wide-resize | 390 wide: Home; the window resized to 1280 (the wide frame; the chat pressed in the sidebar), then to 390 again: the same chat, a phone's page; words sent | the window resized twice (the host's RESIZED); the words at the station, once, in the test chat；Tester 重放（src/sfreplay/flows/wide_resize_test.mbt） |
| 70 card-motion | an options card answered in the chat (the options go, 你 选择了「…」 comes in their place), another let go with 忽略 | alice's answer quoting the post; `dismissed` has alice's row for the second, nothing answered; the motion log has the options going (to 90%, their room closing), the line coming, 忽略 going (to 85%)；暂留端到端：Tester 和真机对「列表是否在末尾」的判断不一样（client.focus end:false/true 发不发、发几次），已交确定性负责人查；app 在状态没变时重复发 end:true，交 app 迁移 |
| 72 bar-archive | the same kind of chat archived from its bar's 归档: Home at once, 已归档 | the session archived by hand at the station; the test chat not；Tester 重放（src/sfreplay/flows/bar_archive_test.mbt） |
| 73 pick-words | held still on the agent's words: a word picked, 复制 (已复制); held again, 引用, sent with words (flow 11 now takes 全选 first) | alice's message quotes a passage of the agent's words, not all of them; on macOS the pasteboard holds just a word of them · 仍走 e2e：Tester 的分词和 macOS 不同，系统的分词结果没录进带子（等「分词进带子」） |
| 74 markdown | the agent's Markdown (e2e/fake `md:`): a table, TypeScript highlighted, its long line scrolled sideways by a finger; a link held: its menu, 复制链接 | the entry has the table and the code; the motion log has the code scrolled across; the link was not handed to the browser; on macOS the pasteboard has the address · Tester 重放（src/sfreplay/flows/markdown_test.mbt） |
| 75 open-link | a link in a message tapped: handed to the system (a scripted macOS run only logs it; Android's ACTION_VIEW) | `open-url:` with the address on the app's log · Tester 重放（src/sfreplay/flows/open_link_test.mbt） |
| 80 add-station | Station → ＋: a name, 生成命令; the runner enrolls a second station with it (`second-station`); 已加入, 完成; its page → … → 移除 | the command made (workspace.enroll); the second station enrolled and in the cloud's workspace, then not · Tester 重放（src/sfreplay/flows/settings_add_station_test.mbt） |
| 81 station-mark | the test station → … → 图标: robot found and picked; an emoji pasted; 不使用图标 | still.fail cloud's workspace has the station's icon glyph:robot, then the emoji, then none · Tester 重放（src/sfreplay/flows/settings_station_mark_test.mbt） |
| 82 station-settings | the station's page: Agent 环境变量 edited and saved; 版本: 自动更新 on and off; 检查更新 | the station's config has the variable; software.auto answered on and off, the config off; software.check answered · Tester 重放（src/sfreplay/flows/settings_station_settings_test.mbt） |
| 83 profile | the profile → … → 重命名, 重新检查; ＋: Anthropic API, a made-up key, 验证并添加 refused | the station's config has the new name; profile.check answered; no profile added; the key never on the log · Tester 重放（src/sfreplay/flows/settings_profile_test.mbt） |
| 84 connect | a connect made without tokens (peer `connect-put`): its page; 停用; 单会话; made-up tokens refused; 删除连接 | the station's connect off, then single-session, then gone; the tokens not saved, not on the log · Tester 重放（src/sfreplay/flows/settings_connect_test.mbt） |
| 85 vault-item | 密钥 (in the clear): ＋ → Token: a name, its value, agents by the proxy to a host, 保存; its page, 显示; 编辑 → 删除 | vault.putItem answered; this device's core lists it for agents; vault.deleteItem, gone; the value never on the log · Tester 重放（src/sfreplay/flows/settings_vault_item_test.mbt） |
| 86 decisions | 自动决策 → 归档建议: 启用 switched, 保存修改, back and saved again | automaticDecisions.form.open and two saves answered; the station's config has the rule · Tester 重放（src/sfreplay/flows/settings_decisions_test.mbt） |
| 87 device-pages | 下方栏: a place taken off, 用量 added; 本机缓存; 更新日志; 用量 → 价目表 | prefs.set barsBy, kept on the device; cache.usage answered with the test chat · Tester 重放（src/sfreplay/flows/settings_device_pages_test.mbt） |
| 88 workspace-people | Workspace → ＋: an email added; 移除; 图标: an emoji, then none | the cloud had the email added, then not; workspace.rename with the emoji, then none · Tester 重放（src/sfreplay/flows/settings_workspace_people_test.mbt） |
| 89 run-settings | the chat's agent → 历史 → 详情 → how it runs: 思考深度 high, saved | pick.set of session:<key> with the effort; pick.save answered · Tester 重放（src/sfreplay/flows/settings_run_settings_test.mbt） |
| 90 drive-download | a file of the lent folder held, ⋯ → 下载: 正在下载「说明.txt」, then 已保存到「下载」 | drive.read through the core; the device keeps the station's file byte for byte (macOS: MBUI_DOWNLOADS_DIR; Android: the emulator's Download/, as MediaStore named it) |
| 91 drive-download-many | in a folder of its own (drive-big), a 48 MB file and a small one chosen, 下载 2 个文件: the big one's row says how far, then gone; 已保存到「下载」 | the big file read in a dozen parts; both kept byte for byte · Tester 重放（src/sfreplay/flows/drive_download_many_test.mbt：大文件分段读、两个都留存；48 MB 逐字节比对由冒烟 90 负责） |
| 92 drive-zip | a folder held, ⋯ → 下载为 zip: 正在下载「子文件夹.zip」, 已保存到「下载」 | the station zipped it (drive.zip); the kept zip holds the folder's file, its words the same · Tester 重放（src/sfreplay/flows/drive_zip_test.mbt） |
| 93 share-files | files shared in (Android: an ACTION_SEND intent of a photo; macOS: a photo and a PDF): the sheet heads with them, the test chat tapped, the files in its composer going up, sent with words | the entry's attachments; the photo at the station byte for byte; on Android the intent's file taken in |
| 94 station-file-sent | ＋ → Station 文件, the novel ticked, 添加; its card's sheet: 文件; sent with words | drive.stage called; the entry's attachment is the file, no path line; the station keeps it byte for byte; Tester 重放（src/sfreplay/flows/station_file_sent_test.mbt） |
| 95 recent-photos | (Android) the photo put in the emulator's gallery; ＋: the strip shows it after the camera; tapped, it goes up; sent | the gallery read and ranked; the entry's attachment, the photo byte for byte at the station |
| 96 viewer | two pictures from the other device: the first grows from its thumbnail; ›; a swipe back; a box marked, its note said, 下载标注后的图片, 添加到对话, sent | imageNear stepped; the marks drawn by the host; the marked PNG kept on the device; the entry's attachment and the note's quote |
| 97 video-frames | a video from the other device: 120 帧 read from the file (wherever it has played to), ‹ ‹ ›, 保存此帧 | 120 frames read; ‹ then › one frame apart; the kept frame a PNG of 640 × 360 named by that frame |
| 98 reader | a novel in GB18030 (drive-gb) opened: its words; 排版 → 宋体; 下载 in the top bar | drive.read through the core; the serif face kept in the core's prefs; the kept file byte for byte · Tester 重放（src/sfreplay/flows/reader_test.mbt） |

Flows 70–75 (branch mbui-chat-complete, 2026-10-20, Studio): the whole suite on macOS 63 of 67 at first, then the four
again: 70 and 73 had checks macOS's grep and pbpaste read wrongly (fixed), 29 passed again (its composer row was 0.10,
the bar at 0.1), 47's fixed service port 18978 was another run's server; on Android (the emulator) 11 and 70–73 passed,
74 passed once run again (the app was gone once after its sideways drag), 75 hands the link over and so now ends at the
tap (the browser comes in front), passing on both. Android's words are ICU's (选 alone where macOS's tokenizer has 选中).

Flows 33–37 (branch settings, 2026-10-19; 22–26 on its first base, numbered after slice 8's 22–28, glass's 29 and
the new chat's and bottom bar's 30–32; the preview's 38 after them): the whole suite passed on macOS, and 33–37 on Android (the emulator; 36 once
alice's other device found its chat by all its words: it had taken an earlier run's of the same title). 36
archive-restore is not 72 bar-archive: 72 archives a chat from its bar, 36 finds one archived elsewhere on the 已归档
page and restores it.

Found by it and fixed: the app never told the core it was shown (`client.focus {visible, focused}`), so the core
never marked a chat read (the station's reads stayed empty: every chat opened at its first unread message however
often it had been read) and held back no notice for the chat on screen; it now does, as Home shows a workspace and as
the system says the app came to the front or left it (@hostapi.set_app_state). A scripted run counts as in front: on
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

## The PC (wide) frame (branch mbui-pc, 2026-10-19)

On macOS and Windows the app is a desktop's window (@sfapp.host_setup: 1280×820 at first, as still.fail's desktop app
opens, at least 360×560, its size not kept, the system's title bar). Laid out Medium or Large (@sf.layout, since
2026-10-24: a desktop's window from 600 wide, Large from 840; a phone's or a tablet's by its size classes) it is the
web app's wide frame (web/src/cloud/workspace.tsx WorkspaceShell), src/sfdesk/frame.mbt, Medium on a tape (the one in
use whole, the other showing past its edge, a press there bringing it over); Small, the phone's pages as before, live
as the window is resized: both draw the same stack (app.nav) over the same topics, the wide frame its top page alone in
its pane (@ui Ctx::nav_flat), the phone's sliding. How things answer the hand goes by what points (@ui.pointing), never
by the layout.

- The rail (Rail.tsx: 56 wide; 待处理's panel, 对话, 文件, Station, Profile, 连接, 用量, as the prefs' `rails` keep them;
  the workspaces' squares, the one in view marked; settings), the sidebar beside it on the same ground (240, its edge
  dragged from 180 to 480, pressed to fold it to the rail, ⌘\): the chats' list (新建对话 and the filter in its frosted
  band, the core's days, a row each: Sidebar.tsx ChatRow at 54 high, its time and 归档 on hover), or the settings' pages
  (SettingsNav: 返回会话, 客户端 / Station / Cloud, those in the rail left out), the stations' folders (FilesSidebar), the
  decisions waiting (奏's rows).
- The pane: a chat (ChatPage.tsx: its bar 45 high, the messages in a column 760 wide at most in its middle, the composer
  804 at most, Enter sends and ⇧Enter is a new line, 按空格输入 until it has the keyboard); the core's chat last open
  when the chats are come to, else a new chat (the web has no empty state: WorkspaceHome); every other page the phone's
  own under the web's page bar (settings' pages under the web's page head, in its column: wide_head, scroll_page).
- What opens over it (wide_pop.mbt): a row's menu from its right click (固定 / 取消固定, 重命名 in place, 保留 / 取消保留,
  复制会话链接, 归档), the filter's menu, 待处理's panel, ⌘K's switcher (the chats by their titles), ⌘/'s shortcuts.
- Keys (keymap.ts): ⌘K, ⌘N, ⌥↑ / ⌥↓ the chat before or after, ⌘\, ⌘,, ⌘/, Esc (what is open closed), Space (the
  composer), Enter / ⇧Enter; the list under the pointer scrolls by the arrows and Page keys.
- The pointer (mbui's desktop input): hover grounds as the web's (--hover; --selected on what is open), the hand on what
  is pressed, the I-beam on fields and the pane's words, col-resize on the sidebar's edge; the pane's words selected with
  a drag and copied with ⌘C (Ctx::selectable); a mouse wheel's notch eased in as a browser does, a trackpad's as it
  comes; a drag scrolls no list.

Not as the web yet: the new chat's composer is at the page's foot (the web's in its middle); the chat's side panel
(histories, jobs, files), its find bar and the drive's columns are the phone's sheets and pages; ⌘K finds chats by
their titles only (not messages, actions or settings); the rail is not changed from its menu (its places as the prefs
keep them); the macOS window has the system's title bar (mbui's @hostapi.window_setup `inset` puts the buttons in the
app's top row as the desktop app's are, not used yet); 复制 session 文件路径 is not in the row's menu.

Shots: `scripts/shots.sh wide` (mac-wide-<mode>[-dark] at WIDE_WIN 1280x800 over sffix's home, chat,
settings-appearance, files, decisions); `scripts/web-ref.mjs` takes the web's stories at the same sizes. Windows:
mbui's windows.yml run with `stillfail_ref` builds sffix against that mbui and shoots its wide frame.

## Motion (branch motion, 2026-10-19)

still.fail's motion as its Android app has it: docs/stillfail-motion.md catalogues every animation of the Android app
(where, what sets it off, what moves, its duration and curve or spring, its place in the Kotlin) and says what mbui has
of each. The framework, the motion package (src/motion) over ui's drawing (src/ui/draw.mbt), only ever changing what is drawn
(tapped where laid out, at once): Compose's curves, tweens and springs
(closed form, Compose's durations; checked against values printed by Compose's own classes, scripts/compose_ref.sh),
animated values kept by key (Animatable, animateFloatAsState), and a motion layer applied only when painting: looks
(opacity, offset, scale), keyed layout animation (FLIP; in a list by the list's content, so scrolling moves nothing),
a list's rows by key (rows in, rows out by a copy kept painted, rows passing over others, closing late), presence
(AnimatedVisibility), a height opening and closing, shared elements flown from a rect, reduced motion (the host's
setting). On the screens: Home's rows as the list changes (and held while a finger is on it), marks popping in, a
chat's new rows rising, the list gliding after what comes, an activity opening, staying and fading, gliding when
pushed, words sent flying from the field into their bubble with the rows above going up with them, the composer's
change of shape, the way to the newest, toasts, ＋'s sheet on the sheet's spring, the filter's menu, pressed grounds on
the ripple's timing. MBUI_MOTION_LOG=1 logs every moving frame; scripts/record.sh records a motion on macOS frame by
frame (MBUI_RECORD), `scripts/android.sh record` on the emulator, scripts/motionplot.py compares the frames with the
Android app's curves. scripts/film.sh films one with no window (src/sffilm, mbui's film): the same script run in a
Tester of the Mac's text and pictures, each frame drawn by the Mac's renderer offscreen and written into an MP4 at its
moment, so a change's old and new are the same run frame for frame (`scripts/film.sh side` puts two side by side). At rest nothing of it is drawn: every picture is unchanged.

## A chat's messages in motion (branch mbui-chat-complete)

The motion branch's rows rising in, the list gliding after them, the activity's glide and the words flying from the
composer into their bubble (docs/stillfail-motion.md), and now an agent's answer coming out of its activity's avatar
(src/sfapp/emit.mbt, ChatMotion.kt): an answer said while its agent's activity shows (the reader at the end, the app in
front) waits out of the list; the activity's line folds to its avatar (170 ms), a copy of the avatar hops to where the
answer goes (440 ms: up 34 over the higher end in 42% of the time, then falling ever faster, stretched), the answer
comes out of it (380 ms: from 35% at its corner, unrolling from its top, the avatar flattened and springing back), and
the avatar goes home (320 ms); the same agent's next answer waiting, it drops on to it (280 ms). Not watched, all of
it at once. Each frame of the flight is in the motion log (`emit/<seq> pose=…`). The fixture's agent now works on
what is sent (its activity shows) and answers while the chat shows, so sffix plays it.

## Opening links outside the app (branch selection-links in mbui, mbui-chat-complete here)

`@hostapi.open_url` (and `Ctx::open_url`, `@ui.open_url`) hands a URL to the system: Android's ACTION_VIEW (a task of its
own, the browser or the app that takes the link), macOS's NSWorkspace, iOS's UIApplication, Windows' ShellExecute
(http, https and mailto only), the browser's window.open (noopener). A scripted macOS run (MBUI_SCRIPT, MBUI_DRIVE)
only says it on the log (`open-url: …`). In use: a link tapped in a message (App.kt's UriHandler: a chat's own link
opens it here, any other goes out; 无法打开此链接 when nothing takes it), a link's menu's 打开链接, a login card's pill
(复制并打开 copies the device code and opens its page; 在浏览器里登录 opens the page, a loopback login once the core
listens for its callback, `machineLogin.open`; LoginCards.kt), a service page's link elsewhere (PreviewWeb.kt leave).
The Android app opens a login's page in a Custom Tab; here it is the browser (no Custom Tabs in the host yet).

## iOS (branch mbui-ios, 2026-10-19)

`APP=stillfail scripts/ios.sh build | run` builds still.fail mbui for the iOS simulator and runs it on a simulator of
its own (`MBUI_IOS_DEVICE`, default ios-mbui-sf): the same pages as Android and macOS, the core in Hermes (the same
`core.hbc`, src/host/apple_core.mm built for aarch64-apple-ios-sim with the Rust shell built for that target, Hermes's
xcframework slice in the app's Frameworks; core/README.md, "iOS"). mbui's scripts/ios.sh takes an app of this module
(MBUI_APP_MOD, a hook as Android's: scripts/ios-core.sh) and its host (ios_app.m) does what still.fail asks of it:

The app on iOS is Android's, as on an Android phone (2026-10-23):

- Edge to edge (ios/Info.plist's MBUIEdge, as Android's manifest dev.mbui.edge): the view from the screen's top to its
  foot, the status bar's and the home indicator's room said as the system's `bars`, each page padded where Android's
  is (src/sfapp/bars.mbt); round it, and at launch, the page's paper (MBUIGround; the launch screen's Paper colour),
  the status bar's words to match (`@hostapi.set_dark`).
- Its layout chosen by what the system says of the window, as on Android (src/hostapi/system.mbt `size_class`,
  `fold`; @sf.layout): regular in width said as medium under 840 points and expanded from there, the web's wide frame
  in the phone's theme, Medium on its tape, Large its sidebar ending on a fold that stands upright; the hinge
  (UIHingeInteraction) and where its fold
  divides the view (the view's division regions), iOS 27.1 on and built with its SDK (mbui.yml's ios job, on Xcode
  27.1): half open with the fold across the view, a chat's page across it, its messages over the fold, its composer
  and the latest chats under it (src/sfapp/tabletop.mbt).
- From side to side too: the safe area's sides said as `bars` (an iPhone Duo's outer screen has its status bar down
  its right side), the pages beside them on the page's paper (src/sfapp/sides.mbt).
- The keyboard as Android's: the view keeps its size, the keyboard's top followed frame by frame as the system moves
  it (UIKeyboardLayoutGuide's motion read off a mark's presentation layer), the app laid out above it; the keyboard
  asked for plain text, no capitals or curly quotes of its own, its return key a new line (a search field's its search
  key); put away by the person (not the app), the field lets go of the focus.
- Its touches and fields feel as Android's (@sfapp.host_setup: `@ui.feel_as(2)`): lists fling and give at their edges
  as Compose's (their scroll bar mbui's own, as on every host: src/ui/scroll_bar.mbt), a field takes a tap as it
  lifts, draws Compose's caret and handles, picks words by a long press or a double tap, with the system's floating
  edit menu over them (UIEditMenuInteraction: 剪切, 拷贝, 粘贴, 全选, as Android's ActionMode).
- Back: the left edge's swipe is the app's own (src/ui/nav.mbt), as on every host; iOS has no system back of its own.
- `secure.*` in the Keychain; the sign-in through ASWebAuthenticationSession (`stillfail` scheme), as on macOS. A
  login card's page in Safari's view over the app (SFSafariViewController, Android's Custom Tab): the app stays in front
  under it, the core's loopback listener answering the page.
- Pictures and files picked (PHPickerViewController, JPEG for the library's HEIC as Android's; UIDocumentPickerViewController),
  a photo taken (UIImagePickerController's camera), ＋'s recent photos (Photos: all of the library, or the photos
  chosen, its picker of more as Android 14's), the share sheet (UIActivityViewController), the app in front or not
  (`@hostapi.set_app_state`), its time off the screen (`shown`), the network changed (`network`), its links (`link`:
  a universal link, a URL of its scheme), a film sideways (the status bar and home indicator out of its way).
- Notifications the system's (UNUserNotificationCenter; no pushes: APNs wants a signed app, as Android's FCM is not
  done either). The build's number (CFBundleVersion: main's commits, as Android's versionCode) in 设置's version row
  and told to the core, which names the device still.fail mbui iOS · <its model> and says messages came from `ios`.
- Scripted runs (src/ui/drive.mbt): the keyboard's calls on the view, the paste, the app's picture, notifications
  tapped; the log on stderr (`simctl launch --stderr`).

- Sharing in (the person's choice, 2026-10-23: an iOS share extension cannot open its app): the share sheet's still.fail
  mbui (ios/Share-Info.plist; mbui's src/host/ios_share.m, PlugIns/Share.appex) keeps what is shared in the app group
  the two share and says to open the app; the app takes it as it next comes to the front (`@hostapi.shared_in`) and
  shows the same 发到 sheet as Android's, over itself (not over the app it came from).

Not yet, against Android: a signed build for a device and TestFlight (they need the Apple developer account, its
profiles the app group too), updates (the App Store's, not the app's).

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

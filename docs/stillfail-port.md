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
it, so no new-chat button here), the search page, the long-press menu (pin, rename, copy link)
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
words are), the text toolbar of the field
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
  web-drive` compares them with goldens/mac-<mode>.png and web-<mode>.png.

Not yet, against the current app: the player (the rest of slice 12), downloading a file to the device, sharing it
to another app, a folder as a zip (each says so in a toast: no host API to keep a file yet), GB18030 text (no
table here: such a file opens as UTF-8 with replacement characters), the serif face (the reader draws its sans
face either way), 跟随's swatch drawn half and half on a diagonal (here the dark page as a disc in the light one),
the system bars' icons following the paper, the frosted glass of the bars and sheets (their tint only), the
system's back closing a sheet or ending a choice (it goes back a page), dragging sheets by the grabber, the
long-press ripple, a station file sent as a file (`drive.stage`, the card's sheet, 此对话默认发送文件) and station
files kept with the draft on the device, the station page's way into a drive (slice 13).

Slice 8, decisions, history, tool steps, a chat's sheets, jobs (branch decisions, 2026-10-19): what a chat asks is
answered from it, and an agent's work can be looked into (src/sfapp/decide.mbt, sheets.mbt, history.mbt,
decisions.mbt; Decisions.kt, Chat.kt AskDismiss and ArchiveUnder, LoginCards.kt, ChatInfo.kt, AgentSheet.kt, Jobs.kt,
OpenJobs.kt, History.kt, ui/ToolStep.kt, ui/Sheet.kt):

- The cards in a chat do what they say: an options card's option tapped answers it (`decision.answer`: the core sends
  the viewer's message quoting the post, or, for an option the agent made with action=close, closes the card with no
  message: `decision.close`), a spinner on it meanwhile, its row pressed as the Android app's ripple; 忽略 lets the ask
  go (`decision.dismiss`), at once, back if it failed; 保留 (`chat.keep`, 已保留… said) and 归档此对话 under the last
  all-done post, as the bar's 归档 (`chat.archive`: Home at once, 已归档 said); a login card for one who may finish it
  (the station's `machineLogins.canLogin`) says what to do now by its step, with its pill and 取消
  (`machineLogin.cancel`). Anything that fails is said in a toast (无法…：…), as AppState.act says it.
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
  compares them with goldens/mac-decide-*.png and web-decide-*.png.

Not yet, against the current app: code highlighting in tool steps (code is drawn in the code face, in the ink) and a
capped block's own scroll (it is cut at its height); the run settings page (RunSettings: its rows are shown, not
opened); the station's card from an agent's; a service's page (Preview.kt) from its row; sharing the chat with other
workspaces and making it public (their rows are shown); a watched chat's question before archiving; opening a login's
page in the browser (there is no URL hand-off on the hosts yet: its pill copies the link or the code and says so); the
reply on the 奏 page takes words only (no files, quotes or its own draft kept by the core) and its card neither tilts
nor shrinks as it goes (boxes have no rotation or scale yet); a sheet dragged by its grabber; the segmented control's
sliding thumb; a history opened at an entry; a Slack user's 这是我.

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
- Liquid glass (the demo's MBUI_SCREEN=glass, not on still.fail's pages): each shape's rounded-box distance, the
  shapes of a `glass_group=true` box drawn first as one capture and merged by a smooth minimum (`merge`); what is
  under it bent along a bezel (`bezel` wide, by up to `refraction`, a circle's profile), the colours split by
  `chroma`, a rim lit from the top left; text in it (`adaptive`) is a glyph kind of its own (7) whose ink the
  renderer picks from how light the copy is round the glass's middle.
- Solid where the system asks for less transparency: macOS's and iOS's Reduce Transparency, Windows' transparency
  effects off, the browser's prefers-reduced-transparency (asked every 30 frames); Android has no such setting.
  MBUI_GLASS=solid (or `@ui.set_glass_solid`) forces it; solid is the glass's `solid` ground (the paper under its tint).
- `@host.gpu_ms` (Metal's command buffers' times; -1 elsewhere) goes into the in-app bench's lines (MBUI_BENCH=1);
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
- The bar and its sheets with nothing blurred yet: `bar_ground` (bar.mbt) is the bar's colour where the Android app
  has no blur (Glass.kt floating: --raised at 72% over the paper; the ball that and white at 42%; 令 the accent at
  86%), the one place it is chosen, and `sheet_ground` (sheet.mbt) the sheet's (the paper, the scrim's black, the
  surface at 80%). The glass (above) has `glass_bottom_bar`, `glass_bar_ball`, `glass_action` and `glass_sheet` for
  them, but the notch is cut out of the bar as Bar.kt's outline has it (the circle and its two fillets), drawn from
  rounded rectangles and a ring in clips so the page shows through it, and a ring is not a shape the glass pass
  takes: the bar goes on glass with that. A new chat's choices over the composer are on the composer's glass
  (`glass_floating`). The rim is a hairline here; the shadow is cast below and to the sides only.
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
  `scripts/shots.sh newchat web-newchat` compares them with goldens/mac-newchat-*.png and web-newchat-*.png. Home's
  goldens (mac-home, mac-home-dark, mac-home-sheet, mac-home-swipe, web-home, and slice 8's mac-decide-home-jobs and
  web-decide-home-jobs) changed on purpose: the bar on Home, the workspaces' sheet in the new sheet.
- MBUI_DRIVE has `drag X Y DX DY [MS]` and `dragon DX DY MS TEXT` (a finger moved a frame at a time, then lifted).

Not yet, against the current app: the bar's and the sheets' frosted glass (see above), the bar chosen in the panel sliding
down into the bar's place (here the panel closes and the bar is the chosen one at once), the notch's icon swapping
between 令 and a page's ＋ with its short scale and fade (here it changes at once), the stations' place's glyph of their states (the
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
  panning it when larger, the wheel zooming round the pointer; a video played by the system's player in a native view (below), its bytes read through
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
  first, doubling to 4 MB while reads run on, served from the window around the extractor's reopenings), each read
  asked of the app (`view_read_next`) and answered from the core (`view_read_answer`); the page is a WebView with the
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
- `APP=sffix MBUI_FIXTURE=chat-preview-image|pdf|video|html|code|md|csv|none` opens a made-up file
  (src/sfapp/preview_fixture.mbt: a picture, a PDF of two pages, a video whose reads are never answered, a page with a
  script, code, Markdown, a table, a file of no kind): `scripts/shots.sh preview web-preview` compares them with
  goldens/mac-preview-*.png and web-preview-*.png.

Not yet, against the current app: the flight from the chat's thumbnail and back (a video closed into its thumbnail at
the frame it was left at), stepping through the chat's images (`imageNear`) and swiping between them, pinching on iOS (its host
tells no second finger yet), marking an image (ImageMarks.kt), a video's
frame-exact steps (the file's frames' times, MediaExtractor; here steps of a 60th of a second), saving a frame,
landscape, audio's own small player (audio plays in the video's), code highlighting and a code file's sideways scroll,
installing an APK, an SVG drawn by a page when it is not a bitmap, the progress of a whole file coming (`progress`), a
big file read to the disk, a web view's own scrolling under the canvas on macOS while something is painted over it,
the frosted glass over a picture or a document (where nothing native is under it: `@sf` glass could take it).

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
| 22 answer-option | the agent posts an options card (e2e/fake: `card:`), the recommended one marked; one tapped (decision.answer); 你 选择了「…」 under it | alice's message with the option's words, quoting the post; the card as posted, `recommended` on the one |
| 23 dismiss | another card; 忽略 tapped: it and the options go at once (decision.dismiss) | `dismissed` has alice's row for the post; nothing answered |
| 24 close-option | a card with an option made to close it (action=close) tapped | `closed_cards` has the post; no message sent for it |
| 25 archive | a chat made on the other device (before the app starts: `#before`, see below) ends all done; opened, 归档此对话: 已归档, Home without it | the session the app archived and its thread put away by hand (`archived_by`, `hidden_by` manual; its entries leave the live tables); the test chat not |
| 26 history | the agent does steps (e2e/fake: `steps:` writes its transcript); "…" → its row → its card → 历史: received and posted, the group opened, the command opened to what it printed | the agent's post; its transcript (what the history is read from) has the steps |
| 27 pin | "…" → 固定到列表顶部, then 取消固定 | the station's `pins` has alice's for the chat, then none |
| 28 decisions-page | the 奏 page (MBUI_OPEN_PAGE=decisions, a flow's `#env`); the other device asks with a card; the option tapped there; 奏折已全部批完 | alice's answer quoting the post |
| 29 glass | four long messages sent from the composer's glass; the newest run under the top bar's glass, then, scrolled up, under the composer's | the four entries, as alice's; on macOS the bar's and the capsule's rows in the shots are not flat (what is under them shows through, blurred) |
| 30 new-chat | 令 in the bar's notch: the new chat rises; the first message typed and sent; the page becomes its chat; the agent's answer comes there; back on Home | the station's entry: the words, once, alice's, in a thread of their own; the agent's answer in that thread; alice's other device lists the chat |
| 31 places | 文件 tapped on the bar (the drive's page in place); the bar drawn up into the other bar's panel and let go on 奏 (that bar, 奏's page); 用量; the panel again, back on the chats | the bar chosen kept as the workspace's in the core's store on the device (`prefs.set {barsBy}`) |
| 32 sheet-drag | the workspaces' sheet drawn up to 94% and dragged closed; a new chat's station sheet dragged a little (back) and past 80 (closed), opened again and its station tapped | the sheet's settling as the app logs it; the core took the pick (`newChat.pick` answered) |
| 38 preview | the other device makes a chat with a picture, a PDF, a video and a page (`peer createfiles`: put up in parts, then the chat made with them, so the test chat's end stays as the other flows know it); opened from Home, each file opened in the preview, shot, closed | the station's entry has the four files; the app's log: the picture and the page read through the core, the PDF's 2 pages drawn, the player's reads through the core (`station.file.part`) and its first frame, the page loaded in the web view; each shot shows something in its place (e2e/pngstat.py) |

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

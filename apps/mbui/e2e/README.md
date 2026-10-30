# End to end, against a still.fail of its own

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
| 29 glass | four long messages sent from the composer's glass; the newest run under the top bar's glass, then, scrolled up, under the composer's | the four entries, as alice's; on macOS the bar's and the capsule's rows in the shots are not flat (what is under them shows through, blurred) · Tester 重放（src/sfreplay/flows/glass_test.mbt：顶栏和输入框的毛玻璃下压着消息的字，窗口 700 高，Tester 的字体折行比真机少） |
| 30 new-chat | 令 in the bar's notch: the new chat rises; the first message typed and sent; the page becomes its chat; the agent's answer comes there; back on Home | the station's entry: the words, once, alice's, in a thread of their own; the agent's answer in that thread; alice's other device lists the chat；Tester 重放（src/sfreplay/flows/new_chat_test.mbt） |
| 31 places | 文件 tapped on the bar (the drive's page in place); the bar drawn up into the other bar's panel and let go on 用量 (that bar, 用量's page); 已归档; the panel again, back on the chats | the bar chosen kept as the workspace's in the core's store on the device (`prefs.set {barsBy}`)；Tester 重放（src/sfreplay/flows/places_test.mbt） |
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


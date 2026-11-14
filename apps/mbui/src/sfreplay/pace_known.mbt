///|
/// The flows whose pace pass (orders: the strict pass again with run_for's frames at 7 a second, and at 120) tells
/// the core otherwise than the strict pass, by trace, at which rates: each stops at its first split (PACE-SPLIT says
/// where, message by message). Only falls: a flow that splits and is not here fails, one here that splits no more
/// fails till it is taken out. A cause mended a layer down may show the next one further on, the flow still here.
/// Grouped by the first message apart (the pace pass's | the strict pass's); the cause said where it was traced, the
/// rest by what shows: what the app reads of the core it asks as a frame is built, so a sparser display's frames
/// ask it later than an input that came meanwhile (the coordinator of the migration, 2026-11-11: the next step,
/// what a page reads said as it is made).
///
/// It rises only where the measure came truer (the coordinator of the migration, 2026-11-11), never for the app: each
/// flow so added shows the app unchanged and the split a device's already, and the migration's coordinator agrees.
/// Once so: #5519 (the fake host tells what is posted at the moment it is posted, as a device's host does, no longer as
/// the next frame begins; not a line of what a device runs changed) took 120 a second from 10 flows to 11: share and
/// station-files out, glass, settings-run-settings and wide-answer-reply in (each says why where it is).
// kept across runs: a value
let pace_splits_known : Map[String, Array[Int]] = {
  // 20: sub {"scope":…,"topic":"stations"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  // (the first tap on a chat's row comes before the frame that builds Home's list and sends its reads (they go
  // out as a frame is built): at 7 a second it falls on the bar under it, Station's tab (glass: Home's
  // subscriptions at 1159 here, 1033-1050 in the strict pass; the tap at 1150))
  "agent-reply": [7],
  "answer-option": [7],
  "bar-going-down": [7],
  "card-motion": [7],
  "close-option": [7],
  "delete-failed": [7],
  "glass": [7],
  "history": [7],
  "markdown": [7],
  "open-link": [7],
  "pick-words": [7],
  "quote": [7],
  "send-flying": [7],
  "send-paced": [7],
  "service-page": [7],
  "station-file-sent": [7],
  // 6: sub {"topic":"workspace","workspace":…} | strict sub {"topic":"doing"}
  "drive-lend": [7],
  "drive-play": [7, 120],
  "drive-rename": [7],
  "drive-zip": [7],
  "reader": [7],
  // 6: unsub {"topic":"status"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "dismiss": [7],
  "paste-long": [7],
  "paste-short": [7],
  "pin": [7],
  "station-files": [7],
  // 5: sub {"query":…,"scope":…,"topic":"search"} | strict call cache.usage {}
  "settings-profile": [7],
  "settings-station-mark": [7],
  "settings-station-settings": [7],
  "settings-workspace-people": [7],
  "station-rename": [7],
  "settings-decisions": [7],
  // 4: - | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "notice-looking": [7],
  // wide-answer-reply at 120 (#5519): the new chat page sends its composer, machineSessions.list and status's
  // release in the frame at 1050 ms, notify.permission (sent once notify's values are in, which came after that
  // frame) in the next, at 1058.3; the strict pass sends all four in its frame at 1083.3, notify.permission before
  // machineSessions.list; gone with what a page reads said as it is made
  "wide-answer-reply": [7],
  "wide-send": [7],
  // 3: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict sub
  // {"topic":"chat","compact":true,"session":…,"station":…}
  "viewer": [7],
  // 3: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict call cache.usage {}
  "settings-connect": [7],
  "settings-device-pages": [7],
  "settings-vault-item": [7],
  // 3: sub {"query":…,"scope":…,"topic":"shareIn","source":…} | strict sub {"topic":"notify"}
  // (120, seen once its rows were held: shareIn let go of before driveTransfers in the strict pass, after it at 120.
  // shareIn is read by the share sheet's old view as its frame builds (src/sfapp/share.mbt:445, share_parts,
  // MB_OUTSIDE_SHARE's cause), so it is let go of by the first frame that no longer builds it: probed, at 1999.98 in the
  // strict pass (the run's frame) and 1991.67 at 120 a second, each a frame's moment; driveTransfers, the shell's,
  // declared, at 2000 and 1983.33. Goes with share_in_frame)
  "share": [7, 120],
  "share-files": [7],
  "share-new-chat": [7],
  // 2: unsub {"topic":"status"} | strict sub {"topic":"workspace","workspace":…}
  "bar-glass": [7],
  "places": [7],
  // 1: - | strict call lock.pair {"workspace":…}
  "lock-wait": [7],
  // 1: sub {"scope":…,"topic":"stations"} | strict sub {"scope":…,"topic":"newChat"}
  "new-chat": [7],
  // 1: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict call notify.permission
  "notice-cancel": [7],
  // 1: - | strict call link.parse {"url":…}
  "notice-failed": [7],
  // 1: - | strict sub {"topic":"stationNet","station":…}
  "settings-add-station": [7],
  // 1: unsub {"topic":"doing"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "settings-run-settings": [7],
  // 1: - | strict call composer.starting {"key":…,"starting":true}
  "wide-new-chat": [7],
  // 1: - | strict call session.warm {"key":…,"station":…}
  "wide-newline": [7],
  // 1: unsub {"topic":"doing"} | strict sub {"scope":…,"topic":"newChat"}
  "wide-places": [7],
  // 1: sub {"topic":"workspaceMarks","workspace":…} | strict sub {"scope":…,"topic":"longJobs"}
  "wide-resize": [7, 120],
  // 1: - | strict call chat.pin {"pinned":true,"session":…,"station":…}
  "wide-row-menu": [7],
  // 1: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict sub {"limit":60,"scope":…,"topic":"archive"}
  // (the replay's rig, not the app (#5589, measured): the strict pass's tap on the filter key at 1983.3 ms draws the
  // frames it leaves owed at once, its clock on to 2016.7, the pace pass's draws none till the display's next; at 7 a
  // second the menu is not up where 已归档 was at 2150, the tap on it falls on nothing, 已归档 never opens and 还原's at
  // 2733.3 falls on Home's chat row. The menu itself stands the same at every rate a moment after its press (the
  // library's presenters and Home's own, 60, 120, 24, 7). Taken out by the PR that gives the strict pass its inputs as
  // the pace pass's are given, at their moments, frames drawn only as the clock passes them)
  "archive-restore": [7],
  // 1: sub {"query":…,"scope":…,"topic":"search"} | strict call notify.permission {"state":"unknown"}
  "wide-switcher": [7],
}

///|
/// What the pace passes came to split at, besides pace_splits_known, as the replay came to give each message at its own
/// moment and its strict pass the run's steps at the run's moments (the replay's rig, the coordinator of the migration,
/// 2026-11-12): a split each, untraced yet, found where a stop before it had hidden it or where the measure came truer.
/// Held as pace_splits_known is, and only falls: each is traced in turn and goes with its cause.
// kept across runs: a value
let pace_splits_untraced : Map[String, Array[Int]] = {
  // (each split as PACE says it in the flow's run)
  "drive-sheet-closing": [7],
  "wide-switcher": [120],
}

///|
/// The flows whose strict pass asks what their run did not, known, by trace: each ask exactly, in its order, at its
/// moment on the app's clock; any other is the flow's failure as ever, and one that asks it no more fails till it is
/// taken out. Only falls (the coordinator of the migration, 2026-11-11: no ask allowed by its kind, no trace recorded
/// again over one).
// kept across runs: a value
let strict_diverged_known : Map[String, Array[(Double, String)]] = {
  // drive-download-many (recorded again for bell_lit): its run's app was started on the files' page (the trace's
  // `MBUI_OPEN_PAGE=files`), the replay's opens it as a step (Flow::open_page) once the first screen is up. So the
  // replay's app first lands the wide frame's pane, declaring the new chat as the marks are answered (1093.9), and lets
  // go of it as the files' page comes on top, a frame's moment there, the shell's `doing` handed over from the page
  // before let go of and asked again with it. The run's app asked none of it. The replay's way of opening the page, not
  // the app's: goes as Flow::open_page starts the replay's app on the page as its run's was
  "drive-download-many": [
    (1093.92529296875, "{\"id\":19,\"subscribe\":{\"topic\":\"newChat\",\"scope\":\"01M76NSCTQ86BGR7W0YS3R5G21\"},\"keyed\":true}"),
    (1566.6666666666665, "{\"id\":19,\"unsubscribe\":true}"),
    (1566.6666666666665, "{\"id\":12,\"unsubscribe\":true}"),
    (1583.3333333333333, "{\"id\":26,\"subscribe\":{\"topic\":\"doing\"},\"keyed\":true}"),
  ],
  // lock-wait (#5519; anew with what the first screen reads declared, #5589; anew with notify.permission told as
  // notify is answered, between frames, #5613: it takes the id before doing's and driveTransfers', and what the
  // replay held for it comes a frame sooner): at 22116.7 the lock's delta (safe mode off) takes the waiting page away
  // and with it what it had taken over of what was declared as the workspace came in view, doing and driveTransfers
  // (taken over, then its reader gone, the next not come yet: a gap a declaration does not mend); Home's frame at
  // 22133.3 asks doing again. The run's device took it in the frame that built the next page, behind a message before
  // it, so nothing was let go. Gone with #5135 (what is read kept by its topic while a page is covered), whose merge
  // takes this out.
  "lock-wait": [
    (23096.97412109375, "{\"id\":13,\"unsubscribe\":true}"),
    (23096.97412109375, "{\"id\":14,\"unsubscribe\":true}"),
    (23100.0, "{\"id\":24,\"subscribe\":{\"topic\":\"doing\"},\"keyed\":true}"),
  ],
}

///|
/// How long after the last message its run had before its first step each flow's first step found what it waits for
/// so (its first screen: Flow::first_screen), in ms and the display's frames drawn meanwhile, in the strict pass. Its
/// waits before that step wait (the moments there are those of the app that recorded the run, before #5589 and #5618,
/// asking otherwise as it started), so how long the first screen takes is measured here instead: only falls, each
/// flow's ms and frames at most its own, one under them to be brought down (the coordinator of the migration,
/// 2026-11-12: B). Once the traces are recorded again under the strict pass's moments, those waits are assertions and
/// this goes.
// kept across runs: a value
let first_screen_known : Map[String, (Double, Int)] = Map([])

///|
/// The traces recorded before a run kept its display's frames (`{"frame":…}` lines, mbui's @ui.trace_frames): their
/// strict pass's frames on a grid of their own, a phase apart from the run's, so whether a step's screen was so at the
/// run's moment for it is measured there, not judged (LATE-UNFRAMED; the coordinator of the migration, 2026-11-12: a
/// phase guessed from the steps' moments would still be a frame's building off). Only falls: each trace recorded again
/// keeps its frames and leaves it; a new one is recorded with them.
// kept across runs: a value
let frames_unrecorded_known : Array[String] = [
  "agent-reply",
  "answer-option",
  "appearance-kept",
  "archive-restore",
  "bar-archive",
  "bar-glass",
  "bar-going-down",
  "card-motion",
  "chat-audio",
  "chinese-enter",
  "close-option",
  "delete-failed",
  "dismiss",
  "draft",
  "draft-restart",
  "drive-delete",
  "drive-lend",
  "drive-list",
  "drive-play",
  "drive-read",
  "drive-rename",
  "drive-sheet-closing",
  "drive-upload",
  "drive-zip",
  "glass",
  "history",
  "home-new-chat",
  "lock-wait",
  "mark-read",
  "markdown",
  "new-chat",
  "notice-cancel",
  "notice-failed",
  "notice-looking",
  "notify-off",
  "offline-retry",
  "open-link",
  "paste-long",
  "paste-short",
  "pick-words",
  "pin",
  "places",
  "quote",
  "reader",
  "send-card-paced",
  "send-flying",
  "send-paced",
  "send-text",
  "service-page",
  "settings-add-station",
  "settings-appearance",
  "settings-connect",
  "settings-decisions",
  "settings-device-pages",
  "settings-profile",
  "settings-run-settings",
  "settings-sheet-sinking",
  "settings-station-mark",
  "settings-station-settings",
  "settings-vault-item",
  "settings-workspace-people",
  "share",
  "share-files",
  "share-new-chat",
  "sheet-drag",
  "sheets-sinking",
  "station-file-sent",
  "station-files",
  "station-rename",
  "video-frames",
  "viewer",
  "wide-resize",
  "wide-row-menu",
  "workspace-members",
]

///|
/// The flows whose strict pass (orders' first: the run's steps at the run's moments, src/sfreplay/steps.mbt) fails, by
/// trace: its first failure as it says it, and what it is, traced to its line, or "untraced". A new measure's baseline
/// as it came in (the coordinator of the migration, 2026-11-12), only falls: a flow failing otherwise, or one here that
/// fails no more, fails. The flow's own checks are the lenient pass's, whole, whatever its strict pass came to.
/// drive-download-many's and wide-places' are one kind, untraced yet: nothing moves at the run's moment, and what the
/// step waits for is the core's next answers, which the replay gives later than the run's moment; which of the replay's
/// steps makes them late is to be found (the coordinator of the migration, 2026-11-12), both to go with it.
// kept across runs: a value
let strict_known : Map[String, (String, String)] = Map([
  (
    "drive-download-many",
    (
      "src/sfreplay/flows/drive_download_many_test.mbt:38:5-38:22@stillfail: not so at 3544.971435546875 ms, the run's moment for it (its timeline 0 ms later from its first step): so at 3665.17822265625 ms, 120.206787109375 ms later",
      "untraced (probed frame by frame): nothing moving but the download's toast; what it waits for is the core's answers to the folder opened, which the replay gives later than the run's moment (3580.1 to 3649.2 ms): the replay's moment of giving, it seems, not the app's",
    ),
  ),
  (
    "chat-audio",
    (
      "its motion at rest at 3795.85693359375 ms, 966.98583984375 ms after the run's next step (2828.87109375 ms; its timeline 81.203125 ms later from its first step); said since the last step that acted: the bar's springs, told at src/sfapp/bar.mbt:170:12-170:102@stillfail (at rest at 3184.2972278094203 ms) | bar/k to 0, told at src/sfapp/bar.mbt:300:3-300:36@stillfail (at rest at 3184.2972278094203 ms)",
      "untraced: the bar's springs still moving as the run's next step came (src/sfapp/bar.mbt:170, :300)",
    ),
  ),
  (
    "draft",
    (
      "its motion at rest at 3290.177388696544 ms, 189.09438088404386 ms after the run's next step (3101.0830078125 ms; its timeline 21.912109375 ms later from its first step); said since the last step that acted: the bar's springs, told at src/sfapp/bar.mbt:170:12-170:102@stillfail (at rest at 3290.177388696544 ms) | bar/k to 0, told at src/sfapp/bar.mbt:300:3-300:36@stillfail (at rest at 3290.177388696544 ms) | a stack's slide, told at src/ui/nav_view.mbt:362:7-362:68@mbui (at rest at 2902.3291015625 ms) | Anim \"composer/hint\" to 1, told at src/sfpages/composer.mbt:915:5-915:105@stillfail (at rest at 3066.6666666666665 ms) | Anim \"composer/hint\" to 1, told at src/sfpages/composer.mbt:915:5-915:105@stillfail (at rest at 3100 ms) | Anim \"composer/send/able\" to 1, told at src/sfpages/composer.mbt:1022:14-1022:124@stillfail (at rest at 2740 ms) | Anim \"layout composer/box\" to 1, told at src/motion/layer.mbt:1576:3-1576:47@mbui (at rest at 2900 ms) | Anim \"layout composer/extras\" to 0, told at src/motion/layer.mbt:1576:3-1576:47@mbui (at rest at 2900 ms) | Anim \"layout composer/part/words\" to 0, told at src/motion/layer.mbt:1576:3-1576:47@mbui (at rest at 2900 ms) | Anim \"layout composer/notices/01M6W4XGV9R8EP2T8MEXHXRZSC/0542fc65aeac537e7b415361c87bd78e6109b4bc5957f0c782439cd3a4cff4a6:chat:c-4d386bcc584806fc879106a02c56a9a4\" to 0, told at src/motion/layer.mbt:1576:3-1576:47@mbui (at rest at 2900 ms) | a list's rows' heights, told at src/ui/list.mbt:1005:5-1005:92@mbui (at rest at 2900 ms)",
      "untraced: the bar's springs, the stack's slide and the composer's ways still moving as the run's next step came",
    ),
  ),
  (
    "settings-add-station",
    (
      "its motion at rest at 2295.209228515625 ms, 16.55908203125 ms after the run's next step (2278.650146484375 ms; its timeline 13.2421875 ms later from its first step); said since the last step that acted: Anim \"ripple\" to 0.5, told at src/motion/ripple.mbt:124:5-124:56@mbui (at rest at 2400 ms)",
      "untraced: a press's ripple still moving as the run's next step came (mbui/src/motion/ripple.mbt:124)",
    ),
  ),
  (
    "settings-workspace-people",
    (
      "its motion at rest at 2817.304931640625 ms, 66.697021484375 ms after the run's next step (2750.60791015625 ms; its timeline 37.575927734375 ms later from its first step); said since the last step that acted: ",
      "untraced: a motion at rest 66.7 ms after the run's next step, nothing said since the last step that acted (50 ms later since #5953: the add panel's note a line longer, its sheet taller)",
    ),
  ),
  (
    "share-files",
    (
      "its motion at rest at 1466.6666666666665 ms, 60.553629557291515 ms after the run's next step (1406.113037109375 ms; its timeline 0 ms later from its first step); said since the last step that acted: image \"mem:share-in/1\" fading in, told at src/ui/image.mbt:741:5-741:63@mbui (at rest at 1300 ms)",
      "untraced: an image fading in as the run's next step came (mbui/src/ui/image.mbt:741)",
    ),
  ),
  (
    "share-new-chat",
    (
      "its motion at rest at 1466.6666666666665 ms, 6.895670572916515 ms after the run's next step (1459.77099609375 ms; its timeline 0 ms later from its first step); said since the last step that acted: the bar's springs, told at src/sfapp/bar.mbt:170:12-170:102@stillfail (at rest at 1096.608154296875 ms) | image \"mem:share-in/1\" fading in, told at src/ui/image.mbt:741:5-741:63@mbui (at rest at 1300 ms)",
      "untraced: the bar's springs and an image fading in as the run's next step came",
    ),
  ),
  (
    "wide-answer-reply",
    (
      "src/sfreplay/flows/wide_answer_reply_test.mbt:14:5-14:17@stillfail: not so at 1230.647216796875 ms, the run's moment for it (its timeline 0 ms later from its first step): so at 1246.647216796875 ms, 16 ms later",
      "traced: as the new chat's page leaves for the chat (src/sfbase/fresh.mbt:81, :84, the old view), the chat page's composer is drawn a frame late; goes as the chat page's shell is made as nodes",
    ),
  ),
  (
    "wide-places",
    (
      "src/sfreplay/flows/wide_places_test.mbt:12:5-12:17@stillfail: not so at 1132.15087890625 ms, the run's moment for it (its timeline 11.18603515625 ms later from its first step): so at 1149.0439453125 ms, 16.89306640625 ms later",
      "untraced (probed frame by frame): nothing moving at that moment; what it waits for is the core's next message, which the replay gives later than the run's moment (1132.9 ms): the replay's moment of giving, it seems, not the app's",
    ),
  ),
])

///|
/// What a flow's own judgement says where the app does as a device does and the cause is traced to its line, by
/// trace: each as it says it, its moment with it, and why, so that a pass that comes to it notes it and goes on to the
/// flow's next step, its checks after it judged as ever (the coordinator of the migration, 2026-11-12). Only what is
/// traced to its line comes in, and only falls: said otherwise (later, or other words) it fails as ever, and one no
/// longer said fails, to be taken out. Another flow said so for the same cause may come in by the same entry; any other
/// cause is the coordinator's to say.
// kept across runs: a value
let judged_traced_known : Map[String, Array[(String, String)]] = Map([
  (
    "answer-option",
    [
      (
        "something under the post moves: 2733.3333333333335 (at 2716.6666666666665 ms)",
        // gone =先不换 at 2428.49; the chat's delta (in id 19: the agent's turn failed) given at ~2421.6, between the
        // frames at 2416.67 and 2433.33; the old view's list sets its rows' way out from the frame that builds it
        // (mbui/src/ui/list_size.mbt:632: `now`, the frame's moment, a row's cause where `from` says none), 2433.33 +
        // row_size_ms 300, and the room under the post goes on it (src/sfbase/under_post.mbt:86, on_row_way): its
        // options' close, at rest at 2716.67 as the step came, ends a frame later. A device's so; main's replay gave
        // every message at a frame, the way setting out at its moment. Goes as the chat's list is made as nodes.
        "traced: the old list's rows' way from the frame after the message (mbui/src/ui/list_size.mbt:632, src/sfbase/under_post.mbt:86); goes as the chat's list is made as nodes",
      ),
    ],
  ),
  (
    "share",
    [
      (
        "no motion to run to (its end: -1); said since the last step that acted: the bar's springs, told at src/sfapp/bar.mbt:170:12-170:102@stillfail (at rest at 1098.887939453125 ms) (at 1434.887939453125 ms)",
        // what another app shares is taken by the old view as it builds a frame (src/sfapp/share.mbt:195,
        // share_in_frame: @ui.shared_in read there), its sheet raised by a frame after that, not as the host says it:
        // given at its step, nothing of it moves yet. Goes as the host tells it between frames (MB_OUTSIDE_SHARE).
        "traced: what is shared taken in a frame (src/sfapp/share.mbt:195, share_in_frame); goes with MB_OUTSIDE_SHARE",
      ),
    ],
  ),
])

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
  "bar-going-down": [7, 120],
  "card-motion": [7],
  "close-option": [7],
  "delete-failed": [7],
  "draft": [7],
  // glass at 120 (#5519): the chat page's reads go out between frames at 1165.3 ms, as a message of the core is
  // taken as it comes and what read it is made again, chatJobs first; the strict pass sends them as its frame at
  // 1150 is built, stations, picture, then chatJobs; gone with what a page reads said as it is made
  "glass": [7, 120],
  "history": [7],
  "markdown": [7],
  "offline-retry": [7],
  "open-link": [7],
  "pick-words": [7],
  "quote": [7],
  "send-card-paced": [7],
  "send-flying": [7],
  "send-paced": [7],
  "send-text": [7],
  "service-page": [7, 120],
  "station-file-sent": [7],
  // 6: sub {"topic":"workspace","workspace":…} | strict sub {"topic":"doing"}
  "drive-delete": [7],
  "drive-lend": [7],
  "drive-play": [7, 120],
  "drive-rename": [7],
  "drive-zip": [7],
  "reader": [7],
  // 6: unsub {"topic":"status"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "chinese-enter": [7],
  "dismiss": [7],
  "paste-long": [7],
  "paste-short": [7],
  "pin": [7],
  "station-files": [7],
  // 6: sub {"query":…,"scope":…,"topic":"search"} | strict call cache.usage {}
  "settings-profile": [7],
  "settings-sheet-sinking": [7],
  "settings-station-mark": [7],
  "settings-station-settings": [7],
  "settings-workspace-people": [7],
  "station-rename": [7],
  "settings-decisions": [7],
  // 4: - | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "bar-archive": [7, 120],
  "notice-looking": [7],
  // wide-answer-reply at 120 (#5519): the new chat page sends its composer, machineSessions.list and status's
  // release in the frame at 1050 ms, notify.permission (sent once notify's values are in, which came after that
  // frame) in the next, at 1058.3; the strict pass sends all four in its frame at 1083.3, notify.permission before
  // machineSessions.list; gone with what a page reads said as it is made
  "wide-answer-reply": [7],
  "wide-send": [7],
  // 3: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict sub
  // {"topic":"chat","compact":true,"session":…,"station":…}
  "chat-audio": [7],
  "video-frames": [7],
  "viewer": [7],
  // 3: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict call cache.usage {}
  "settings-connect": [7],
  "settings-device-pages": [7],
  "settings-vault-item": [7],
  // 3: sub {"query":…,"scope":…,"topic":"shareIn","source":…} | strict sub {"topic":"notify"}
  "share": [7],
  "share-files": [7],
  "share-new-chat": [7],
  // 2: unsub {"topic":"status"} | strict sub {"topic":"workspace","workspace":…}
  "bar-glass": [7],
  "places": [7],
  // 1: sub {"scope":…,"topic":"newChat"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "draft-restart": [7],
  // 1: sub {"topic":"filesTabs","workspace":…} | strict sub {"topic":"doing"}
  "drive-download-many": [7, 120],
  // 1: - | strict call lock.pair {"workspace":…}
  "lock-wait": [7],
  // 1: sub {"scope":…,"topic":"stations"} | strict sub {"key":…,"topic":"composer"}
  "mark-read": [7, 120],
  // 1: sub {"scope":…,"topic":"stations"} | strict sub {"scope":…,"topic":"newChat"}
  "new-chat": [7],
  // 1: sub {"topic":"chat","compact":true,"session":…,"station":…} | strict call notify.permission
  "notice-cancel": [7],
  // 1: - | strict call link.parse {"url":…}
  "notice-failed": [7],
  // 1: - | strict sub {"topic":"stationNet","station":…}
  "settings-add-station": [7],
  // 1: unsub {"topic":"doing"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  // settings-run-settings at 120 (#5519): the chat page's chatJobs and picture go out between frames at 1147.3
  // ms, as a message of the core is taken as it comes, chatJobs first; the strict pass sends them as its frame at
  // 1133.3 is built, picture first; gone with what a page reads said as it is made
  "settings-run-settings": [7, 120],
  // 1: call picture {"url":…} | strict unsub {"topic":"driveTransfers","workspace":…}
  "sheets-sinking": [7],
  // 1: - | strict call composer.starting {"key":…,"starting":true}
  "wide-new-chat": [7, 120],
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
  // 1: - | strict call cache.usage {}
  "workspace-members": [7],
}

///|
/// The flows whose strict pass asks what their run did not, known, by trace: each ask exactly, in its order, at its
/// moment on the app's clock; any other is the flow's failure as ever, and one that asks it no more fails till it is
/// taken out. Only falls (the coordinator of the migration, 2026-11-11: no ask allowed by its kind, no trace recorded
/// again over one).
// kept across runs: a value
let strict_diverged_known : Map[String, Array[(Double, String)]] = {
  // lock-wait (#5519; anew with what the first screen reads declared, #5589): at 22133.3 the lock's delta (safe
  // mode off) takes the waiting page away and with it what it had taken over of what was declared as the workspace
  // came in view, doing and driveTransfers (taken over, then its reader gone, the next not come yet: a gap a
  // declaration does not mend); Home's frame at 22150 asks doing again. The run's device took it in the frame that
  // built the next page, behind a message before it, so nothing was let go. Gone with #5135 (what is read kept by its
  // topic while a page is covered), whose merge takes this out.
  "lock-wait": [
    (22133.333333333336, "{\"id\":12,\"unsubscribe\":true}"),
    (22133.333333333336, "{\"id\":13,\"unsubscribe\":true}"),
    (22150.000000000004, "{\"id\":24,\"subscribe\":{\"topic\":\"doing\"},\"keyed\":true}"),
  ],
}

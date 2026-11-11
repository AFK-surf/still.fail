///|
/// The flows whose pace pass (orders: the strict pass again with run_for's frames at 7 a second, and at 120) tells
/// the core otherwise than the strict pass, by trace, at which rates: each stops at its first split (PACE-SPLIT says
/// where, message by message). Only falls: a flow that splits and is not here fails, one here that splits no more
/// fails till it is taken out. A cause mended a layer down may show the next one further on, the flow still here.
/// Grouped by the first message apart (the pace pass's | the strict pass's); the cause said where it was traced, the
/// rest by what shows: what the app reads of the core it asks as a frame is built, so a sparser display's frames
/// ask it later than an input that came meanwhile (the coordinator of the migration, 2026-11-11: the next step,
/// what a page reads said as it is made).
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
  "glass": [7],
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
  // 9: sub {"topic":"workspace","workspace":…} | strict sub {"topic":"doing"}
  "drive-delete": [7],
  "drive-lend": [7],
  "drive-list": [7],
  "drive-play": [7, 120],
  "drive-read": [7],
  "drive-rename": [7],
  "drive-sheet-closing": [7],
  "drive-zip": [7],
  "reader": [7],
  // 6: unsub {"topic":"status"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "chinese-enter": [7],
  "dismiss": [7],
  "paste-long": [7],
  "paste-short": [7],
  "pin": [7],
  "station-files": [7, 120],
  // 6: sub {"query":…,"scope":…,"topic":"search"} | strict call cache.usage {}
  "settings-profile": [7],
  "settings-sheet-sinking": [7],
  "settings-station-mark": [7],
  "settings-station-settings": [7],
  "settings-workspace-people": [7],
  "station-rename": [7],
  // 4: unsub {"topic":"status"} | strict call cache.usage {}
  "appearance-kept": [7],
  "notify-off": [7],
  "settings-appearance": [7],
  "settings-decisions": [7],
  // 4: - | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "bar-archive": [7, 120],
  "notice-looking": [7],
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
  "share": [7, 120],
  "share-files": [7],
  "share-new-chat": [7],
  // 2: unsub {"topic":"status"} | strict sub {"topic":"workspace","workspace":…}
  "bar-glass": [7],
  "places": [7],
  // 1: sub {"scope":…,"topic":"newChat"} | strict sub {"topic":"chat","compact":true,"session":…,"station":…}
  "draft-restart": [7],
  // 1: sub {"topic":"filesTabs","workspace":…} | strict sub {"topic":"doing"}
  "drive-download-many": [7, 120],
  // 1: - | strict sub {"path":…,"root":…,"topic":"drive","station":…}
  "drive-upload": [7],
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
  "settings-run-settings": [7],
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
  // 1: sub {"query":…,"scope":…,"topic":"search"} | strict call notify.permission {"state":"unknown"}
  "wide-switcher": [7],
  // 1: - | strict call cache.usage {}
  "workspace-members": [7],
}

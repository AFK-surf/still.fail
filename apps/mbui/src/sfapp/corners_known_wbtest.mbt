// The corner rule (mbui's Tester::corner_faults, mbui's ui/corners.mbt) as each screen keeps it
// now: how many faults it still has, the bar they may only fall from (screen_check fails on one more, and on one less
// until the bar is lowered here). A screen not listed has none.

///|
let corners_known : Map[String, Int] = Map([])

///|
/// Every screen in every window (corners_wbtest.mbt), by window, language and screen: the bar it may only fall from. A
/// screen not listed has none. Listed: the rail on the tape (corners_tape_rail), and 安全's last card where its page
/// ends 5 short of its panel.
let corners_everywhere_known : Map[String, Int] = {
  let known = Map([])
  for win in ["touch", "desk-win"] {
    for lang in ["zh", "en"] {
      for mode in corners_tape_rail {
        known["\{win}-\{lang} \{mode}"] = 1
      }
    }
  }
  // 安全 with safe mode on, in the tablet's window, in Chinese: the rail's one and two more, the foot corners of its
  // last card (网页版's, 16 in from the panel's sides, 26 round). Without the row of a lock of one's own at its top
  // (gone, 2026-11-10) the page is 5 short of its panel, so it does not scroll and its last card stands 21 over the
  // panel's foot, where its end would stand 16 (page_foot). Where a page that does not fill its panel ends is its
  // words' and the window's, no place it is stood at: the rule holds what does not scroll to the corner, and nothing
  // here stands it elsewhere. Gone as the page's height is any other (English's has none).
  known["touch-zh lock-security"] = 3
  // A request for the phone waiting (chat-phone-lacks, swept since 2026-11-11; the same card as chat-phone's, on main
  // unswept): its length's chooser, the last of its answer's row, stands in the card's foot end corner off concentric
  // with it where its words are long (闲置 1 小时后失效 on a phone; Until idle for 1 hour wherever English is), as the
  // request cards' rows of answers are laid (ask_buttons). The rail's one besides it where the window has a tape.
  known["phone-zh chat-phone-lacks"] = 1
  known["touch-en chat-phone-lacks"] = 2
  known["desk-en chat-phone-lacks"] = 2
  known["desk-win-en chat-phone-lacks"] = 3
  known["tablet-en chat-phone-lacks"] = 1
  known["wide-en chat-phone-lacks"] = 2
  known["wide-win-en chat-phone-lacks"] = 2
  known
}

///|
/// The screens whose rail stands on the tape (its 600 wide windows, a tablet's and Windows'), one fault each: the
/// ground of its first place, 30 square and 15 round, in the corner of the sidebar's panel (42 round): 13 in from its
/// left, as the rail's places stand, and 27 under its top, that place's middle on the line of the sidebar's first row
/// beside it, 新建对话's (pengxiao, 2026-10-25). The tablet is kept so for now (the user, 2026-11-09, moving the Mac window's up into its
/// corner alone). On main the rail was an old view's island, measured against the island's own square box, so the rule
/// never saw it; as nodes of the window's tree it is measured against the panel. A panel over Home (home-sheet, switcher,
/// new-workspace and new-workspace-code, …) has it too: the rail behind it, not the panel.
let corners_tape_rail : Array[String] = [
  "webdemo", "home", "home-bars", "home-jobs", "home-sheet", "home-news", "new-workspace", "new-workspace-code", "rail-menu",
  "home-station-updates", "station-updates", "home-station-updates-app", "station-updates-app", "place", "switcher", "switcher-found", "keys-dialog", "search", "search-jobs", "search-results", "chat", "chat-agent",
  "chat-agent-unsaid", "chat-answering", "chat-attach", "chat-attach-row", "chat-cards", "chat-compose",
  "chat-download", "chat-failed", "chat-feedback", "chat-image-coming", "chat-file-links", "chat-find", "chat-flash", "chat-flash-mine", "chat-flash-notice",
  "chat-history-side", "chat-history-side-working", "chat-info", "chat-job", "chat-jobs", "chat-jobs-pop", "chat-jobs-side", "chat-letters",
  "chat-letters-info", "chat-letters-open", "chat-letters-pop", "chat-letters-side", "chat-things",
  "chat-things-side", "chat-info-pulls", "chat-link-menu", "chat-loading", "chat-login", "chat-long", "chat-md",
  "chat-model-pop", "chat-model-accounts", "chat-need", "chat-peek", "chat-pick", "chat-preview-apk",
  "chat-preview-audio", "chat-preview-code", "chat-preview-csv", "chat-preview-html", "chat-preview-image",
  "chat-preview-md", "chat-preview-none", "chat-preview-pdf", "chat-preview-step", "chat-preview-swipe",
  "chat-preview-video", "chat-publish", "chat-quote", "chat-screens", "chat-sending", "chat-service-side",
  "chat-station-file", "chat-station-files", "chat-station-ref", "chat-station-sheet", "chat-tabs-side",
  "chat-view-side", "chat-view-side-image", "chat-view-side-video", "chat-view-side-audio", "chat-update",
  "chat-vault-typed", "chat-viz", "chat-working", "chat-rig", "chat-outline-away", "chat-outline", "chat-outline-find",
  "archived", "history", "history-details", "drive",
  "drive-roots", "drive-download", "drive-empty", "drive-loading", "drive-sub", "drive-upload", "files",
  "files-add-folder", "files-clash", "files-columns", "files-list", "files-preview", "files-split",
  "files-transfers", "files-tree", "place-stations", "place-profiles", "reader", "reader-bars", "reader-contents",
  "reader-layout", "reader-md", "newchat", "newchat-files", "newchat-lend", "share-card", "share-card-dark",
  "newchat-model", "newchat-profiles", "newchat-reading", "newchat-station",
  // (a preset's dialog over 新对话 and its steps further in: the rail behind them, not the panel)
  "newchat-preset-new", "newchat-preset-new-add", "newchat-preset-new-browse", "newchat-preset-new-browse-repos",
  "newchat-preset-new-clone", "newchat-preset-new-clones",
  // (the presets' menu and its level further in: the rail behind them, not the menu)
  "newchat-preset", "newchat-preset-others", "newchat-preset-others-none", "newchat-preset-theirs",
    "newchat-preset-theirs-long", "player-audio", "player-ended",
  "player-failed", "player-opening", "player-video", "service", "service-restart", "service-sized",
  "service-stopped", "share-in", "share-in-files", "share-in-stations", "lock-security", "lock-upgrade", "screen-agent-driving",
  "screen-agent-paused", "screen-clipboard-driving", "screen-clipboard-old-station", "screen-connecting",
  "screen-denied", "screen-ended", "screen-failed", "screen-files-done", "screen-files-going", "screen-full",
  "screen-full-tools", "screen-gone", "screen-keys", "screen-live", "screen-login-fill", "screen-login-pick",
  "screen-not-drivable", "screen-outdated", "screen-pages", "screen-read-only", "screen-reconnecting", "screen-trackpad",
  "screen-trackpad-command", "screen-user-pages", "screen-user-tabs", "screen-windows", "screen-window", "settings-home", "settings-appearance", "settings-me", "settings-me-reading",
  "settings-workspace", "settings-security", "settings-vault", "settings-vault-items", "settings-vault-item",
  "settings-stations", "settings-station", "settings-station-offline", "settings-station-env",
  "settings-station-processes", "settings-station-mark", "settings-station-lower", "settings-station-versions",
  "settings-station-updated",
  "settings-station-network", "settings-station-copies", "settings-station-copies-alone", "settings-station-restore", "settings-station-restore-offer",
  "settings-station-restore-confirm", "settings-station-restore-confirm-long", "settings-station-restored", "settings-station-retire-panel", "settings-station-retire-panel-pick", "settings-station-retire-panel-none", "settings-station-retire-panel-joined", "settings-station-retire-panel-long", "settings-station-retire-sending", "settings-station-retire-sent", "settings-station-retire-sent-failed", "settings-station-retire-quiet", "settings-station-retire-failed", "settings-station-retire-accounts", "settings-station-retire-done", "settings-station-retire-done-left", "settings-station-taking", "settings-profile-move", "settings-profile-move-key", "settings-stations-add", "settings-stations-existing", "settings-stations-command",
  "settings-first-station", "settings-adb", "settings-adb-unpaired", "settings-adb-pairing",
  "settings-adb-connected", "settings-adb-failed", "settings-adb-chats", "settings-adb-chats-long", "settings-adb-lock-two",
  "settings-adb-idle", "settings-adb-desk", "chat-phone-lacks", "chat-phone-step-off", "chat-phone-step-developer",
  "chat-phone-step-wifi", "chat-phone-step-wireless", "chat-phone-step-refused", "chat-phone-step-code",
  "chat-phone-linked-unpaired", "chat-phone-linked-unauthorized", "chat-phone-linked-connected",
  "settings-profiles", "settings-profiles-monthly", "settings-profiles-fable", "settings-profiles-own3",
  "settings-profiles-week-fable", "settings-profiles-several", "settings-profile", "settings-profile-fable", "settings-profile-own3",
  "settings-profile-week-fable", "settings-profile-quota", "settings-profile-quota-kinds",
  "settings-profile-lower", "settings-profile-login", "settings-profile-login-failed",
  "settings-profile-quota-failed", "settings-profile-blocked", "settings-profile-signin", "settings-profile-key", "settings-profile-copy",
  "settings-new-profile", "settings-new-profile-stations", "settings-new-profile-key", "settings-connects", "settings-connect", "settings-connect-menu", "settings-connect-mode",
  "settings-connect-run", "settings-new-connect", "settings-new-connect-platform", "settings-new-connect-scan",
  "settings-new-connect-app", "settings-new-connect-comma", "settings-connect-comma", "settings-connect-feishu", "settings-slack-app", "settings-memory", "settings-memory-doc", "settings-usage",
  "settings-archive", "settings-kept", "settings-kept-many", "settings-vault-off", "settings-vault-plain",
  "settings-vault-waits", "settings-vault-words", "settings-vault-add", "settings-vault-editor", "settings-vault-recover",
  "settings-lock-prompt", "settings-add-people", "settings-workspace-mark", "settings-local-fonts",
  "settings-policy", "settings-policy-text", "settings-policy-option", "settings-security-join",
  "settings-security-off", "settings-security-pending", "settings-security-upgrade-station", "settings-security-upgrade-station-not", "settings-security-upgrade-member", "settings-security-upgrade-device", "settings-security-upgrade-many", "settings-security-upgrade-ask", "settings-security-upgrade-other", "settings-security-upgrade-updating", "settings-stations-tasks", "place-stations-tasks", "settings-station-tasks", "settings-station-tasks-other", "settings-station-tasks-locked", "settings-stations-devices", "place-stations-devices", "settings-station-devices", "settings-run", "settings-run-models", "settings-run-accounts", "settings-fonts",
  "settings-fonts-code", "settings-decisions", "settings-completion", "settings-bars", "settings-about",
  "settings-changelog", "settings-prices", "settings-notify-off", "settings-notify-denied", "share-card-poster",
  "share-card-receipt", "share-card-senren-adv", "share-card-senren-affection", "share-card-senren-cg",
  "share-card-senren-chat", "share-card-senren-chibi", "share-card-senren-ciallo", "share-card-senren-class",
  "share-card-senren-ema", "share-card-senren-gacha", "share-card-senren-gahou-koharu",
  "share-card-senren-gahou-lena", "share-card-senren-gahou-mako", "share-card-senren-gahou-murasame",
  "share-card-senren-gahou-roka", "share-card-senren-gahou-roka2", "share-card-senren-inumimi",
  "share-card-senren-kagura", "share-card-senren-ledger", "share-card-senren-map", "share-card-senren-menu",
  "share-card-senren-night", "share-card-senren-ninja", "share-card-senren-omikuji", "share-card-senren-parfait",
  "share-card-senren-party", "share-card-senren-photo", "share-card-senren-ryokan", "share-card-senren-staff",
  "share-card-senren-sword", "share-card-senren-title", "share-card-terminal",
]

///|
/// Words a box with its height said does not hold (mbui's Tester::fixed_outgrown) on every screen in every window
/// (corners_wbtest.mbt), by window, language and screen: the bar it may only fall from, counted as the rule first ran
/// (2026-11-11). A screen not listed has none; none is now (智能体's card's spend, an old view's, on its own line of 26
/// since, as its box was).
let corners_outgrown_known : Map[String, Int] = Map([])

///|
/// What is pressed side by side another height than the rest of its row (mbui's Tester::height_faults; the user,
/// 2026-10-30: what can be pressed is one height) on every screen in every window (corners_wbtest.mbt), by window,
/// language and screen: the bar it may only fall from, counted as the rule first ran (2026-11-14). A screen not listed
/// has none. Listed: 连接's 继续 (a connect's session waiting to go on) in the wide windows, its button 36 and the
/// icon's button beside it 32.
let corners_heights_known : Map[String, Int] = Map([
  ("wide-zh settings-connects", 1),
  ("wide-win-zh settings-connects", 1),
  ("wide-en settings-connects", 1),
  ("wide-win-en settings-connects", 1),
])

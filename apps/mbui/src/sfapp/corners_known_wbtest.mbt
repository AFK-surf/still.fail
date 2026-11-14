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
  // settings-profile-move in the tablet's 600×900 window, and place-profiles / settings-profile-key (备用 key, without
  // an empty 额度 card) in the 600×760 desktop windows: with Station rows merged into 设置, the page is just short of its
  // panel, so it does not scroll and its last card (设置's, 16 in from the panel's sides, 26 round) stands over the
  // panel's 42-round foot.
  known["touch-zh settings-profile-move"] = 3
  known["touch-en settings-profile-move"] = 3
  known["desk-zh place-profiles"] = 1
  known["desk-en place-profiles"] = 1
  known["desk-zh settings-profile-key"] = 1
  known["desk-en settings-profile-key"] = 1
  known["desk-win-zh place-profiles"] = 3
  known["desk-win-en place-profiles"] = 3
  known["desk-win-zh settings-profile-key"] = 3
  known["desk-win-en settings-profile-key"] = 3
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
  // (a station's terminals among its screens, a terminal's page over the frame: the rail on the tape under them)
  "settings-station-terminals", "terminal", "terminal-taken",
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
/// icon's button beside it 32. And what old views hosted in the window's tree show, not measured till the spacing rules
/// took the tree's nodes in each after its parent (2026-11-14): 屏幕's pages, their address field 36 beside 后退's 40
/// (and in the wide windows a tab's × 40 beside its tabs' 36); a chat's 任务 beside it in the wide windows.
let corners_heights_known : Map[String, Int] = Map([
  ("phone-zh screen-pages", 1),
  ("phone-en screen-pages", 1),
  ("phone-zh screen-user-pages", 1),
  ("phone-en screen-user-pages", 1),
  ("phone-zh screen-user-tabs", 1),
  ("phone-en screen-user-tabs", 1),
  ("desk-en screen-pages", 1),
  ("desk-en screen-user-pages", 1),
  ("desk-en screen-user-tabs", 1),
  ("desk-win-en screen-pages", 1),
  ("desk-win-en screen-user-pages", 1),
  ("desk-win-en screen-user-tabs", 1),
  ("desk-win-zh screen-pages", 1),
  ("desk-win-zh screen-user-pages", 1),
  ("desk-win-zh screen-user-tabs", 1),
  ("desk-zh screen-pages", 1),
  ("desk-zh screen-user-pages", 1),
  ("desk-zh screen-user-tabs", 1),
  ("tablet-en screen-pages", 1),
  ("tablet-en screen-user-pages", 1),
  ("tablet-en screen-user-tabs", 1),
  ("tablet-zh screen-pages", 1),
  ("tablet-zh screen-user-pages", 1),
  ("tablet-zh screen-user-tabs", 1),
  ("touch-en screen-pages", 1),
  ("touch-en screen-user-pages", 1),
  ("touch-en screen-user-tabs", 1),
  ("touch-zh screen-pages", 1),
  ("touch-zh screen-user-pages", 1),
  ("touch-zh screen-user-tabs", 1),
  ("wide-en chat-jobs-side", 1),
  ("wide-en screen-pages", 1),
  ("wide-en screen-user-pages", 2),
  ("wide-en screen-user-tabs", 2),
  ("wide-win-en chat-jobs-side", 1),
  ("wide-win-en screen-pages", 1),
  ("wide-win-en screen-user-pages", 2),
  ("wide-win-en screen-user-tabs", 2),
  ("wide-win-zh chat-jobs-side", 1),
  ("wide-win-zh screen-pages", 1),
  ("wide-win-zh screen-user-pages", 2),
  ("wide-win-zh screen-user-tabs", 2),
  ("wide-zh chat-jobs-side", 1),
  ("wide-zh screen-pages", 1),
  ("wide-zh screen-user-pages", 2),
  ("wide-zh screen-user-tabs", 2),
  ("wide-zh settings-connects", 1),
  ("wide-win-zh settings-connects", 1),
  ("wide-en settings-connects", 1),
  ("wide-win-en settings-connects", 1),
])

///|
/// A mark beside a block of several lines off its first line (mbui's Tester::first_line_faults; the user, 2026-11-14:
/// beside several lines an icon, a mark or a chevron sits on the first, never centred on them) on every screen in every
/// window (corners_wbtest.mbt), by window, language and screen: the bar it may only fall from, counted as the rule
/// first ran (2026-11-15). A screen not listed has none. Listed: rows whose icon is centred on a name over a line under
/// it: 连接's connects (and a new one's choices), a station's commands, a preset's folders (its icon and chevron), a
/// file's card in a chat (published files), a found message in the outline, 决策's chevron, a run's model in its
/// history's details (its icon and chevron). And what old views hosted in the window's tree show, measured once the
/// rules took the tree's nodes in each after its parent (#6294, 2026-11-15): a chat's files and references, its
/// agent's card, 文件's rows, a station's settings, 搜索's results, a login's fill.
let corners_first_line_known : Map[String, Int] = Map([
  ("phone-en search-jobs", 3),
  ("phone-zh search-jobs", 3),
  ("phone-en history-details", 2),
  ("phone-zh history-details", 2),
  ("desk-en newchat-preset-new-browse", 2),
  ("desk-en settings-stations-command", 1),
  ("desk-win-en newchat-preset-new-browse", 2),
  ("desk-win-en settings-stations-command", 1),
  ("desk-win-zh newchat-preset-new-browse", 2),
  ("desk-zh newchat-preset-new-browse", 2),
  ("phone-en settings-connects", 2),
  ("phone-en settings-decisions", 1),
  ("phone-en settings-new-connect", 2),
  ("phone-en settings-new-connect-app", 2),
  ("phone-en settings-new-connect-comma", 2),
  ("phone-en settings-new-connect-platform", 2),
  ("phone-en settings-new-connect-scan", 2),
  ("phone-zh settings-connects", 2),
  ("phone-zh settings-new-connect", 2),
  ("phone-zh settings-new-connect-app", 2),
  ("phone-zh settings-new-connect-comma", 2),
  ("phone-zh settings-new-connect-platform", 2),
  ("phone-zh settings-new-connect-scan", 2),
  ("tablet-en chat-outline-find", 1),
  ("tablet-en chat-publish", 2),
  ("tablet-en newchat-preset-new-browse", 2),
  ("tablet-en settings-connects", 2),
  ("tablet-en settings-new-connect", 2),
  ("tablet-en settings-new-connect-app", 2),
  ("tablet-en settings-new-connect-comma", 2),
  ("tablet-en settings-new-connect-platform", 2),
  ("tablet-en settings-new-connect-scan", 2),
  ("tablet-en settings-stations-command", 3),
  ("tablet-zh chat-outline-find", 1),
  ("tablet-zh chat-publish", 2),
  ("tablet-zh newchat-preset-new-browse", 2),
  ("tablet-zh settings-connects", 2),
  ("tablet-zh settings-new-connect", 2),
  ("tablet-zh settings-new-connect-app", 2),
  ("tablet-zh settings-new-connect-comma", 2),
  ("tablet-zh settings-new-connect-platform", 2),
  ("tablet-zh settings-new-connect-scan", 2),
  ("touch-en chat-outline-find", 1),
  ("touch-en chat-publish", 2),
  ("touch-en newchat-preset-new-browse", 2),
  ("touch-en settings-stations-command", 1),
  ("touch-zh chat-outline-find", 1),
  ("touch-zh chat-publish", 2),
  ("touch-zh newchat-preset-new-browse", 2),
  ("wide-en chat-publish", 2),
  ("wide-en newchat-preset-new-browse", 2),
  ("wide-en settings-connects", 2),
  ("wide-en settings-new-connect", 2),
  ("wide-en settings-new-connect-app", 2),
  ("wide-en settings-new-connect-comma", 2),
  ("wide-en settings-new-connect-platform", 2),
  ("wide-en settings-new-connect-scan", 2),
  ("wide-en settings-stations-command", 3),
  ("wide-win-en chat-publish", 2),
  ("wide-win-en newchat-preset-new-browse", 2),
  ("wide-win-en settings-connects", 2),
  ("wide-win-en settings-new-connect", 2),
  ("wide-win-en settings-new-connect-app", 2),
  ("wide-win-en settings-new-connect-comma", 2),
  ("wide-win-en settings-new-connect-platform", 2),
  ("wide-win-en settings-new-connect-scan", 2),
  ("wide-win-en settings-stations-command", 3),
  ("wide-win-zh chat-publish", 2),
  ("wide-win-zh newchat-preset-new-browse", 2),
  ("wide-win-zh settings-connects", 2),
  ("wide-win-zh settings-new-connect", 2),
  ("wide-win-zh settings-new-connect-app", 2),
  ("wide-win-zh settings-new-connect-comma", 2),
  ("wide-win-zh settings-new-connect-platform", 2),
  ("wide-win-zh settings-new-connect-scan", 2),
  ("wide-zh chat-publish", 2),
  ("wide-zh newchat-preset-new-browse", 2),
  ("wide-zh settings-connects", 2),
  ("wide-zh settings-new-connect", 2),
  ("wide-zh settings-new-connect-app", 2),
  ("wide-zh settings-new-connect-comma", 2),
  ("wide-zh settings-new-connect-platform", 2),
  ("wide-zh settings-new-connect-scan", 2),
  ("desk-en chat-agent-unsaid", 1),
  ("desk-en chat-agent", 1),
  ("desk-en screen-login-fill", 1),
  ("desk-win-en chat-agent-unsaid", 1),
  ("desk-win-en chat-agent", 1),
  ("desk-win-en screen-login-fill", 1),
  ("desk-win-zh chat-agent-unsaid", 1),
  ("desk-win-zh chat-agent", 1),
  ("desk-win-zh screen-login-fill", 1),
  ("desk-zh chat-agent-unsaid", 1),
  ("desk-zh chat-agent", 1),
  ("desk-zh screen-login-fill", 1),
  ("phone-en chat-attach-row", 3),
  ("phone-en chat-attach", 2),
  ("phone-en chat-download", 1),
  ("phone-en chat-station-file", 2),
  ("phone-en chat-station-ref", 1),
  ("phone-en chat-station-sheet", 2),
  ("phone-en drive-download", 9),
  ("phone-en drive-loading", 10),
  ("phone-en drive-sub", 4),
  ("phone-en drive-upload", 9),
  ("phone-en drive", 10),
  ("phone-en files-add-folder", 10),
  ("phone-en files-clash", 10),
  ("phone-en files-columns", 4),
  ("phone-en files-list", 10),
  ("phone-en files-preview", 10),
  ("phone-en files-split", 10),
  ("phone-en files-transfers", 10),
  ("phone-en files-tree", 14),
  ("phone-en place-stations-devices", 4),
  ("phone-en place-stations-tasks", 4),
  ("phone-en place-stations", 2),
  ("phone-en screen-login-fill", 1),
  ("phone-en search-results", 7),
  ("phone-en service-restart", 1),
  ("phone-en settings-stations-add", 2),
  ("phone-en settings-stations-command", 2),
  ("phone-en settings-stations-devices", 5),
  ("phone-en settings-stations-existing", 2),
  ("phone-en settings-stations-tasks", 4),
  ("phone-en settings-stations", 2),
  ("phone-zh chat-attach-row", 3),
  ("phone-zh chat-attach", 2),
  ("phone-zh chat-download", 1),
  ("phone-zh chat-station-file", 2),
  ("phone-zh chat-station-ref", 1),
  ("phone-zh chat-station-sheet", 2),
  ("phone-zh drive-download", 9),
  ("phone-zh drive-loading", 10),
  ("phone-zh drive-sub", 4),
  ("phone-zh drive-upload", 9),
  ("phone-zh drive", 10),
  ("phone-zh files-add-folder", 10),
  ("phone-zh files-clash", 10),
  ("phone-zh files-columns", 4),
  ("phone-zh files-list", 10),
  ("phone-zh files-preview", 10),
  ("phone-zh files-split", 10),
  ("phone-zh files-transfers", 10),
  ("phone-zh files-tree", 14),
  ("phone-zh place-stations-devices", 4),
  ("phone-zh place-stations-tasks", 4),
  ("phone-zh place-stations", 2),
  ("phone-zh screen-login-fill", 1),
  ("phone-zh search-results", 7),
  ("phone-zh service-restart", 1),
  ("phone-zh settings-stations-add", 2),
  ("phone-zh settings-stations-command", 2),
  ("phone-zh settings-stations-devices", 5),
  ("phone-zh settings-stations-existing", 2),
  ("phone-zh settings-stations-tasks", 4),
  ("phone-zh settings-stations", 2),
  ("tablet-en chat-agent-unsaid", 1),
  ("tablet-en chat-agent", 1),
  ("tablet-en chat-attach-row", 3),
  ("tablet-en chat-attach", 2),
  ("tablet-en chat-download", 1),
  ("tablet-en chat-screens", 3),
  ("tablet-en chat-station-file", 2),
  ("tablet-en chat-station-ref", 1),
  ("tablet-en chat-station-sheet", 2),
  ("tablet-en screen-login-fill", 1),
  ("tablet-en settings-fonts-code", 1),
  ("tablet-en settings-fonts", 1),
  ("tablet-en settings-local-fonts", 1),
  ("tablet-en settings-stations-add", 2),
  ("tablet-en settings-stations-devices", 5),
  ("tablet-en settings-stations-existing", 2),
  ("tablet-en settings-stations-tasks", 4),
  ("tablet-en settings-stations", 2),
  ("tablet-en share-card-senren-menu", 10),
  ("tablet-zh chat-agent-unsaid", 1),
  ("tablet-zh chat-agent", 1),
  ("tablet-zh chat-attach-row", 3),
  ("tablet-zh chat-attach", 2),
  ("tablet-zh chat-download", 1),
  ("tablet-zh chat-screens", 3),
  ("tablet-zh chat-station-file", 2),
  ("tablet-zh chat-station-ref", 1),
  ("tablet-zh chat-station-sheet", 2),
  ("tablet-zh screen-login-fill", 1),
  ("tablet-zh settings-fonts-code", 1),
  ("tablet-zh settings-fonts", 1),
  ("tablet-zh settings-local-fonts", 1),
  ("tablet-zh settings-stations-add", 2),
  ("tablet-zh settings-stations-command", 2),
  ("tablet-zh settings-stations-devices", 5),
  ("tablet-zh settings-stations-existing", 2),
  ("tablet-zh settings-stations-tasks", 4),
  ("tablet-zh settings-stations", 2),
  ("tablet-zh share-card-senren-menu", 10),
  ("touch-en chat-agent-unsaid", 1),
  ("touch-en chat-agent", 1),
  ("touch-en screen-login-fill", 1),
  ("touch-en share-card-senren-menu", 10),
  ("touch-zh chat-agent-unsaid", 1),
  ("touch-zh chat-agent", 1),
  ("touch-zh screen-login-fill", 1),
  ("touch-zh share-card-senren-menu", 10),
  ("wide-en chat-agent-unsaid", 1),
  ("wide-en chat-agent", 1),
  ("wide-en chat-attach-row", 3),
  ("wide-en chat-attach", 2),
  ("wide-en chat-download", 1),
  ("wide-en chat-station-file", 2),
  ("wide-en chat-station-ref", 1),
  ("wide-en chat-station-sheet", 2),
  ("wide-en screen-login-fill", 1),
  ("wide-en settings-stations-add", 2),
  ("wide-en settings-stations-devices", 5),
  ("wide-en settings-stations-existing", 2),
  ("wide-en settings-stations-tasks", 4),
  ("wide-en settings-stations", 2),
  ("wide-win-en chat-agent-unsaid", 1),
  ("wide-win-en chat-agent", 1),
  ("wide-win-en chat-attach-row", 3),
  ("wide-win-en chat-attach", 2),
  ("wide-win-en chat-download", 1),
  ("wide-win-en chat-station-file", 2),
  ("wide-win-en chat-station-ref", 1),
  ("wide-win-en chat-station-sheet", 2),
  ("wide-win-en screen-login-fill", 1),
  ("wide-win-en settings-stations-add", 2),
  ("wide-win-en settings-stations-devices", 5),
  ("wide-win-en settings-stations-existing", 2),
  ("wide-win-en settings-stations-tasks", 4),
  ("wide-win-en settings-stations", 2),
  ("wide-win-zh chat-agent-unsaid", 1),
  ("wide-win-zh chat-agent", 1),
  ("wide-win-zh chat-attach-row", 3),
  ("wide-win-zh chat-attach", 2),
  ("wide-win-zh chat-download", 1),
  ("wide-win-zh chat-station-file", 2),
  ("wide-win-zh chat-station-ref", 1),
  ("wide-win-zh chat-station-sheet", 2),
  ("wide-win-zh screen-login-fill", 1),
  ("wide-win-zh settings-stations-add", 2),
  ("wide-win-zh settings-stations-command", 2),
  ("wide-win-zh settings-stations-devices", 5),
  ("wide-win-zh settings-stations-existing", 2),
  ("wide-win-zh settings-stations-tasks", 4),
  ("wide-win-zh settings-stations", 2),
  ("wide-zh chat-agent-unsaid", 1),
  ("wide-zh chat-agent", 1),
  ("wide-zh chat-attach-row", 3),
  ("wide-zh chat-attach", 2),
  ("wide-zh chat-download", 1),
  ("wide-zh chat-station-file", 2),
  ("wide-zh chat-station-ref", 1),
  ("wide-zh chat-station-sheet", 2),
  ("wide-zh screen-login-fill", 1),
  ("wide-zh settings-stations-add", 2),
  ("wide-zh settings-stations-command", 2),
  ("wide-zh settings-stations-devices", 5),
  ("wide-zh settings-stations-existing", 2),
  ("wide-zh settings-stations-tasks", 4),
  ("wide-zh settings-stations", 2),
])

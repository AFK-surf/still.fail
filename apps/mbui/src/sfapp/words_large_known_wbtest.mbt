// What each screen still shows with its words at words_large_scale (words_large_wbtest.mbt), by window, language and
// screen: squeezed, or words over words at rest. The bar it may only fall from; a screen not listed has none. Counted
// as the sweep first ran (2026-11-10): 87 screens (each language counted) with 229, and the share card's looks
// (share-card-senren-*) with 770, most of those words laid over words by the look's design, as at the default size.
// The window tree's nodes held to the squeeze as an old view's are (squeeze_tree.mbt, 2026-11-11) added what each line
// beside it says (`was`: its bar before), each to be mended and its bar brought down: 定高不随字号 a box of a fixed height
// its words' line outgrows at this size; 真问题 squeezed as it shows.

///|
let words_large_known : Map[String, Int] = {
  let known = Map::new()
  for k in [
    ("phone-zh webdemo", 5),  // was 0, +5 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh home", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh home-bars", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh home-jobs", 7),  // was 0, +7 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh home-sheet", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh home-news", 7),  // was 0, +7 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh new-workspace", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh new-workspace-code", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh rail-menu", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh switcher", 14),  // was 6, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh switcher-found", 12),  // was 4, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh keys-dialog", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh search", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh search-jobs", 3),
    ("phone-zh search-results", 7),
    ("phone-zh chat-agent", 3),
    ("phone-zh chat-preview-csv", 6),
    ("phone-zh chat-screens", 4),
    ("phone-zh history-details", 3),  // was 0, +3 (f) sfapp/history.mbt:268 定高不随字号，待修
    ("phone-zh place-stations", 1),
    ("phone-zh share-card", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-dark", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh newchat-station", 2),
    ("phone-zh share-in", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-in-files", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-in-stations", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh screen-agent-driving", 1),
    ("phone-zh screen-agent-paused", 1),
    ("phone-zh screen-clipboard-driving", 3),
    ("phone-zh screen-clipboard-old-station", 1),
    ("phone-zh screen-files-done", 3),
    ("phone-zh screen-files-going", 3),
    ("phone-zh screen-live", 1),
    ("phone-zh screen-login-fill", 3),
    ("phone-zh screen-login-pick", 3),
    ("phone-zh screen-not-drivable", 1),
    ("phone-zh screen-read-only", 1),
    ("phone-zh screen-trackpad", 1),
    ("phone-zh screen-trackpad-command", 1),
    ("phone-zh settings-workspace", 1),  // was 0, +1 (g) page_node.mbt:935 / workspace_page.mbt:397 真问题，待修
    ("phone-zh settings-stations", 1),
    ("phone-zh settings-stations-add", 1),
    ("phone-zh settings-stations-existing", 1),
    ("phone-zh settings-stations-command", 1),
    ("phone-zh settings-adb-connected", 2),
    ("phone-zh settings-profile-login-failed", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh settings-new-connect-platform", 1),
    ("phone-zh settings-kept", 1),
    ("phone-zh settings-kept-many", 1),
    ("phone-zh settings-vault-words", 14),
    ("phone-zh settings-add-people", 1),  // was 0, +1 (g) page_node.mbt:935 / workspace_page.mbt:397 真问题，待修
    ("phone-zh settings-workspace-mark", 1),  // was 0, +1 (g) page_node.mbt:935 / workspace_page.mbt:397 真问题，待修
    ("phone-zh settings-stations-tasks", 1),
    ("phone-zh place-stations-tasks", 1),
    ("phone-zh settings-stations-devices", 1),
    ("phone-zh place-stations-devices", 1),
    ("phone-zh settings-run", 1),
    ("phone-zh share-card-poster", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-receipt", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-terminal", 14),  // was 6, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-adv", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-ryokan", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-ledger", 15),  // was 7, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-ciallo", 42),  // was 34, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-parfait", 97),  // was 89, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gacha", 12),  // was 4, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-chibi", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-title", 168),  // was 160, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-cg", 16),  // was 8, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-affection", 48),  // was 40, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-chat", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-staff", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-ema", 14),  // was 6, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gahou-murasame", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gahou-mako", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gahou-lena", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gahou-roka", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gahou-koharu", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-gahou-roka2", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-party", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-omikuji", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-ninja", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-menu", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-inumimi", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-sword", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-kagura", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-map", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-photo", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-class", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-zh share-card-senren-night", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en webdemo", 5),  // was 0, +5 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en home", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en home-bars", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en home-jobs", 7),  // was 0, +7 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en home-sheet", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en home-news", 7),  // was 0, +7 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en new-workspace", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en new-workspace-code", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en rail-menu", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en switcher", 14),  // was 6, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en switcher-found", 12),  // was 4, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en keys-dialog", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en search", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en search-jobs", 3),
    ("phone-en search-results", 7),
    ("phone-en chat-agent", 5),
    ("phone-en chat-info", 2),
    ("phone-en chat-letters-info", 4),
    ("phone-en chat-info-pulls", 2),
    ("phone-en chat-preview-csv", 7),
    ("phone-en chat-preview-html", 1),
    ("phone-en chat-publish", 1),
    ("phone-en chat-screens", 4),
    // (its switch's title 「Send as file in this chat」 on two lines beside the switch, 40,642 224×50: the old panel's, told
    // of its nodes again as the tree's squeeze came to say what shares their row; it was 1 before its panel became nodes)
    ("phone-en chat-station-sheet", 1),
    ("phone-en history-details", 4),  // was 1, +3 (f) sfapp/history.mbt:268 定高不随字号，待修
    ("phone-en drive-upload", 1),
    ("phone-en place-stations", 1),
    ("phone-en share-card", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-dark", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en newchat-station", 2),
    ("phone-en share-in", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-in-files", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-in-stations", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en screen-agent-driving", 1),
    ("phone-en screen-agent-paused", 1),
    ("phone-en screen-clipboard-driving", 3),
    ("phone-en screen-clipboard-old-station", 1),
    ("phone-en screen-files-done", 5),
    ("phone-en screen-files-going", 3),
    ("phone-en screen-live", 1),
    ("phone-en screen-login-fill", 3),
    ("phone-en screen-login-pick", 3),
    ("phone-en screen-not-drivable", 1),
    ("phone-en screen-read-only", 1),
    ("phone-en screen-trackpad", 1),
    ("phone-en screen-trackpad-command", 1),
    ("phone-en settings-stations", 1),
    ("phone-en settings-stations-add", 1),
    ("phone-en settings-stations-existing", 1),
    ("phone-en settings-stations-command", 1),
    ("phone-en settings-adb-connected", 1),
    ("phone-en settings-adb-failed", 1),
    ("phone-en settings-profile-login-failed", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en settings-profile-signin", 1),  // was 0, +1 (e) accounts.mbt:601 真问题，待修
    ("phone-en settings-new-connect-app", 1),
    ("phone-en settings-memory-doc", 1),  // was 0, +1 (g) page_node.mbt:1267 真问题，待修
    ("phone-en settings-kept", 1),
    ("phone-en settings-kept-many", 1),
    ("phone-en settings-vault-words", 14),
    ("phone-en settings-vault-add", 1),
    ("phone-en settings-stations-tasks", 1),
    ("phone-en place-stations-tasks", 1),
    ("phone-en settings-stations-devices", 1),
    ("phone-en place-stations-devices", 1),
    ("phone-en settings-run", 1),
    ("phone-en settings-about", 1),  // was 0, +1 (g) page_node.mbt:1267 真问题，待修
    ("phone-en settings-notify-denied", 1),  // was 0, +1 (g) notify_node.mbt:671 真问题，待修
    ("phone-en share-card-poster", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-receipt", 11),  // was 3, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-terminal", 14),  // was 6, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-adv", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-ryokan", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-menu", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-ledger", 17),  // was 9, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-ciallo", 27),  // was 19, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-parfait", 99),  // was 91, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gacha", 13),  // was 5, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-chibi", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-title", 180),  // was 172, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-cg", 21),  // was 13, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-affection", 50),  // was 42, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-chat", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-staff", 10),  // was 2, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-sword", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-kagura", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-ema", 18),  // was 10, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gahou-murasame", 12),  // was 4, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gahou-mako", 13),  // was 5, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gahou-lena", 12),  // was 4, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gahou-roka", 13),  // was 5, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gahou-koharu", 14),  // was 6, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-gahou-roka2", 13),  // was 5, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-photo", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-party", 9),  // was 1, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-omikuji", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-ninja", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-inumimi", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-map", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-class", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
    ("phone-en share-card-senren-night", 8),  // was 0, +8 (f) list_row_node.mbt:55 定高不随字号，待修
  ] {
    known[k.0] = k.1
  }
  known
}

// What each screen still shows with its words at words_large_scale (words_large_wbtest.mbt), by window, language and
// screen: squeezed, or words over words at rest. The bar it may only fall from; a screen not listed has none. Counted
// as the sweep first ran (2026-11-10): 87 screens (each language counted) with 229, and the share card's looks
// (share-card-senren-*) with 770, most of those words laid over words by the look's design, as at the default size.
// The window tree's nodes held to the squeeze as an old view's are (squeeze_tree.mbt, 2026-11-11) added what each line
// beside it says (`was`: its bar before), each to be mended and its bar brought down: 定高不随字号 a box of a fixed height
// its words' line outgrows at this size; 真问题 squeezed as it shows.

///|
let words_large_known : Map[String, Int] = {
  let known = Map([])
  for k in [
    ("phone-zh switcher", 6),
    ("phone-zh switcher-found", 4),
    ("phone-zh search-jobs", 3),
    ("phone-zh search-results", 7),
    ("phone-zh chat-preview-csv", 6),
    ("phone-zh chat-screens", 4),
    ("phone-zh share-card", 3),
    ("phone-zh share-card-dark", 3),
    ("phone-zh settings-workspace", 1),  // was 0, +1 (g) page_node.mbt:935 / workspace_page.mbt:397 真问题，待修
    ("phone-zh settings-new-connect-platform", 1),
    ("phone-zh settings-kept", 1),
    ("phone-zh settings-kept-many", 1),
    ("phone-zh settings-vault-words", 14),
    ("phone-zh settings-add-people", 1),  // was 0, +1 (g) page_node.mbt:935 / workspace_page.mbt:397 真问题，待修
    ("phone-zh settings-workspace-mark", 1),  // was 0, +1 (g) page_node.mbt:935 / workspace_page.mbt:397 真问题，待修
    ("phone-zh settings-run", 1),
    ("phone-zh share-card-poster", 3),
    ("phone-zh share-card-receipt", 3),
    ("phone-zh share-card-terminal", 6),
    ("phone-zh share-card-senren-adv", 1),
    ("phone-zh share-card-senren-ryokan", 1),
    ("phone-zh share-card-senren-ledger", 7),
    ("phone-zh share-card-senren-ciallo", 34),
    ("phone-zh share-card-senren-parfait", 89),
    ("phone-zh share-card-senren-gacha", 4),
    ("phone-zh share-card-senren-chibi", 1),
    ("phone-zh share-card-senren-title", 160),
    ("phone-zh share-card-senren-cg", 8),
    ("phone-zh share-card-senren-affection", 40),
    ("phone-zh share-card-senren-chat", 1),
    ("phone-zh share-card-senren-staff", 2),
    ("phone-zh share-card-senren-ema", 6),
    ("phone-zh share-card-senren-gahou-murasame", 2),
    ("phone-zh share-card-senren-gahou-mako", 2),
    ("phone-zh share-card-senren-gahou-lena", 2),
    ("phone-zh share-card-senren-gahou-roka", 2),
    ("phone-zh share-card-senren-gahou-koharu", 2),
    ("phone-zh share-card-senren-gahou-roka2", 2),
    ("phone-zh share-card-senren-party", 1),
    ("phone-en switcher", 6),
    ("phone-en switcher-found", 4),
    ("phone-en search-jobs", 3),
    ("phone-en search-results", 7),
    ("phone-en chat-agent", 2),
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
    ("phone-en drive-upload", 1),
    ("phone-en share-card", 3),
    ("phone-en share-card-dark", 3),
    ("phone-en screen-files-done", 2),
    ("phone-en settings-profile-signin", 1),  // was 0, +1 (e) accounts.mbt:601 真问题，待修
    ("phone-en settings-new-connect-app", 1),
    ("phone-en settings-memory-doc", 1),  // was 0, +1 (g) page_node.mbt:1267 真问题，待修
    ("phone-en settings-kept", 1),
    ("phone-en settings-kept-many", 1),
    ("phone-en settings-vault-words", 14),
    ("phone-en settings-run", 1),
    ("phone-en settings-about", 1),  // was 0, +1 (g) page_node.mbt:1267 真问题，待修
    ("phone-en settings-notify-denied", 1),  // was 0, +1 (g) notify_node.mbt:671 真问题，待修
    ("phone-en share-card-poster", 3),
    ("phone-en share-card-receipt", 3),
    ("phone-en share-card-terminal", 6),
    ("phone-en share-card-senren-adv", 1),
    ("phone-en share-card-senren-ryokan", 2),
    ("phone-en share-card-senren-menu", 1),
    ("phone-en share-card-senren-ledger", 9),
    ("phone-en share-card-senren-ciallo", 19),
    ("phone-en share-card-senren-parfait", 91),
    ("phone-en share-card-senren-gacha", 5),
    ("phone-en share-card-senren-chibi", 2),
    ("phone-en share-card-senren-title", 172),
    ("phone-en share-card-senren-cg", 13),
    ("phone-en share-card-senren-affection", 42),
    ("phone-en share-card-senren-chat", 1),
    ("phone-en share-card-senren-staff", 2),
    ("phone-en share-card-senren-sword", 1),
    ("phone-en share-card-senren-kagura", 1),
    ("phone-en share-card-senren-ema", 10),
    ("phone-en share-card-senren-gahou-murasame", 4),
    ("phone-en share-card-senren-gahou-mako", 5),
    ("phone-en share-card-senren-gahou-lena", 4),
    ("phone-en share-card-senren-gahou-roka", 5),
    ("phone-en share-card-senren-gahou-koharu", 6),
    ("phone-en share-card-senren-gahou-roka2", 5),
    ("phone-en share-card-senren-photo", 1),
    ("phone-en share-card-senren-party", 1),
  ] {
    known[k.0] = k.1
  }
  known
}

///|
/// Words a box with its height said does not hold (mbui's Tester::fixed_outgrown) on each screen in a phone's window at
/// words_large_scale (words_large_wbtest.mbt), by language and screen: the bar it may only fall from, counted as the
/// rule first ran (2026-11-11). A screen not listed has none. What they are (the coordinator of the migration,
/// 2026-11-11): the share cards' stage, whose words are to keep the size the card is made at; and the old views'
/// (switcher's and search's rows, a screen's timer, a chat's old parts), mended as each is made as nodes. None is left
/// of a mark's letter (drawn at 1 as its mark is, @sf.mark_words_node), of a tag, a video's length or 用量's months (as
/// high as their words' line, @sf.tag_node, box_at, a least), or of 智能体's card's spend (on its line of 26).
let words_large_outgrown_known : Map[String, Int] = {
  let known = Map([])
  for k in [
    ("phone-en chat-image-coming", 2),
    ("phone-en chat-publish", 4),
    ("phone-en chat-screens", 8),
    ("phone-en newchat-model", 4),
    ("phone-en search-jobs", 12),
    ("phone-en search-results", 23),
    ("phone-en share-card-senren-menu", 2),
    ("phone-en share-card-senren-sword", 2),
    ("phone-en switcher", 18),
    ("phone-en switcher-found", 15),
    ("phone-zh chat-image-coming", 2),
    ("phone-zh chat-publish", 4),
    ("phone-zh chat-screens", 8),
    ("phone-zh newchat-model", 4),
    ("phone-zh search-jobs", 12),
    ("phone-zh search-results", 23),
    ("phone-zh share-card-senren-menu", 2),
    ("phone-zh share-card-senren-sword", 2),
    ("phone-zh switcher", 18),
    ("phone-zh switcher-found", 15),
  ] {
    known[k.0] = k.1
  }
  known
}

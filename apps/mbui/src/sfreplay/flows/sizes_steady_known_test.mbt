// What draws and still steps or jolts in these tests (mbui's sizes_steady.mbt: a height or a place in one frame, a
// speed off the frames round it, a dead stop, a turn back again soon), a file at a time: how many a Tester made in
// it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.sizes_steady_known([
    ("src/sfapp/tape.mbt", 1),
    ("src/sfreplay/flows/archive_restore_test.mbt", 1),
    // (words sent flying to their row as a card comes under it at once, the test's agent's: where they are drawn in
    // their row goes a few points back and forth as the row goes up under them on the list's way, one way on the
    // screen; their row stepped up in one frame before, the card's room put on at once: under_post.mbt)
    ("src/sfreplay/flows/close_option_test.mbt", 1),
    ("src/sfreplay/flows/drive_play_test.mbt", 1),
    ("src/sfreplay/flows/glass_test.mbt", 3),
    ("src/sfreplay/flows/lock_wait_test.mbt", 1),
    ("src/sfreplay/flows/new_chat_test.mbt", 2),
    ("src/sfreplay/flows/service_page_test.mbt", 3),
    ("src/sfreplay/flows/settings_connect_test.mbt", 26),
    ("src/sfreplay/flows/settings_run_settings_test.mbt", 2),
    ("src/sfreplay/flows/settings_vault_item_test.mbt", 2),
    ("src/sfreplay/flows/share_new_chat_test.mbt", 6),
    ("src/sfreplay/flows/sheet_drag_test.mbt", 1),
    ("src/sfreplay/flows/viewer_test.mbt", 2),
    ("src/sfreplay/flows/wide_switcher_test.mbt", 2),
  ])
}

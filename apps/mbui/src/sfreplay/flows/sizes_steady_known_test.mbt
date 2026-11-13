// What draws and still steps or jolts in these tests (mbui's sizes_steady.mbt: a height or a place in one frame, a
// speed off the frames round it, a dead stop, a turn back again soon), a file at a time: how many a Tester made in
// it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.sizes_steady_known([
    ("src/sfapp/tape.mbt", 1),
    ("src/sfreplay/flows/archive_restore_test.mbt", 1),
    ("src/sfreplay/flows/glass_test.mbt", 1),
    ("src/sfreplay/flows/new_chat_test.mbt", 1),
    ("src/sfreplay/flows/service_page_test.mbt", 1),
    ("src/sfreplay/flows/settings_connect_test.mbt", 4),
    ("src/sfreplay/flows/settings_run_settings_test.mbt", 1),
    ("src/sfreplay/flows/settings_vault_item_test.mbt", 1),
    ("src/sfreplay/flows/share_new_chat_test.mbt", 1),
    ("src/sfreplay/flows/sheet_drag_test.mbt", 1),
    // (a station renamed: its usage's 75% line comes 52 in a frame as its answer comes, since the framework's change
    // for answers at once where it made its way in before; the steadiness exemption's change, then the page's)
    ("src/sfreplay/flows/station_rename_test.mbt", 1),
    ("src/sfreplay/flows/viewer_test.mbt", 2),
    // (shown as the replay gives each message at its own moment, a device's timing: the answer's words in the old
    // chat page's state row (made at mbui/src/ui/nav_view.mbt:258, the old view's) step 4.03 in the frame at 1383.3
    // between 0 and -0.6, the row's change set out from the frame that builds it. Goes as the chat page is made as
    // nodes)
    ("src/sfreplay/flows/wide_switcher_test.mbt", 2),
  ])
}

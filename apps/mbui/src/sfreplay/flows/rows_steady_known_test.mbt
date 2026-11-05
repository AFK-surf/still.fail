// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list turning back again soon
// after it turned, or going at a speed off the frames round it, while what is in the list moves), a file at a time:
// how many a Tester made in it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0
// leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    // (Android's runs played again, src/sfapp/tape.mbt)
    ("src/sfapp/tape.mbt", 1),
    ("src/sfreplay/flows/answer_option_test.mbt", 2),
    ("src/sfreplay/flows/bar_archive_test.mbt", 2),
    ("src/sfreplay/flows/card_motion_test.mbt", 1),
    ("src/sfreplay/flows/drive_upload_test.mbt", 1),
    // (rolled back to 0.1.7190's chat page, 2026-11-05: a chat row jumps 8.5 in a frame as a message comes in; to be
    // found and mended, then this taken out)
    ("src/sfreplay/flows/glass_test.mbt", 1),
    ("src/sfreplay/flows/history_test.mbt", 1),
    ("src/sfreplay/flows/offline_retry_test.mbt", 1),
    ("src/sfreplay/flows/settings_add_station_test.mbt", 1),
    ("src/sfreplay/flows/settings_connect_test.mbt", 1),
    ("src/sfreplay/flows/settings_run_settings_test.mbt", 2),
    ("src/sfreplay/flows/settings_station_mark_test.mbt", 1),
    ("src/sfreplay/flows/settings_station_settings_test.mbt", 1),
    ("src/sfreplay/flows/share_test.mbt", 1),
    ("src/sfreplay/flows/station_rename_test.mbt", 1),
  ])
}

// The files whose Testers still show faults of how what moves goes at 60 and 120 a second (mbui's tester.mbt,
// motion_counted: what CI's runs count, `scripts/motion_said.sh`): only counted there; every other file is judged, a
// fault failing its test. Only shrinks: a file mended to none leaves the list.

///|
fn init {
  @ui.motion_counted([
    "src/sfapp/tape.mbt",
    "src/sfreplay/flows/archive_restore_test.mbt",
    "src/sfreplay/flows/card_motion_test.mbt",
    "src/sfreplay/flows/drive_upload_test.mbt",
    "src/sfreplay/flows/glass_test.mbt",
    "src/sfreplay/flows/new_chat_test.mbt",
    "src/sfreplay/flows/offline_retry_test.mbt",
    "src/sfreplay/flows/pick_words_test.mbt",
    // (new 2026-11-10, counted from their start for what every flow here shows of the page and the composer they set
    // out from: at 60 the bottom bar's room, going as the chat is pushed over Home, is drawn twice 0.7 ms apart as
    // the core's word comes between two frames, read as a frame it stood still (send_paced); at 120 the list's foot
    // under the composer goes back a little as words are sent from it 33 ms after it came to rest (send_card_paced))
    "src/sfreplay/flows/send_card_paced_test.mbt",
    "src/sfreplay/flows/settings_connect_test.mbt",
    "src/sfreplay/flows/settings_run_settings_test.mbt",
    "src/sfreplay/flows/settings_vault_item_test.mbt",
    "src/sfreplay/flows/share_files_test.mbt",
    "src/sfreplay/flows/share_new_chat_test.mbt",
    "src/sfreplay/flows/share_test.mbt",
    "src/sfreplay/flows/sheet_drag_test.mbt",
    "src/sfreplay/flows/station_file_sent_test.mbt",
    "src/sfreplay/flows/viewer_test.mbt",
    "src/sfreplay/flows/wide_answer_reply_test.mbt",
    "src/sfreplay/flows/wide_switcher_test.mbt",
  ])
}

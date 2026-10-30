// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list going one way and back, or at a
// speed off the frames round it, while what is in the list moves), a file at a time: how many a Tester made in it may
// show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    // (Android's runs played again, src/sfapp/tape.mbt)
    ("src/sfapp/tape.mbt", 8),
    // (short chats' rows at their end since 2026-10-30, as long ones': what sending does to the rows over the composer
    // shows in them too, the composer's room let go on a way of its own beside the message's coming in; the next to mend)
    ("src/sfreplay/flows/agent_reply_test.mbt", 1),
    ("src/sfreplay/flows/answer_option_test.mbt", 5),
    ("src/sfreplay/flows/bar_archive_test.mbt", 2),
    ("src/sfreplay/flows/card_motion_test.mbt", 8),
    // (a row leaves before its room closes since 2026-10-30, docs/list-motion.md: the chat's state line gone as words
    // are sent and back with the agent's answer some 200 ms on, its room just set out closing, opens again)
    ("src/sfreplay/flows/close_option_test.mbt", 2),
    ("src/sfreplay/flows/dismiss_test.mbt", 2),
    ("src/sfreplay/flows/drive_delete_test.mbt", 1),
    ("src/sfreplay/flows/drive_rename_test.mbt", 3),
    ("src/sfreplay/flows/drive_upload_test.mbt", 4),
    ("src/sfreplay/flows/glass_test.mbt", 2),
    ("src/sfreplay/flows/history_test.mbt", 1),
    ("src/sfreplay/flows/new_chat_test.mbt", 1),
    ("src/sfreplay/flows/notice_looking_test.mbt", 1),
    ("src/sfreplay/flows/notify_off_test.mbt", 2),
    ("src/sfreplay/flows/offline_retry_test.mbt", 1),
    ("src/sfreplay/flows/open_link_test.mbt", 1),
    ("src/sfreplay/flows/paste_long_test.mbt", 1),
    ("src/sfreplay/flows/quote_test.mbt", 1),
    ("src/sfreplay/flows/send_text_test.mbt", 2),
    ("src/sfreplay/flows/settings_add_station_test.mbt", 2),
    ("src/sfreplay/flows/settings_connect_test.mbt", 5),
    ("src/sfreplay/flows/settings_decisions_test.mbt", 1),
    ("src/sfreplay/flows/settings_run_settings_test.mbt", 1),
    ("src/sfreplay/flows/settings_station_mark_test.mbt", 3),
    ("src/sfreplay/flows/settings_station_settings_test.mbt", 1),
    ("src/sfreplay/flows/settings_vault_item_test.mbt", 1),
    ("src/sfreplay/flows/settings_workspace_people_test.mbt", 1),
    ("src/sfreplay/flows/share_new_chat_test.mbt", 1),
    ("src/sfreplay/flows/share_test.mbt", 1),
    ("src/sfreplay/flows/station_rename_test.mbt", 1),
    ("src/sfreplay/flows/wide_switcher_test.mbt", 1),
  ])
}

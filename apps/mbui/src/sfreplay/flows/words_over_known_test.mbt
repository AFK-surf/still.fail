// The words over words these tests still show while something moves (mbui's words_over.mbt), a file at a time: how
// many pairs a Tester made in it may show. Each only falls: a motion mended takes its file's number down, and a file
// at 0 leaves the list.

///|
fn init {
  @ui.words_over_known([
    // (Android's runs played again, src/sfapp/tape.mbt)
    ("src/sfapp/tape.mbt", 1),
    ("src/sfreplay/flows/answer_option_test.mbt", 3),
    ("src/sfreplay/flows/bar_going_down_test.mbt", 2),
    // (recorded again for #2642: its run's own pairs, none of them the cards'; fewer since words sent flying and an
    // answer coming in over the end make room for what they pass, #2674 and #2689)
    ("src/sfreplay/flows/card_motion_test.mbt", 6),
    ("src/sfreplay/flows/chat_audio_test.mbt", 1),
    ("src/sfreplay/flows/chinese_enter_test.mbt", 2),
    ("src/sfreplay/flows/close_option_test.mbt", 1),
    ("src/sfreplay/flows/dismiss_test.mbt", 1),
    ("src/sfreplay/flows/history_test.mbt", 2),
    ("src/sfreplay/flows/markdown_test.mbt", 1),
    ("src/sfreplay/flows/new_chat_test.mbt", 4),
    ("src/sfreplay/flows/notice_failed_test.mbt", 1),
    ("src/sfreplay/flows/open_link_test.mbt", 1),
    ("src/sfreplay/flows/paste_long_test.mbt", 3),
    ("src/sfreplay/flows/paste_short_test.mbt", 2),
    ("src/sfreplay/flows/pick_words_test.mbt", 3),
    ("src/sfreplay/flows/quote_test.mbt", 3),
    ("src/sfreplay/flows/send_flying_test.mbt", 2),
    ("src/sfreplay/flows/send_text_test.mbt", 2),
    ("src/sfreplay/flows/service_page_test.mbt", 3),
    ("src/sfreplay/flows/share_files_test.mbt", 5),
    ("src/sfreplay/flows/share_new_chat_test.mbt", 1),
    ("src/sfreplay/flows/share_test.mbt", 1),
    // (one more since what comes out from under a cut fades by each pixel, not by its line (2026-10-30): the failure
    // notice's 「·」 and 「上报」 meet as it comes in, faint in the fade, wholly faded before)
    ("src/sfreplay/flows/sheets_sinking_test.mbt", 2),
    ("src/sfreplay/flows/station_file_sent_test.mbt", 3),
    ("src/sfreplay/flows/station_files_test.mbt", 1),
    ("src/sfreplay/flows/viewer_test.mbt", 6),
    ("src/sfreplay/flows/wide_resize_test.mbt", 1),
  ])
}

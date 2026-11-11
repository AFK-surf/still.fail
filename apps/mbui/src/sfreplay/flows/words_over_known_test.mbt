// The words over words these tests still show while something moves (mbui's words_over.mbt), a file at a time: how
// many pairs a Tester made in it may show. Each only falls: a motion mended takes its file's number down, and a file
// at 0 leaves the list.

///|
fn init {
  @ui.words_over_known([
    // (Android's runs played again, src/sfapp/tape.mbt)
    // (recorded again for #2642: its run's own pairs, none of them the cards'; fewer since words sent flying and an
    // answer coming in over the end make room for what they pass, #2674 and #2689)
    ("src/sfreplay/flows/chat_audio_test.mbt", 1),
    ("src/sfreplay/flows/pick_words_test.mbt", 2),
    // (one more since what comes out from under a cut fades by each pixel, not by its line (2026-10-30): the failure
    // notice's 「·」 and 「上报」 meet as it comes in, faint in the fade, wholly faded before)
    // (one more since an agent's line comes in opening its room, not there at once (2026-10-30, rows_steady.mbt):
    // the failure notice's 「·」 and 「上报」 meet as it comes in under the cut, faint in its fade, as sheets_sinking's)
    // (a new chat left for a short chat, fading where it is over it: its rows at its end since 2026-10-30, short chats'
    // as long ones', the new chat's lines over them as it fades (as over any long chat's): the leaving page's to mend)
    ("src/sfreplay/flows/wide_resize_test.mbt", 1),
    ("src/sfreplay/flows/wide_answer_reply_test.mbt", 1),
    ("src/sfreplay/flows/wide_send_test.mbt", 1),
  ])
}

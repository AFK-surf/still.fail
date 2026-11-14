// The words over words these tests still show while something moves (mbui's words_over.mbt), a file at a time: how
// many pairs a Tester made in it may show. Each only falls: a motion mended takes its file's number down, and a file
// at 0 leaves the list.

///|
fn init {
  @ui.words_over_known([
    // (shown as the replay gives each message at its own moment and draws on the run's display's frames, a device's
    // timing: the words sent leaving the old composer pass over its pasted card's 「6,000 字符」 at 1673.6. Goes as the
    // composer and the chat's message list are made as nodes)
    ("src/sfreplay/flows/paste_long_test.mbt", 1),
    // (+1, the third, the same way: the quote sent passing over the old composer's 「添加说明（可选）」 at 4336.9. Goes
    // as the composer is made as nodes)
    ("src/sfreplay/flows/pick_words_test.mbt", 3),
    // (one more since what comes out from under a cut fades by each pixel, not by its line (2026-10-30): the failure
    // notice's 「·」 and 「上报」 meet as it comes in, faint in the fade, wholly faded before)
    // (one more since an agent's line comes in opening its room, not there at once (2026-10-30, rows_steady.mbt):
    // the failure notice's 「·」 and 「上报」 meet as it comes in under the cut, faint in its fade, as sheets_sinking's)
    // (a new chat left for a short chat, fading where it is over it: its rows at its end since 2026-10-30, short chats'
    // as long ones', the new chat's lines over them as it fades (as over any long chat's): the leaving page's to mend)
    ("src/sfreplay/flows/wide_answer_reply_test.mbt", 1),
  ])
}

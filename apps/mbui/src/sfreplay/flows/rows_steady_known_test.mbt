// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list turning back again soon
// after it turned, or going at a speed off the frames round it, while what is in the list moves), a file at a time:
// how many a Tester made in it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0
// leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    // (Android's runs played again, src/sfapp/tape.mbt)
    ("src/sfapp/tape.mbt", 1),
    // (归档 pressed in the chat's bar: the list's foot stands taller at once as the composer goes, where the chat
    // stands closing over the way, so what is over them goes up 42 in a frame and back, its page leaving for Home;
    // rows_step_least's finding)
    ("src/sfreplay/flows/bar_archive_test.mbt", 1),
    ("src/sfreplay/flows/drive_upload_test.mbt", 1),
    ("src/sfreplay/flows/share_test.mbt", 1),
    // (where the chat stands gone as its agent set to work and back as its turn ended a moment after, its room still
    // closing where it was: put at the end at once, what came between a step up; rows_step_least's first finding)
    ("src/sfreplay/flows/wide_answer_reply_test.mbt", 1),
  ])
}

// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list turning back again soon
// after it turned, or going at a speed off the frames round it, while what is in the list moves), a file at a time:
// how many a Tester made in it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0
// leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    // (归档 pressed in the chat's bar: the list's foot stands taller at once as the composer goes, where the chat
    // stands closing over the way, so what is over them goes up 42 in a frame and back, its page leaving for Home;
    // rows_step_least's finding)
    ("src/sfreplay/flows/bar_archive_test.mbt", 1),
    // (the old chat list's foot row, an old fault: it stands 65-81 ms into its list's way, then goes a whole step in one
    // frame. main 0, -5.72, -5.96 a frame, 2.74 off its frames round it for 2.98 judged; with every way at its exact
    // moment 0, -6.16, -5.85, 3.24 for 2.92. Taken away as the node list takes its place)
    ("src/sfreplay/flows/dismiss_test.mbt", 1),
    ("src/sfreplay/flows/drive_upload_test.mbt", 1),
    // (the same old fault of the old chat list's foot row, at 60 a second: 58-68 ms into its way, then a whole step.
    // main 0, -11.16, -11.46, 5.43 for 5.73; at the exact moment 0, -11.84, -11.52, 6.07 for 5.76. Taken away as the
    // node list takes its place)
    ("src/sfreplay/flows/paste_long_test.mbt", 1),
    ("src/sfreplay/flows/share_test.mbt", 1),
  ])
}

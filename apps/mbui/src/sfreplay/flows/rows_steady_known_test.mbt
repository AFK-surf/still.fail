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
    // (shown as the replay gives each message at its own moment, a device's timing, where main's gave each at a frame:
    // the old chat page's message list sets each change out from the frame that builds it, 2483.3, 2500 and 2516.7 one
    // after the other, its rows' way set out again each time, so the newest row turns back after 66.7 ms. Goes as the
    // chat's message list is made as nodes)
    ("src/sfreplay/flows/card_motion_test.mbt", 1),
    // (shown as the replay gives each message at its own moment and draws on the run's display's frames, a device's
    // timing: the old composer's line break (foot changed at 2437.2) takes the old chat list's top row a frame's step
    // off its way's (-10.85 between -0.95 and -6.85). Goes as the chat's message list and composer are made as nodes)
    ("src/sfreplay/flows/chinese_enter_test.mbt", 1),
    // (the old chat list's foot row, an old fault: it stands 65-81 ms into its list's way, then goes a whole step in one
    // frame. main 0, -5.72, -5.96 a frame, 2.74 off its frames round it for 2.98 judged; with every way at its exact
    // moment 0, -6.16, -5.85, 3.24 for 2.92. Taken away as the node list takes its place)
    ("src/sfreplay/flows/drive_upload_test.mbt", 1),
    // (the same old fault of the old chat list's foot row, at 60 a second: 58-68 ms into its way, then a whole step.
    // main 0, -11.16, -11.46, 5.43 for 5.73; at the exact moment 0, -11.84, -11.52, 6.07 for 5.76. Taken away as the
    // node list takes its place)
    ("src/sfreplay/flows/paste_long_test.mbt", 1),
    // (+1 here, and share_files' one: the old chat page's message list and its old composer, two ways of other causes
    // one after the other on the newest message's state row: the composer emptied as it is sent takes the row down
    // ~60, the answers after it take it back up ~13. main has the same two, the same sizes; where they meet goes by
    // when the send's answer comes, which a device does not choose either: as #5625 has the chat's reads asked as it
    // opens, the answer comes 133 ms sooner (share: "went 58.08 one way, stood 133.3 ms, came back 2.64") and 170 ms
    // sooner (share-files: "went 2.76 one way, stood 66.7 ms, came back 5.39"). Taken away as the node message list
    // makes the two one way with the composer)
    // (+1, the third: shown as the replay gives each message at its own moment, a device's timing, the share's sheet
    // put up and the link sent at theirs: the same two ways on the newest row, the composer emptied at 1580.9 and the
    // answers at 1610.8, "went 13.71 one way, stood 47.7 ms, came back 5.18". Goes as the node message list makes the
    // two one way with the composer)
    // (+1, the fourth, seen once the third was held: the same two ways of the same causes (the composer emptied at
    // 1580.9, the answers and the agent's state going at 1610.8) on that message's state row, taken across the run's
    // display's frames at 1681.0, 1689.4 and 1706.6, uneven as a device's are: "went -1.98 a frame between 4.63 and
    // -1.69". main's app (src/sfapp/app.mbt, src/sfbase/source.mbt, src/sfbase/workspace_switch.mbt, src/sfdesk/frame.mbt
    // as main has them) on the same replay shows the same four, the same row and words. Goes with the third)
    ("src/sfreplay/flows/share_test.mbt", 4),
  ])
}

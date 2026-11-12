// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list turning back again soon
// after it turned, or going at a speed off the frames round it, while what is in the list moves), a file at a time:
// how many a Tester made in it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0
// leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    // (words sent in a chat, the core answering 300 to 700 ms after: a row above them goes 82 in a frame as it comes,
    // every screen, at 60 and 120)
    ("src/sfapp/core_pace_rows_wbtest.mbt", 1),
    // (大屏 at 1.3, the chat's panel opened and closed: a row of the chat goes 14 one way, stands 217 ms and comes back
    // 2.8, at 60 and 120)
    ("src/sfapp/daily_paths_wbtest.mbt", 1),
    ("src/sfapp/desk_service_wbtest.mbt", 1),
  ])
}

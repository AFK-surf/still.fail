// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list turning back again soon
// after it turned, or going at a speed off the frames round it, while what is in the list moves), a file at a time:
// how many a Tester made in it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0
// leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    // (each screen walked over a core answering late, at 60 and 120, as an answer comes: 小屏's 文件 list's foot goes 96
    // in a frame (82 on 大屏), 账号's second row -235, a chat's row -60 to -82, 归档's second row -3; the framework's change for answers, then
    // the list's line)
    ("src/sfapp/answers_still_wbtest.mbt", 4),
    // (words sent in a chat, the core answering 300 to 700 ms after: a row above them goes 82 in a frame as it comes,
    // every screen, at 60 and 120)
    ("src/sfapp/core_pace_rows_wbtest.mbt", 1),
    // (大屏 at 1.3, the chat's panel opened and closed: a row of the chat goes 14 one way, stands 217 ms and comes back
    // 2.8, at 60 and 120)
    ("src/sfapp/daily_paths_wbtest.mbt", 1),
    ("src/sfapp/desk_service_wbtest.mbt", 1),
    // (小屏, a place's first list after a wait: 工作站's foot goes -176 in a frame as its answer comes, 共享调试's heading
    // +136, at 60 and 120. Before the framework's change for answers these made their way in with no cause; now they
    // are at once and push what is under them: the steadiness exemption's change, then the pages')
    ("src/sfapp/place_first_wbtest.mbt", 1),
    // (大屏 over a core answering late: a chat's rows go -73 to -82 in a frame as its answer comes, 归档's second row -4,
    // at 60 and 120)
    ("src/sfapp/ways_told_wbtest.mbt", 3),
  ])
}

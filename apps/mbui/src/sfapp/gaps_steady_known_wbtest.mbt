// The rooms between two lines of words that open and close again on their way, both moving, these tests still show
// (mbui's gaps_steady.mbt), a file at a time: how many a Tester made in it may show. Each only falls: one mended
// takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.gaps_steady_known([
    // (the same as send_steady_wbtest's, from #5256 on, in each file that sends twice in a chat)
    ("src/sfapp/again_wbtest.mbt", 1),
    ("src/sfapp/composer_wbtest.mbt", 1),
    // (send_steady_wbtest's, 中屏 and 大屏 words sent in a chat, the core answering at any moment: 94→117→115, at 60
    // and 120)
    ("src/sfapp/core_pace_rows_wbtest.mbt", 1),
    ("src/sfapp/core_pace_wbtest.mbt", 1),
    // (send_steady_wbtest's, 小屏 words sent in a chat: the agent's row over them opens 100→104 and closes to 100, at 60)
    ("src/sfapp/daily_paths_wbtest.mbt", 1),
    // (send_steady_wbtest's, on host frames, both sends)
    ("src/sfapp/emit_kept_wbtest.mbt", 2),
    // (send_steady_wbtest's, on its first send)
    ("src/sfapp/linger_wbtest.mbt", 1),
    // (send_steady_wbtest's, its words sent flying)
    ("src/sfapp/motion_wbtest.mbt", 1),
    ("src/sfapp/quote_image_wbtest.mbt", 1),
    // (sent with a quote: the agent's row over it opens 82→91 and closes to 87 as the sent one comes; the quote over
    // its first line closes 40→18 and opens to 20)
    ("src/sfapp/send_hold_wbtest.mbt", 1),
    // (the agent's row over words sent opens 81→102 and closes to 98: the user's 「距离能突变三次」, back with #5231 taken
    // out by #5256 till the list's motion is made again)
    ("src/sfapp/send_steady_wbtest.mbt", 1),
    ("src/sfapp/station_peek_wbtest.mbt", 1),
    ("src/sfapp/wide_wbtest.mbt", 2),
  ])
}

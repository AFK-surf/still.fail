// What draws and still steps or jolts in these tests (mbui's sizes_steady.mbt: a height or a place in one frame, a
// speed off the frames round it, a dead stop, a turn back again soon), a file at a time: how many a Tester made in
// it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.sizes_steady_known([
    // (小屏, a new chat's first words, the core answering a frame or more after: 预设's column comes 52 in a frame, at 60
    // and 120)
    ("src/sfapp/core_pace_presets_wbtest.mbt", 1),
    // (小屏, a new chat's long first words sent, at both sizes of words: the composer's field steps 31 points in a frame
    // at 2157 ms, between -13 and 26 round it; at 60 and 120 a frame it stops dead from 40 a frame as well, and 预设's
    // column comes 52 in a frame at 1583)
    ("src/sfapp/daily_paths_wbtest.mbt", 2),
    ("src/sfapp/desk_service_wbtest.mbt", 1),
    ("src/sfapp/home_wbtest.mbt", 1),
    ("src/sfapp/menu_node_wbtest.mbt", 12),
    // (the old composer's caption line 添加说明（可选）, an old fault: its place steps as the quoted picture's room comes
    // in, main -4.82, -12.41, -9.65 a frame round 1566.67, under what is judged; with every way at its exact moment
    // -4.74, -12.83, -9.41, over it. Taken away as the node composer takes its place)
    ("src/sfapp/quote_image_wbtest.mbt", 1),
    ("src/sfapp/settings_wbtest.mbt", 4),
    ("src/sfapp/squeeze_wbtest.mbt", 281),
    ("src/sfapp/stack_over_wbtest.mbt", 1),
    ("src/sfapp/tape.mbt", 1),
    ("src/sfapp/viewer_media_over_wbtest.mbt", 1),
    // (the old list's row growing to the 5000 its page says, 中屏 on the tape, at 60: the words and the picture under
    // the page stop dead from 6.1 a frame as the old view's way to that height ends (9.3, 7.5, 6.1, then none). An old
    // fault, on main the same numbers a frame later, at 2066.67, one frame past where its test stopped looking, and
    // counted already in the cases whose Testers chat_wbtest's helper makes: what a page says is taken as a frame
    // begins now, a frame sooner, so its end is among the frames judged. Taken away with the old chat's page: the row
    // made as nodes goes there by the list's own way)
    ("src/sfapp/viz_wbtest.mbt", 2),
    ("src/sfapp/wide_rail_wbtest.mbt", 4),
    ("src/sfapp/wide_wbtest.mbt", 5),
  ])
}

// What draws and still steps or jolts in these tests (mbui's sizes_steady.mbt: a height or a place in one frame, a
// speed off the frames round it, a dead stop, a turn back again soon), a file at a time: how many a Tester made in
// it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.sizes_steady_known([
    ("src/sfapp/desk_service_wbtest.mbt", 2),
    ("src/sfapp/home_wbtest.mbt", 11),
    ("src/sfapp/menu_node_wbtest.mbt", 23),
    // (the chat's "…" on 小屏, then the chat left: the old view's bottom bar, going down out of the way under the chat
    // page coming in, turned back as it went (bar.mbt Glide::go_by, a Move from its speed down) and stopped dead, at
    // 120 a frame alone: `col "": its place stopped dead from 3.3337772310397065 a frame (5.482485712573649 before;
    // slowing -0.07566634401458572 then 3.316635632436745) at 1650`. The same on 2b9a77c28c^, before press_wait; an old
    // fault (the user, 2026-11-11: each one found old is known, 1). Taken away as 小屏's bottom bar is made as nodes)
    ("src/sfapp/press_waits_wbtest.mbt", 1),
    // (the old composer's caption line 添加说明（可选）, an old fault: its place steps as the quoted picture's room comes
    // in, main -4.82, -12.41, -9.65 a frame round 1566.67, under what is judged; with every way at its exact moment
    // -4.74, -12.83, -9.41, over it. Taken away as the node composer takes its place)
    ("src/sfapp/quote_image_wbtest.mbt", 1),
    ("src/sfapp/settings_wbtest.mbt", 8),
    ("src/sfapp/squeeze_wbtest.mbt", 281),
    ("src/sfapp/stack_over_wbtest.mbt", 6),
    ("src/sfapp/tape.mbt", 1),
    ("src/sfapp/viewer_media_over_wbtest.mbt", 1),
    ("src/sfapp/wide_rail_wbtest.mbt", 4),
    ("src/sfapp/wide_wbtest.mbt", 18),
  ])
}

// The rows not steady these tests still show (mbui's rows_steady.mbt: a row of a list going one way and back, or at a
// speed off the frames round it, while what is in the list moves), a file at a time: how many a Tester made in it may
// show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.rows_steady_known([
    ("src/sfapp/cards_wbtest.mbt", 1),
    ("src/sfapp/chat_wbtest.mbt", 4),
    ("src/sfapp/composer_wbtest.mbt", 4),
    ("src/sfapp/decide_wbtest.mbt", 1),
    ("src/sfapp/desk_service_wbtest.mbt", 1),
    ("src/sfapp/drive_wbtest.mbt", 1),
    ("src/sfapp/image_corners_chat_wbtest.mbt", 3),
    ("src/sfapp/quote_image_wbtest.mbt", 2),
    ("src/sfapp/settings_wbtest.mbt", 1),
    ("src/sfapp/tape.mbt", 8),
    ("src/sfapp/viz_wbtest.mbt", 2),
    ("src/sfapp/wide_panel_wbtest.mbt", 2),
    ("src/sfapp/wide_wbtest.mbt", 2),
  ])
}

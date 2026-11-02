// The words over words these tests still show while something moves (mbui's words_over.mbt), a file at a time: how
// many pairs a Tester made in it may show. Each only falls: a motion mended takes its file's number down, and a file
// at 0 leaves the list.

///|
fn init {
  // The requested whole-panel fade lets the page show through for its last frames. Keep this exception exact: the
  // checker still reports every other overlap, and even this pair outside a closing layer.
  @ui.words_over_closing_expected([
    ("src/sfapp/model_pop_wbtest.mbt", "想让 agent 做什么？", "高"),
  ])
  @ui.words_over_known([
    ("src/sfapp/composer_wbtest.mbt", 2),
    ("src/sfapp/newchat_send_wbtest.mbt", 1),
    ("src/sfapp/preview_wbtest.mbt", 13),
    ("src/sfapp/publish_wbtest.mbt", 1),
    ("src/sfapp/quote_image_wbtest.mbt", 2),
    ("src/sfapp/screens_wbtest.mbt", 42),
    ("src/sfapp/stations_now_wbtest.mbt", 3),
    ("src/sfapp/tape.mbt", 1),
    ("src/sfapp/wide_publish_wbtest.mbt", 3),
    ("src/sfapp/wide_wbtest.mbt", 3),
  ])
}

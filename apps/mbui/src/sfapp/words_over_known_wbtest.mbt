// The words over words these tests still show while something moves (mbui's words_over.mbt), a file at a time: how
// many pairs a Tester made in it may show. Each only falls: a motion mended takes its file's number down, and a file
// at 0 leaves the list.

///|
fn init {
  // The requested whole-panel fade lets the page show through for its last frames. Keep this exception exact: the
  // checker still reports every other overlap, and even this pair outside a closing layer.
  @ui.words_over_closing_expected([
    ("src/sfapp/model_pop_wbtest.mbt", "想让 agent 做什么？", "DeepSeek V4.1 Flash"),
    ("src/sfapp/model_pop_wbtest.mbt", "想让 agent 做什么？", "GPT-6"),
    // (the configurations used most a row each: the first level taller, a configuration's capsule over the words)
    ("src/sfapp/model_pop_wbtest.mbt", "想让 agent 做什么？", "DSH · 高"),
    ("src/sfapp/model_pop_wbtest.mbt", "想让 agent 做什么？", "高"),
    ("src/sfapp/model_pop_wbtest.mbt", "描述要做的事。它会在 Willow 上使用所选模型新建会话。", "GPT-6 Astra"),
    ("src/sfapp/model_pop_wbtest.mbt", "描述要做的事。它会在 Willow 上使用所选模型新建会话。", "中"),
    ("src/sfapp/model_pop_wbtest.mbt", "描述要做的事。它会在 Willow 上使用所选模型新建会话。", "Opus 5.5"),
    // (the card to share's stage fading as it closes, the picture a line higher since its looks are in sets: a day's
    // date under its bar over the new chat's words)
    ("src/sfapp/stations_now_wbtest.mbt", "描述要做的事。它会在 Willow 上使用所选模型新建会话。", "10/26"),
  ])
  @ui.words_over_known([
    ("src/sfapp/composer_wbtest.mbt", 2),
    ("src/sfapp/preview_wbtest.mbt", 1),
    ("src/sfapp/wide_wbtest.mbt", 2),
  ])
}

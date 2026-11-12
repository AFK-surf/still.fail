// The rooms between two lines of words that open and close again on their way, both moving, these tests still show
// (mbui's gaps_steady.mbt), a file at a time: how many a Tester made in it may show. Each only falls: one mended
// takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.gaps_steady_known([
    ("src/sfreplay/flows/archive_restore_test.mbt", 1),
    ("src/sfreplay/flows/glass_test.mbt", 1),
    ("src/sfreplay/flows/markdown_test.mbt", 1),
    // (this one and wide_answer_reply's: shown as the replay gives each message at its own moment, a device's timing,
    // where main's gave each at a frame: the old chat page's message list sets a row's change out from the frame that
    // builds it, so the room by the agent's line opens on one cause's way and closes on the next's ("20 to 105.04 and
    // back to 102.39 at 2550"; wide: "104.02 to 110.59 and back to 102.53 at 1450"). Goes as the chat's message list is
    // made as nodes)
    ("src/sfreplay/flows/offline_retry_test.mbt", 1),
    ("src/sfreplay/flows/send_flying_test.mbt", 1),
    // (two: the old chat page's message list and its old composer, the newly sent e2e-doc's row going down as the
    // composer empties, then up again with the answers after it: the room by it opened then closed, by the row its
    // first way stopped beside. main's one, the same fault met the other way: "answered the question th… | e2e-doc:
    // the room between them went 41.09 to 44.28 and back to 41.97 at 3300"; and as #5625 has the chat's reads asked
    // as it opens, its send's answer 170 ms sooner: "你好，我是测试用的 agent | e2e-doc: the room between them went
    // 278.98 to 293.06 and back to 288.80 at 3183.3". When a device's answer comes is no app's to say: both are a
    // device's. Taken away as the node message list makes the two one way with the composer)
    ("src/sfreplay/flows/share_files_test.mbt", 1),
    ("src/sfreplay/flows/viewer_test.mbt", 1),
  ])
}

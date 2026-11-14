// What a test reads of the app before its own run has begun is the run before's (detlint's read-before-run): the two
// run in this order in one process, the first leaving the core's prefs saying English (gate_wbtest's), the second
// finding each landing's title in the words of its own run all the same (landing_node_wbtest's). Before 2026-11-11 the
// landing read its titles' words before its new_run, in English, and found none of them in the Chinese it drew,
// where CI's grouping put the two files in one process (#5433).

///|
test "a run whose core's prefs say English leaves the app saying English" {
  let (_t, _) = gate_cold(lang="en", locale="zh-CN")
  assert_eq(@sf.language(), "en")
}

///|
test "the next test's landing, its words read in its own run: each title found, whatever the run before said" {
  let (seen, all) = landing_titles()
  assert_eq(seen, all)
}

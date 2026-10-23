// A link within a sentence to one of the message's files (messages.mbt agent_words, Prose.kt OpenedFile), its address
// escaped as the station sends it (MBUI_FIXTURE=chat-file-links): a visualization opened over the whole screen, any
// other file in the preview.

///|
test "file links: the tree's words are the message's" {
  let t = file_links_answer
  assert_eq(t.view(start_offset=4, end_offset=8).to_string(), "发布节奏")
  assert_eq(t.view(start_offset=25, end_offset=29).to_string(), "，草图在")
  assert_eq(t.view(start_offset=30, end_offset=34).to_string(), "界面草图")
  assert_eq(t.view(start_offset=77).to_string(), "。")
}

///|
test "file links: an escaped link to the visualization opens it over the whole screen" {
  let t = chat_tester("chat-file-links")
  t.frame()
  assert_true(t.find("release.html") is None)
  t.tap_run("发布节奏")
  t.frame()
  assert_true(t.find("release.html") is Some(_))
  t.back()
  t.frame()
  assert_true(t.find("release.html") is None)
}

///|
test "file links: an escaped link to a picture opens it in the preview" {
  let t = chat_tester("chat-file-links")
  t.frame()
  assert_true(t.find("界面草图.png") is None)
  t.tap_run("界面草图")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("界面草图.png") is Some(_))
}

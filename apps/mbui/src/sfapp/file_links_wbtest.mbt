// A link within a sentence to one of the message's files (messages.mbt agent_words), its address
// escaped as the station sends it (MBUI_FIXTURE=chat-file-links): a visualization opened over the whole screen, any
// other file in the preview.

///|
test "file links: the tree's words are the message's" {
  let t = file_links_answer
  assert_eq(t.exact_view(start=4, end=8).to_owned(), "发布节奏")
  assert_eq(t.exact_view(start=25, end=29).to_owned(), "，草图在")
  assert_eq(t.exact_view(start=30, end=34).to_owned(), "界面草图")
  assert_eq(t.exact_view(start=77).to_owned(), "。")
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
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("界面草图.png") is Some(_))
}

///|
test "a table's cells of the message's pictures (MBUI_FIXTURE=chat-table-images): the pictures, not their names" {
  let t = chat_tester("chat-table-images")
  t.frame()
  assert_eq(table_images_answer.exact_view(start=7, end=11).to_owned(), "手机网页")
  assert_true(t.find("手机网页") is Some(_))
  assert_true(t.find("phone.png") is None)
  // the picture itself, opening in the preview
  t.click(Button, label=@sf.t("web-main.file.view", args=[("name", "phone.png")]))
  // (on its way in)
  t.run_for(@ui.move_most_ms / 2.0)
  assert_true(t.find("phone.png") is Some(_))
}

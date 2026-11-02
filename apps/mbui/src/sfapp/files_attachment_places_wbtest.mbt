// The places offered when attaching a station file follow the same favorites as the files page.

///|
test "the attachment picker uses the personal shortcuts" {
  new_run()
  let src = fixture("chat")
  @sfdesk.favorite_add(src, "ws1", { station: "ws1/st1", root: "/Users/lin", path: "项目", name: "项目" })
  @sfdesk.favorite_remove(src, "ws1", "ws1/st1", fix_docs, "")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  @sfdesk.station_files_pick(src, "ws1/st1:s-c1")
  sheet_rested(t, "sf-present")
  assert_true(t.find("项目") is Some(_), msg="the saved folder is offered")
  assert_true(t.find("文档") is None, msg="a removed old shortcut is not offered again")
  t.tap_text("项目")
  t.draw()
  assert_true(t.find("说明.txt") is Some(_), msg="the saved folder opens")
}

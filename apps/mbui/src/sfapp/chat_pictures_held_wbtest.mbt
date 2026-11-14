// The pictures a chat's page has its host hold at its foot (fake_host.mbt's bytes handed over for decodes), made as
// nodes and by the old view: the page's list makes blocks by their estimate over the passes of one layout and lets some
// go in a later one, and a picture of a block let go so is never drawn; its decode is asked for by what draws it alone
// (View::image_ready asks for none), so a page made as nodes holds no picture the old page does not.

///|
/// The fixture's chat open on platform 1 in a window `w` × `h`, its size classes `width` ("" none said), the system
/// laying out the app's tabs where `nav_able`, its page made as nodes where `nodes`, at rest.
fn chat_pictures_open(w : Double, h : Double, width : String, nav_able : Bool, nodes : Bool) -> @ui.Tester {
  new_run()
  @sfbase.chat_page_nodes.set(nodes)
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=1, nav_able~)
  if width != "" {
    t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"\{width}\",\"height\":\"regular\"}}")
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat's page made as nodes holds at its foot no picture's bytes the old page does not: none for a block its list made and let go of in one layout" {
  for screen in [(820.0, 1180.0, "regular", false), (1024.0, 1366.0, "regular", false), (720.0, 840.0, "", true)] {
    let (w, h, width, nav_able) = screen
    let old = chat_pictures_open(w, h, width, nav_able, false).host_image_bytes_most()
    let made = chat_pictures_open(w, h, width, nav_able, true).host_image_bytes_most()
    assert_true(made <= old, msg="\{w}x\{h}: as nodes \{made} bytes, the old page \{old}")
  }
}


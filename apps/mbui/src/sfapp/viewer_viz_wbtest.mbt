// A picture's viewer and a visualization over the whole window, on a wide window, each opened its own way in (a picture
// tapped in its message, a visualization's 全屏 under its page): what is open over the other, and what back closes.

///|
/// A window tall enough for a chat's last messages to show a picture and a visualization's page at once.
let viz_chat_h : Double = 2400.0

///|
/// The picture both ways in are tried with.
let viz_chat_picture : String = "compare.png"

///|
/// A chat with a visualization and pictures in its messages, a wide window (1280 across, a Mac's, `viz_chat_h` tall), at
/// its end: the tester, where its picture is drawn and where the visualization's 全屏 is (each None: not on the screen).
fn viz_chat() -> (@ui.Tester, (Double, Double)?, (Double, Double)?) {
  new_run()
  let src = fixture("chat-viz")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=viz_chat_h, platform=0)
  nav_rested(t)
  t.run_for(@ui.move_most_ms)
  let picture = match t.locate("img:" + viz_chat_picture) {
    [p, ..] => Some(p)
    [] => None
  }
  // (the two 22 boxes under its page, at its right: the whole screen, then beside)
  let full = match view_rect(t, viz_views(t).0) {
    Some((x, y, w, h)) => Some((x + w - 22.0 - 2.0 - 11.0, y + h + 2.0 + 11.0))
    None => None
  }
  (t, picture, full)
}

///|
/// Both on the screen, else the test says so.
fn both_seen(picture : (Double, Double)?, full : (Double, Double)?) -> ((Double, Double), (Double, Double)) raise {
  match (picture, full) {
    (Some(p), Some(f)) => (p, f)
    _ => fail("not both on the screen: the picture \{picture}, the visualization's 全屏 \{full}")
  }
}

///|
/// Closed by back: whichever is open.
fn back_closes(t : @ui.Tester) -> Unit {
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  t.frame()
}

///|
/// The page under all of it as it stands: which, how deep.
fn page_now() -> (Page, Int) {
  (app.nav.top(), app.nav.depth())
}

///|
test "a wide window, a picture and a visualization's 全屏 both on the screen, each opening its own with nothing over it; a picture opened over all of it, the 全屏 under it opening nothing (the press the viewer's, as its contract says), back closing the picture, the page under it as it was" {
  let (t, picture, full) = viz_chat()
  let ((px, py), (fx, fy)) = both_seen(picture, full)
  let page = page_now()
  // (nothing over them: each opens its own)
  t.tap(fx, fy)
  t.frame()
  t.frame()
  assert_true(@sfbase.viz_full.get() is Some(_), msg="the 全屏 there opens the visualization")
  back_closes(t)
  assert_true(@sfbase.viz_full.get() is None, msg="closed again")
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get().map(fn(v) { v.in_tree }).unwrap_or(false), msg="the picture there opens the tree's viewer")
  // (back, nothing pressed between: the picture closed, the page as it was)
  back_closes(t)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="back: the picture closed")
  assert_true(page_now() == page, msg="back: the page as it was")
  // (opened again, the 全屏 where it was pressed under it)
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="opened again")
  t.tap(fx, fy)
  t.frame()
  t.frame()
  assert_true(@sfbase.viz_full.get() is None, msg="under the viewer: no visualization opened")
  let open = viewer.get().map(fn(v) { !v.closing }).unwrap_or(false)
  println("viewer over the 全屏: the press there left the viewer \{if open { "open" } else { "closing" }}")
  if open {
    // (the viewer's to keep: back closes it, the page as it was)
    back_closes(t)
    assert_true(viewer.get() is None && pv_leaving.get() is None, msg="back: the picture closed")
  } else {
    // (a click round the picture closes it, as the viewer's contract says: closed, nothing through it)
    t.run_for(@ui.move_most_ms)
    t.run_for(@sfpages.reveal_ms)
    assert_true(viewer.get() is None && pv_leaving.get() is None, msg="the click closed the picture")
  }
  assert_true(@sfbase.viz_full.get() is None, msg="nothing else opened")
  assert_true(page_now() == page, msg="the page as it was")
}

///|
test "a wide window, a picture and a visualization's 全屏 both on the screen; the visualization over the whole window, the picture under it opening nothing, back closing the visualization, the page under it as it was" {
  let (t, picture, full) = viz_chat()
  let ((px, py), (fx, fy)) = both_seen(picture, full)
  let page = page_now()
  // (nothing over it: the picture opens)
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="the picture there opens the viewer")
  back_closes(t)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed again")
  // (the visualization, back with nothing pressed between: closed, the page as it was)
  t.tap(fx, fy)
  t.frame()
  t.frame()
  assert_true(@sfbase.viz_full.get() is Some(_), msg="全屏: the visualization over the whole window")
  back_closes(t)
  assert_true(@sfbase.viz_full.get() is None, msg="back: the visualization closed")
  assert_true(page_now() == page, msg="back: the page as it was")
  // (opened again, the picture where it was pressed under it)
  t.tap(fx, fy)
  t.frame()
  t.frame()
  assert_true(@sfbase.viz_full.get() is Some(_), msg="opened again")
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None, msg="under the visualization: no picture opened")
  let open = @sfbase.viz_full.get() is Some(_)
  println("the visualization over the picture: the press there left it \{if open { "open" } else { "closed" }}")
  if open {
    back_closes(t)
    assert_true(@sfbase.viz_full.get() is None, msg="back: the visualization closed")
  }
  assert_true(viewer.get() is None, msg="nothing else opened")
  assert_true(page_now() == page, msg="the page as it was")
}

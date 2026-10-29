// The chats' list in the sidebar scrolls under its band (新建对话 and the filter): its scroll bar runs clear of the
// band, built every frame as a test does and kept as a host keeps its parts and rows.

///|
/// The sidebar's thumb, if one is drawn.
fn side_thumb(t : @ui.Tester) -> (Double, Double, Double, Double, Int64)? {
  t.drawn_rects().filter(fn(r) { r.0 < 400.0 && r.2 == @ui.scroll_bar_size && r.3 > @ui.scroll_bar_least }).get(0)
}

///|
/// The chats' list scrolled a little and back to its top, parts kept or not, `again` drawn again: the thumb's top and
/// the foot of 新建对话's words.
fn side_bar_run(keep : Bool, again : Bool) -> (Double, Double) {
  let t = wide_tester([], h=360.0)
  t.keep_parts(keep)
  t.drawn_again(again)
  t.draw()
  t.run_for(@ui.scrollbar_fade_ms)
  t.wheel(160.0, 250.0, 120.0)
  t.run_for(@ui.scrollbar_fade_ms)
  t.wheel(160.0, 250.0, -400.0)
  t.run_for(@ui.scrollbar_fade_ms)
  let thumb = side_thumb(t).unwrap()
  let (_, y, _, h) = t.rect_of("新建对话").unwrap()
  (thumb.1, y + h)
}

///|
test "the chats' list's scroll bar runs clear of 新建对话 over it, built every frame" {
  let (top, band) = side_bar_run(false, false)
  assert_true(top >= band, msg="thumb at \{top}, 新建对话 to \{band}")
}

///|
test "the chats' list's scroll bar runs clear of 新建对话 over it, parts kept as a host keeps them" {
  let (top, band) = side_bar_run(true, true)
  assert_true(top >= band, msg="thumb at \{top}, 新建对话 to \{band}")
}

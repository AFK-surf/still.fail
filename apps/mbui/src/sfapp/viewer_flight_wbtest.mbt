// What comes and goes as a chat's film opens out of its thumbnail and closes back into it: nothing on the
// screen changes in one frame (the user, 2026-10-31: 视频和图片展开收起有不少东西是瞬间变化的).

///|
/// Whether the words of the first text node holding `s` show at all in the last frame (a glyph of their line drawn,
/// not wholly see-through).
fn words_show(t : @ui.Tester, s : String) -> Bool {
  match t.find(s) {
    Some((x, y)) =>
      t.glyphs_shown().iter().any(fn(g) { g.1 <= y && y <= g.3 && (g.0 + g.2) / 2.0 > x - 150.0 && (g.0 + g.2) / 2.0 < x + 150.0 })
    None => false
  }
}

///|
test "a picture of the chat opened on a phone: drawn in each frame from the tap on, its thumbnail's place never left empty" {
  new_run()
  let src = fixture("chat-preview-named")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // (a phone's: a finger's tap, as a phone's host hands it on)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  nav_rested(t)
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let at = t.locate("img:compare.png")
  assert_true(at.length() > 0)
  let (x, y) = at[0]
  let big = fn() {
    t.drawn_images().iter().any(fn(i) { i[0] <= x && x <= i[0] + i[2] && i[1] <= y && y <= i[1] + i[3] && i[2] > 100.0 })
  }
  assert_true(big())
  // a finger's tap, then the display's frames one by one: in each, the picture there (its thumbnail, or flying out of
  // it), never a frame of nothing where it was
  t.touch(0, x, y)
  t.touch(2, x, y)
  let end = t.time() + @ui.move_most_ms
  let mut frames = 0
  while t.time() < end && frames < 8 {
    t.frame()
    assert_true(big())
    frames += 1
  }
  assert_true(viewer.get() is Some(_))
}

///|
test "a film flying in: its capsule goes with the still as it leaves its thumbnail; the player's bars come as it grows" {
  let t = video_in_chat(duration=72500.0)
  // its capsule's words (how long it is) over the thumbnail
  assert_true(words_show(t, "1:13"))
  let (bx, by) = t.find("1:13").unwrap()
  tap_video(t, "演示录屏.mp4")
  // set out: the capsule still there, going with the still
  assert_true(
    t.glyphs_shown().iter().any(fn(g) { g.1 <= by + 2.0 && by - 2.0 <= g.3 && g.0 < bx + 150.0 && g.2 > bx - 150.0 }),
  )
  // the chat still seen under its ground: the player's controls not yet over it (no words over words)
  assert_false(words_show(t, "0:00"))
  let v = viewer.get().unwrap()
  // nearly in, its ground whole: the player's controls coming with it (their clock showing), not after it lands
  let nearly = v.fly.end() - @ui.move_most_ms / 8.0
  t.run_for(nearly - t.time())
  assert_true(v.flies && v.flying() > @sfbase.bars_from)
  assert_true(words_show(t, "0:00"))
  t.run_for(@ui.move_most_ms)
  assert_true(words_show(t, "0:00"))
}

///|
test "a film closed back into its thumbnail: the player's bars go with it as it shrinks, not at once" {
  let t = video_in_chat(duration=72500.0)
  tap_video(t, "演示录屏.mp4")
  t.run_for(@ui.move_most_ms)
  t.set_player(1, position=4000.0)
  t.draw()
  t.back()
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"\{hex_bytes(fixture_file_png("演示录屏.mp4"))}\"}"))
  t.draw()
  let v = pv_leaving.get().unwrap()
  assert_true(v.flies && v.fly_back)
  // flying back: the controls still there, going as it shrinks
  t.frame()
  assert_true(words_show(t, "0:04"))
  // landed: gone, the thumbnail's capsule shown again
  t.run_for(@ui.move_most_ms)
  assert_true(pv_leaving.get() is None)
  assert_false(words_show(t, "0:04"))
  assert_true(words_show(t, "1:13"))
}

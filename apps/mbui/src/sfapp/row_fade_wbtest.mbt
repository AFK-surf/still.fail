// The real chat row's selected ground after its page is left.

///|
fn fading_chat_row(on : Ref[Bool], builds : Ref[Int], opened : Ref[Int], shown? : Ref[Bool] = Ref(true)) -> @ui.Tester {
  new_run()
  let src = fixture("home")
  let item = chat_item({
    "id": "fade-row",
    "station": "ws1/st1",
    "session": "s-c1",
    "title": "Fade row",
    "people": [
      { "id": "lin", "shown": { "name": "Lin", "display": "Lin", "mine": false } },
      { "id": "mo", "shown": { "name": "Mo", "display": "Mo", "mine": false } },
    ],
  })
  let t = @ui.Tester::new(fn(c) {
    builds.val += 1
    @sf.begin(c) |> ignore
    if shown.val {
      @sfpages.chat_row(
        c,
        src,
        item,
        "people",
        on=on.val,
        list_ground=0x123456FFL,
        opened=fn(_) { opened.val += 1 },
      )
      |> ignore
    }
  }, w=390.0, h=200.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.draw()
  t
}

///|
fn fade_row_ground(t : @ui.Tester) -> Int64 {
  let ink = @sf.theme().p.selected & 0xFFFFFF00L
  let rects = t.drawn_rects().filter(fn(r) {
    r.2 == 390.0 && r.3 == @sfpages.touch_row_h && (r.4 & 0xFFFFFF00L) == ink
  })
  if rects.is_empty() { 0L } else { rects[0].4 }
}

///|
fn fade_row_rect(t : @ui.Tester) -> (Double, Double, Double, Double) {
  let rows = t.boxes().filter(fn(b) { b.hit && b.w == 390.0 && b.h == @sfpages.touch_row_h })
  if rows.is_empty() { (-1.0, -1.0, -1.0, -1.0) } else { (rows[0].x, rows[0].y, rows[0].w, rows[0].h) }
}

///|
fn fade_rings(t : @ui.Tester, ground : Int64) -> Int {
  t.drawn_rects().filter(fn(r) { r.2 == 20.0 && r.3 == 20.0 && r.4 == ground }).length()
}

///|
test "a real chat row's selected ground fades without rebuilding or laying out its contents" {
  let on = Ref(true)
  let builds = Ref(0)
  let opened = Ref(0)
  let t = fading_chat_row(on, builds, opened)
  let initial = fade_row_ground(t)
  assert_eq(initial, @sf.theme().p.selected)
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms + @sfpages.left_fade_ms / 4.0)
  // A host frame, with the Tester's retained-versus-whole comparison still on.
  t.frame_at(t.time() + t.frame_period())
  assert_true(t.painted_why().contains("the clock read as it was painted"), msg=t.painted_why())
  let first = fade_row_ground(t)
  // Count only the host's work, not the Tester's extra whole build used to check the retained result.
  t.check_looks(false)
  let before = builds.val
  t.run_for(@sfpages.left_fade_ms / 4.0)
  let middle = fade_row_ground(t)
  let p = t.frame_perf()
  t.check_looks(true)
  assert_true(first != initial && middle != first && middle != 0L, msg="\{initial} -> \{first} -> \{middle}")
  assert_eq(builds.val - before, 1, msg="only the test's first frame builds; got \{builds.val - before}")
  assert_eq((p.passes, p.laid), (0, 0), msg="the last fade frame only paints")
}

///|
test "a chat row keeps its colour, face rings, geometry and press as its selected ground fades" {
  let on = Ref(true)
  let builds = Ref(0)
  let opened = Ref(0)
  let t = fading_chat_row(on, builds, opened)
  let initial = fade_row_ground(t)
  let rect = fade_row_rect(t)
  assert_eq((rect.2, rect.3), (390.0, @sfpages.touch_row_h))
  assert_eq(fade_rings(t, @sf.over(0x123456FFL, initial)), 2)
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms / 2.0)
  assert_eq(fade_row_ground(t), initial)
  t.run_for(@sfpages.left_lit_ms / 2.0 + @sfpages.left_fade_ms / 2.0)
  let end = t.rest_of("row-lit/")
  assert_true(end > t.time(), msg="the fade is under way")
  let at = t.time() - (end - @sfpages.left_fade_ms)
  let fraction = @motion.tween(@sfpages.left_fade_ms, ease=Leave).value_at(at, @sfpages.left_fade_ms, 1.0, 0.0, 0.0).0
  let ground = @sf.alpha(initial, fraction)
  assert_eq(fade_row_ground(t), ground)
  assert_eq(fade_rings(t, @sf.over(0x123456FFL, ground)), 2)
  assert_eq(fade_row_rect(t), rect)
  let (x, y) = t.find("Fade row").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.tap_indication_ms)
  let pressed = @sf.alpha(@sf.theme().p.text, 0.05)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.2 == rect.2 && r.3 == rect.3 && r.4 == pressed }))
  assert_eq(fade_rings(t, @sf.over(0x123456FFL, pressed)), 2)
  t.release(x, y)
  assert_eq(opened.val, 1)
  t.run_for(@sfpages.left_fade_ms)
  assert_eq(fade_row_ground(t), 0L)
  assert_eq(fade_rings(t, 0x123456FFL), 2)
  assert_eq(fade_row_rect(t), rect)
}

///|
test "a chat row selected again cancels its old fade, and a later return starts its own" {
  let on = Ref(true)
  let t = fading_chat_row(on, Ref(0), Ref(0))
  let initial = fade_row_ground(t)
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms + @sfpages.left_fade_ms / 2.0)
  assert_true(fade_row_ground(t) != initial)
  on.val = true
  t.draw()
  t.run_for(@sfpages.left_fade_ms)
  assert_eq(fade_row_ground(t), initial)
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms / 2.0)
  assert_eq(fade_row_ground(t), initial)
  t.run_for(@sfpages.left_lit_ms / 2.0 + @sfpages.left_fade_ms)
  assert_eq(fade_row_ground(t), 0L)
}

///|
test "a chat row's fade respects reduced motion" {
  let on = Ref(true)
  let t = fading_chat_row(on, Ref(0), Ref(0))
  t.set_reduce_motion(true)
  t.draw()
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms + t.frame_period())
  assert_eq(fade_row_ground(t), 0L)
  assert_eq(t.rest_of("row-lit/"), -1.0)
}

///|
test "reducing motion during a chat row's fade puts it at its end" {
  let on = Ref(true)
  let t = fading_chat_row(on, Ref(0), Ref(0))
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms + @sfpages.left_fade_ms / 2.0)
  assert_true(fade_row_ground(t) != 0L)
  t.set_reduce_motion(true)
  t.draw()
  assert_eq(fade_row_ground(t), 0L)
  assert_eq(t.rest_of("row-lit/"), -1.0)
}

///|
test "a removed chat row does not leave the hold's wake behind" {
  let on = Ref(true)
  let shown = Ref(true)
  let t = fading_chat_row(on, Ref(0), Ref(0), shown~)
  on.val = false
  t.draw()
  assert_true(t.wanted_after() < @double.infinity)
  shown.val = false
  t.draw()
  assert_eq(t.wanted_after(), @double.infinity)
}

///|
test "a removed chat row is not built when its old fade would have ended" {
  let on = Ref(true)
  let shown = Ref(true)
  let t = fading_chat_row(on, Ref(0), Ref(0), shown~)
  on.val = false
  t.draw()
  t.run_for(@sfpages.left_lit_ms + @sfpages.left_fade_ms / 4.0)
  let end = t.rest_of("row-lit/")
  assert_true(end > t.time())
  shown.val = false
  t.draw()
  // Removing the row changes layout; the host's following frame accounts for that before the old end comes.
  t.frame_at(t.time() + t.frame_period())
  assert_eq(t.built_why(), "the one before it laid out otherwise")
  t.frame_at(end)
  assert_eq(t.built_why(), "")
  assert_eq(t.wanted_after(), @double.infinity)
}

// An activity's first words arrive like a message; a later step changes each glyph into the next one's at its place.

///|
let activity_next_words : String = "正在核对动效和测试结果"

///|
/// Visible glyphs in the line of these words (which may itself be moving into the activity's window).
fn activity_glyphs_shown(t : @ui.Tester, words : String) -> Int {
  let line = t.words().iter().find_first(fn(w) { w.0 == words })
  guard line is Some((_, x, y, w, h, _)) else { return 0 }
  t.glyphs_shown().filter(fn(g) {
    let mid_y = (g.1 + g.3) / 2.0
    g.0 >= x - 1.0 && g.0 < x + w && mid_y >= y && mid_y < y + h
  }).length()
}

///|
/// The ink alpha of glyphs on this line, including their individual looks as they are drawn.
fn activity_glyph_alphas(t : @ui.Tester, words : String) -> Array[Int64] {
  let line = t.words().iter().find_first(fn(w) { w.0 == words })
  guard line is Some((_, x, y, w, h, _)) else { return [] }
  t.drawn_glyphs()
  .filter(fn(g) { g.0 >= x - 1.0 && g.0 < x + w && g.1 >= y && g.1 < y + h })
  .map(fn(g) { g.2 & 0xFFL })
}

///|
test "activity: the first words of a newly seen turn arrive a glyph at a time" {
  let t = linger_core()
  t.run_for(fix_deliver_ms)
  let at = turns_of("ws1/st1\u{1}s-c1").start_of("act:s-c1")
  assert_true(at >= 0.0 && at < @double.infinity, msg="\{at}")
  t.run_for(dmax(at - t.time(), 0.0) + @sfbase.glyph_line_in_ms / 2.0)
  let alphas = activity_glyph_alphas(t, tr("android-chat.chat.working"))
  assert_true(alphas.length() > 1 && alphas.iter().any(fn(a) { a != alphas[0] }), msg="\{alphas}")
  t.run_for(@ui.move_most_ms + @sfbase.glyph_line_in_ms)
  let alphas = activity_glyph_alphas(t, tr("android-chat.chat.working"))
  assert_true(alphas.length() > 1 && alphas.iter().all(fn(a) { a == alphas[0] }), msg="\{alphas}")
}

///|
test "activity: a row reserved for later reveals its words in its own turn" {
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  // The row itself follows the flight's landing; the chat's turn and the row's reserved time are distinct.
  let at = reading_of("ws1/st1\u{1}s-c1").rows.came("act:s-c1").unwrap()
  assert_true(at > t.time(), msg="its turn is reserved for later: \{at}, now \{t.time()}")
  let words = tr("android-chat.chat.working")
  assert_eq(activity_glyphs_shown(t, words), 0)
  t.run_for(at - t.time() + @ui.move_most_ms + @sfbase.glyph_line_in_ms)
  assert_true(activity_glyphs_shown(t, words) > 0, msg="the activity's words come in during its turn")
  emit_restore()
}

///|
test "activity: each glyph fades before its successor rises in" {
  for step in 0..=8 {
    let ms = @sfbase.glyph_change_in_ms * step.to_double() / 8.0
    for i in 0..<12 {
      let turn = @sfbase.glyph_change_line_ms * i.to_double() / 11.0
      let old = @sfbase.glyph_change(ms, turn, i, 37, false)
      let next = @sfbase.glyph_change(ms, turn, i, 37, true)
      assert_true(old.alpha == 0.0 || next.alpha == 0.0, msg="\{ms} \{i}")
      assert_true(old.scale == 1.0 && next.scale == 1.0, msg="\{ms} \{i}")
    }
  }
  assert_true(@sfbase.glyph_change(0.0, 0.0, 0, 37, false).alpha == 1.0)
  let entering = @sfbase.glyph_change(@sfbase.glyph_change_in_ms / 2.0, 0.0, 0, 37, true)
  assert_true(entering.alpha > 0.0 && entering.alpha < 1.0 && entering.dy > 0.0)
  let done = @sfbase.glyph_change(@sfbase.glyph_change_in_ms, @sfbase.glyph_change_line_ms, 11, 37, true)
  assert_true(done.alpha == 1.0 && done.dy == 0.0)
}

///|
test "activity: the individual changes have local variation" {
  let mut out_of_order = false
  for step in 0..=64 {
    let ms = @sfbase.glyph_change_in_ms * step.to_double() / 64.0
    for i in 0..<12 {
      let turn = @sfbase.glyph_change_line_ms * i.to_double() / 15.0
      let next_turn = @sfbase.glyph_change_line_ms * (i + 3).to_double() / 15.0
      let here = @sfbase.glyph_change(ms, turn, i, 37, true)
      let next = @sfbase.glyph_change(ms, next_turn, i + 3, 37, true)
      if next.alpha > here.alpha { out_of_order = true }
    }
  }
  assert_true(out_of_order, msg="later glyphs can change before earlier ones")
}

///|
test "activity: a step changes glyphs individually before the next step is whole" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_due.push(fn() { @sffixture.fix_working_now.val = ("call:2", activity_next_words) })
  @settings.fixture_changed()
  t.draw()
  // The next step is first held long enough to exclude one that vanishes during its own arrival.
  t.run_for(@sfbase.glyph_change_in_ms + @sfbase.glyph_change_in_ms / 2.0)
  let alphas = activity_glyph_alphas(t, activity_next_words)
  assert_true(alphas.length() > 1 && alphas.iter().any(fn(a) { a != alphas[0] }), msg="\{alphas}")
  t.run_for(@ui.move_most_ms + @sfbase.glyph_change_in_ms)
  let final_alphas = activity_glyph_alphas(t, activity_next_words)
  assert_true(final_alphas.length() > 1 && final_alphas.iter().all(fn(a) { a == final_alphas[0] }), msg="\{final_alphas}")
}

///|
fn activity_glyphs_do_not_collide(before : String, next : String) -> Unit raise {
  let src = fixture_app("chat-working")
  @sffixture.fix_working_now.val = ("call:1", before)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_due.push(fn() { @sffixture.fix_working_now.val = ("call:2", next) })
  @settings.fixture_changed()
  t.draw()
  t.run_for(@sfbase.glyph_change_in_ms)
  for _ in 0..<6 {
    t.run_for(@sfbase.glyph_change_in_ms / 6.0)
    let line = t.words().iter().find_first(fn(w) { w.0 == next })
    guard line is Some((_, x, y, w, h, _)) else { fail("the next step is in the line: \{before} → \{next}, at \{t.time()}") }
    // The old line may extend beyond the next one's box while its last glyphs are fading away.
    let right = match t.words().iter().find_first(fn(w) { w.0 == before }) {
      Some((_, old_x, _, old_w, _, _)) => dmax(x + w, old_x + old_w)
      None => x + w
    }
    let glyphs = t.glyphs_shown().filter(fn(g) {
      let mid_y = (g.1 + g.3) / 2.0
      g.0 >= x - 1.0 && g.0 < right && mid_y >= y && mid_y < y + h
    })
    assert_true(glyphs.length() > 0, msg="the line stays visible")
    for i in 0..<glyphs.length() {
      for j in (i + 1)..<glyphs.length() {
        let a = glyphs[i]
        let b = glyphs[j]
        assert_true(a.2 <= b.0 + 0.01 || b.2 <= a.0 + 0.01 || a.3 <= b.1 + 0.01 || b.3 <= a.1 + 0.01, msg="\{before} → \{next} at \{t.time()}: \{a} / \{b}")
      }
    }
  }
}

///|
test "activity: glyphs do not collide when their widths change" {
  activity_glyphs_do_not_collide("iiiiiiiiiiii", "宽宽宽宽宽宽宽宽宽宽宽宽")
  activity_glyphs_do_not_collide("宽宽宽宽宽宽宽宽宽宽宽宽", "iiiiiiiiiiii")
  activity_glyphs_do_not_collide("iiiiiiiiiiii", "宽宽宽宽宽宽")
  activity_glyphs_do_not_collide("宽宽宽宽宽宽", "iiiiiiiiiiii")
  activity_glyphs_do_not_collide("在 Studio 上跑整套检查", "正在核对动效和测试结果")
  activity_glyphs_do_not_collide("在 Studio 上跑整套检查：先编译 mbui 的原生代码", "正在核对动效和测试结果")
}

///|
test "activity: changing the words of the same step keeps them whole" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_due.push(fn() { @sffixture.fix_working_now.val = ("call:1", activity_next_words) })
  @settings.fixture_changed()
  t.draw()
  t.run_for(@sfbase.glyph_line_ms / 2.0)
  let now = activity_glyphs_shown(t, activity_next_words)
  t.run_for(@sfbase.glyph_line_in_ms)
  let later = activity_glyphs_shown(t, activity_next_words)
  assert_true(now > 0 && now == later, msg="\{now} then \{later} glyphs")
}

///|
test "activity: reduced motion shows the new step at once" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  t.set_reduce_motion(true)
  @sffixture.fix_due.push(fn() { @sffixture.fix_working_now.val = ("call:2", activity_next_words) })
  @settings.fixture_changed()
  t.draw()
  t.run_for(@sfbase.glyph_change_in_ms + @sfbase.glyph_line_ms / 2.0)
  let now = activity_glyphs_shown(t, activity_next_words)
  t.run_for(@sfbase.glyph_line_in_ms)
  let later = activity_glyphs_shown(t, activity_next_words)
  assert_true(now > 0 && now == later, msg="\{now} then \{later} glyphs")
  t.set_reduce_motion(false)
}

// An agent's step rolling to its next where its line has less room than either says (steady_words): the line no
// wider as it rolls than at rest, each step's words cut where the line ends, as at rest, the clock beside them in
// sight. Rolling, the line once took each step's whole width, far past the screen's edge (2026-10-29 用户：
// 「activity 滚动的时候会超长」).

///|
/// The step the chat-working agent goes on to, as long as the one it was on.
let next_step : String = "再在 Studio 上把三种宽度下的截图逐张拼成对比图，标出每处和上一版不一样的地方，发到对话里给人看"

///|
/// The words drawn on the line of `step`'s words that reach past `right` (their words, where they end).
fn past_edge(t : @ui.Tester, step : String, right : Double) -> Array[(String, Double)] {
  let (_, y, _, h) = t.rect_of(step).unwrap()
  t
  .words()
  .filter(fn(w) { w.2 + w.4 > y && w.2 < y + h && w.1 + w.3 > right + 0.5 })
  .map(fn(w) { (w.0, w.1 + w.3) })
}

///|
test "activity: rolling from one long step to the next, its line no wider than at rest" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  assert_eq(past_edge(t, @sffixture.working_step, 360.0), [])
  @sffixture.fix_later(1.0, fn() { @sffixture.fix_working_now.val = ("call:2", next_step) })
  // a quarter of the shortest a roll can take at a time (a Move of nothing far), three of them, and at its end
  for i in 1..<4 {
    t.run_for(@ui.move_least_ms / 4.0)
    assert_true(t.rect_of(@sffixture.working_step) is Some(_), msg="\{i}/4: the step it was on still rolling out")
    assert_eq(past_edge(t, @sffixture.working_step, 360.0), [], msg="\{i}/4")
    assert_eq(past_edge(t, next_step, 360.0), [], msg="\{i}/4")
  }
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of(@sffixture.working_step) is None)
  assert_eq(past_edge(t, next_step, 360.0), [])
}

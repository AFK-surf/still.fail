// A job's sheet on 小屏 (open_job: what it holds nodes, job_node): each of its words where the host's sheet of its old
// body drew them (recorded from that body, apps/mbui/src/sfapp/sheets.mbt's job_detail before it was made nodes, on the
// same made-up job: chat-job's 盯 CI), its 输出 pressed where it is drawn: its output where the old one's was, the
// choice's thumb gone to it; 停止 pressing it asks the core to stop it.

///|
/// The words in the job's sheet (its lower share), each where it is drawn (to half a point) and how big: those drawn
/// there but the chat's under it (`chat`: what is drawn there with no sheet).
fn job_words_seen(seen : Array[(String, Double, Double, Double, Double)], chat : Array[(String, Double, Double, Double, Double)]) -> Array[(String, Double, Double, Double, Double)] {
  seen.filter(fn(w) { !chat.contains(w) })
}

///|
/// What the old body's sheet showed of 盯 CI as it opened, what it said (its words, where each was and how big, to half a
/// point).
// kept across runs: a value (no field of it changes)
let job_said_was : Array[(String, Double, Double, Double, Double)] = [
  ("盯 CI", 44.0, 198.0, 346.0, 22.5),
  ("在盯着 · 第 3 步通过", 44.0, 220.0, 346.0, 17.5),
  ("gh run watch 4821 --exit-status", 24.0, 251.5, 342.0, 17.0),
  ("通知", 96.5, 290.0, 28.0, 19.5),
  ("输出", 265.5, 290.0, 28.0, 19.5),
  ("14:05", 24.0, 331.0, 48.0, 18.0),
  ("第 3 步通过：单元测试全部通过", 82.0, 331.0, 284.0, 21.0),
  ("13:58", 24.0, 364.0, 48.0, 18.0),
  ("开始跑：构建、测试、截图", 82.0, 364.0, 284.0, 21.0),
  ("最后输出 · 3 分钟前", 24.0, 399.0, 342.0, 17.0),
  ("… waiting for deploy", 24.0, 417.5, 342.0, 17.0),
  ("停止", 191.0, 461.0, 30.0, 21.0),
]

///|
/// The same once 输出 was pressed: its output.
// kept across runs: a value (no field of it changes)
let job_output_was : Array[(String, Double, Double, Double, Double)] = [
  ("盯 CI", 44.0, 198.0, 346.0, 22.5),
  ("在盯着 · 第 3 步通过", 44.0, 220.0, 346.0, 17.5),
  ("gh run watch 4821 --exit-status", 24.0, 251.5, 342.0, 17.0),
  ("通知", 96.5, 290.0, 28.0, 19.5),
  ("输出", 265.5, 290.0, 28.0, 19.5),
  ("✓ build (1m 12s)", 38.0, 343.0, 314.0, 17.0),
  ("✓ unit tests (48s)", 38.0, 360.0, 314.0, 17.0),
  ("✓ step 3: screenshots", 38.0, 377.5, 314.0, 17.0),
  ("… waiting for deploy", 38.0, 394.5, 314.0, 17.0),
  ("停止", 191.0, 762.5, 30.0, 21.0),
]

///|
/// The old sheet's output's box (its ground, the ink at 5%: where it was and how big) and the choice's thumb under 输出.
let job_output_box_was : (Double, Double, Double, Double) = (24.0, 331.0, 342.0, 405.0)

///|
let job_thumb_was : (Double, Double, Double, Double) = (195.0, 285.0, 169.0, 30.0)

///|
/// Where a box of `ink` is drawn in the sheet (to half a point), those there are.
fn job_rects_of(t : @ui.Tester, ink : Int64) -> Array[(Double, Double, Double, Double)] {
  let half = fn(x : Double) { (x * 2.0).round() / 2.0 }
  t.drawn_rects().filter(fn(r) { r.4 == ink && r.1 >= 844.0 * (1.0 - sheet_share) }).map(fn(r) { (half(r.0), half(r.1), half(r.2), half(r.3)) })
}

///|
test "小屏: a job's sheet whose body is nodes: each of its words where the old body's were; 输出 pressed where it is drawn: its output where the old one's was, the thumb on it" {
  let t = screen_played("chat-job", @ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let said = words_below(t, sheet_share)
  t.tap_text("输出")
  t.run_for(@ui.move_most_ms)
  let output = words_below(t, sheet_share)
  let ground = @sf.alpha(@sf.theme().p.text, job_output_ink)
  assert_true(job_rects_of(t, ground).contains(job_output_box_was), msg="its output's ground")
  assert_true(job_rects_of(t, 0xFFFFFFFFL).contains(job_thumb_was), msg="the thumb under 输出")
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
  let chat = words_below(t, sheet_share)
  assert_eq(job_words_seen(said, chat), job_said_was)
  assert_eq(job_words_seen(output, chat), job_output_was)
}

///|
test "小屏: a job's sheet whose body is nodes: 停止 asks the core to stop it" {
  let t = screen_played("chat-job", @ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let felt = t.haptics().length()
  t.tap_text("停止")
  t.run_for(@ui.move_most_ms)
  // (asked: felt as it is pressed, act's)
  assert_eq(t.haptics().length(), felt + 1, msg="asked")
}

///|
/// The lines of the job's output drawn whole in its box (the old one's, job_output_box_was), in their order: its
/// made-up four and those come after (`deploy check N`), not the chat's under the sheet.
fn job_lines_drawn(t : @ui.Tester) -> Array[String] {
  let (_, y, _, h) = job_output_box_was
  let first = ["✓ build (1m 12s)", "✓ unit tests (48s)", "✓ step 3: screenshots", "… waiting for deploy"]
  let lines = t
    .words()
    .filter(fn(w) {
      (w.0.has_prefix("deploy check ") || first.contains(w.0)) && w.5 > 0.0 && w.2 >= y && w.2 + w.4 <= y + h
    })
  lines.sort_by(fn(a, b) { a.2.compare(b.2) })
  lines.map(fn(w) { w.0 })
}

///|
/// Lines a running job's output comes to have at once, more than its box shows; and a few more after (the test's).
let job_lines_come : Int = 40

///|
let job_lines_more : Int = 5

///|
/// How far the wheel scrolls the output back towards its first lines (points; on, the other way).
let job_wheel_back : Double = -300.0

///|
/// How far on it is scrolled to be at its end again, past it (points).
let job_wheel_end : Double = 6000.0

///|
test "小屏: a job's output as nodes follows its end as the old one's did (Ctx::list's stick_end): made at its end, kept there as lines come; scrolled back off it, left where it was as more come; scrolled to its end again, followed again" {
  let t = screen_played("chat-job", @ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  t.tap_text("输出")
  t.run_for(@ui.move_most_ms)
  // (at its end as it opened, its four lines all there: more come than its box shows, kept at its end)
  @sffixture.fix_now(fn() { @sffixture.fix_job_more.val += job_lines_come })
  t.run_for(@ui.move_most_ms)
  let newest = "deploy check \{job_lines_come}"
  assert_eq(job_lines_drawn(t).last(), Some(newest), msg="followed to its newest: \{job_lines_drawn(t)}")
  // (its box as the old one's, however many lines it holds: never pushed past the sheet)
  let ground = @sf.alpha(@sf.theme().p.text, job_output_ink)
  assert_true(job_rects_of(t, ground).contains(job_output_box_was), msg="its output's ground: \{job_rects_of(t, ground)}")
  assert_false(job_lines_drawn(t).contains("✓ build (1m 12s)"), msg="its first gone up")
  // (scrolled back off its end: more come, left where it was)
  let (x, y, w, h) = job_output_box_was
  t.wheel(x + w / 2.0, y + h / 2.0, job_wheel_back)
  t.run_for(@ui.move_most_ms)
  let seen = job_lines_drawn(t)
  assert_false(seen.contains(newest), msg="scrolled off its end: \{seen}")
  @sffixture.fix_now(fn() { @sffixture.fix_job_more.val += job_lines_more })
  t.run_for(@ui.move_most_ms)
  assert_eq(job_lines_drawn(t), seen, msg="left where it was")
  // (scrolled to its end again: followed again)
  t.wheel(x + w / 2.0, y + h / 2.0, job_wheel_end)
  t.run_for(@ui.move_most_ms)
  @sffixture.fix_now(fn() { @sffixture.fix_job_more.val += job_lines_more })
  t.run_for(@ui.move_most_ms)
  let last = "deploy check \{job_lines_come + job_lines_more * 2}"
  assert_eq(job_lines_drawn(t).last(), Some(last), msg="followed again: \{job_lines_drawn(t)}")
}

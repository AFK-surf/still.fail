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
  assert_eq(job_lines_drawn(t).last(), Some(newest), msg="followed to its newest: \{Repr(job_lines_drawn(t))}")
  // (its box as the old one's, however many lines it holds: never pushed past the sheet)
  let ground = @sf.alpha(@sf.theme().p.text, job_output_ink)
  assert_true(job_rects_of(t, ground).contains(job_output_box_was), msg="its output's ground: \{Repr(job_rects_of(t, ground))}")
  assert_false(job_lines_drawn(t).contains("✓ build (1m 12s)"), msg="its first gone up")
  // (scrolled back off its end: more come, left where it was)
  let (x, y, w, h) = job_output_box_was
  t.wheel(x + w / 2.0, y + h / 2.0, job_wheel_back)
  t.run_for(@ui.move_most_ms)
  let seen = job_lines_drawn(t)
  assert_false(seen.contains(newest), msg="scrolled off its end: \{Repr(seen)}")
  @sffixture.fix_now(fn() { @sffixture.fix_job_more.val += job_lines_more })
  t.run_for(@ui.move_most_ms)
  assert_eq(job_lines_drawn(t), seen, msg="left where it was")
  // (scrolled to its end again: followed again)
  t.wheel(x + w / 2.0, y + h / 2.0, job_wheel_end)
  t.run_for(@ui.move_most_ms)
  @sffixture.fix_now(fn() { @sffixture.fix_job_more.val += job_lines_more })
  t.run_for(@ui.move_most_ms)
  let last = "deploy check \{job_lines_come + job_lines_more * 2}"
  assert_eq(job_lines_drawn(t).last(), Some(last), msg="followed again: \{Repr(job_lines_drawn(t))}")
}

///|
/// A line of a running test runner's output as the core's `jobLog` gives it (its number `k`, its runs): its time dim,
/// its mark green, its words.
fn job_long_line(k : Int) -> Json {
  let mark : Json = if k % 17 == 5 { { "text": " ↻ ", "fg": "3" } } else { { "text": " ✔ ", "fg": "2" } }
  {
    "n": Json::number(k.to_double()),
    "runs": [
      { "text": Json::string("12:\{k / 60 % 60}:\{k % 60}"), "dim": true },
      mark,
      { "text": Json::string("src/views/chat-tabs.test.ts › keeps its place \{k}") },
    ],
  }
}

///|
/// The words of the line numbered `k` as drawn (job_long_line's).
fn job_long_words(k : Int) -> String {
  let mark = if k % 17 == 5 { " ↻ " } else { " ✔ " }
  "12:\{k / 60 % 60}:\{k % 60}" + mark + "src/views/chat-tabs.test.ts › keeps its place \{k}"
}

///|
/// How many lines its output asks (sheets.mbt job_output_most), and how many it opens with: one short of them, so the
/// first to come comes under them and the next at them.
let job_long_most : Int = 300

///|
/// A job's sheet on 小屏 (chat-job's 盯 CI) whose output is `log` as the core client holds it (`lines` of 300 asked:
/// what the station says, the client's keyed ops applied, the lines they do not touch the same JSON), the rest the
/// fixture's; its 输出 pressed, at its end.
fn job_long_sheet(log : @signals.Signal[Json]) -> @ui.Tester {
  new_run()
  let base = @sffixture.fixture("chat-job")
  // (its version: one more each time it is another value)
  let version = Ref(0)
  let seen : Ref[Json?] = Ref(None)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "jobLog" && params.get("lines") == Some(Json::number(job_long_most.to_double())) {
        let value = log.get()
        if !(seen.val is Some(v) && physical_equal(v, value)) {
          seen.val = Some(value)
          version.val += 1
        }
        return { value: Some(value), error: None, version: version.val }
      }
      base.topic(name, params).get().snapshot()
    },
  }
  open_fixture_over("chat-job", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("输出")
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What the window's tree made, let go of and measured in the frame drawn after `come` (a frame's work: the first
/// frame drawn once it is said), then the rest of the way at rest.
fn job_frame_after(t : @ui.Tester, come : () -> Unit) -> @ui.TreeFrame {
  t.tree_frames_from_now()
  come()
  t.frame()
  let f = t.tree_frames()
  t.run_for(@ui.move_most_ms)
  f[0]
}

///|
/// Whether the output's list stands at its end (the tallest list shown), and the last of its lines drawn whole.
fn job_long_end(t : @ui.Tester) -> (Bool, String) {
  let tree = @ui.view_tree().unwrap()
  let mut best : (Double, Double, Double, Double)? = None
  for l in tree.lists_reckoned() {
    if l.1 > 0.0 && (best is None || l.0 > best.unwrap().0) {
      best = Some(l)
    }
  }
  let at_end = match best {
    Some((h, vh, at, _)) => at >= h - vh - 0.5
    None => false
  }
  let (_, y, _, h) = job_output_box_was
  let lines = t.words().filter(fn(w) { w.0.has_prefix("12:") && w.5 > 0.0 && w.2 >= y && w.2 + w.4 <= y + h })
  lines.sort_by(fn(a, b) { a.2.compare(b.2) })
  (at_end, lines.last().map_or("", fn(w) { w.0 }))
}

///|
test "小屏: a job's output of 300 coloured lines: in the frame a line comes, what is made is that line's row alone (one line came, one row made; two, two), and its end is followed" {
  let lines = Array::makei(job_long_most - 1, fn(k) { job_long_line(k) })
  let log = @signals.signal(
    ({ "lines": Json::array(lines), "said": "最后输出 · 刚刚", "last": "x" } : Json),
    same=fn(a, b) { physical_equal(a, b) },
  )
  let t = job_long_sheet(log)
  assert_eq(job_long_end(t), (true, job_long_words(job_long_most - 2)), msg="opened at its end")
  let next = Ref(job_long_most - 1)
  let first = Ref(0)
  // (the core's keyed ops for `come` lines more, the first gone past its 300: as the core client applies them)
  let more = fn(come : Int) {
    let ops : Array[Json] = []
    for _ in 0..<come {
      if next.val - first.val >= job_long_most {
        ops.push({ "path": ["lines"], "key": ["n"], "drop": Json::number(first.val.to_double()) })
        first.val += 1
      }
      ops.push({ "path": ["lines"], "key": ["n"], "put": job_long_line(next.val), "before": Json::null() })
      next.val += 1
    }
    log.set(@core.apply_delta(log.get(), ops))
  }
  // A line more under its 300, then one at them (the first gone), then two at once.
  let one = job_frame_after(t, fn() { more(1) })
  assert_eq(job_long_end(t), (true, job_long_words(next.val - 1)), msg="followed to the line come")
  let capped = job_frame_after(t, fn() { more(1) })
  assert_eq(job_long_end(t), (true, job_long_words(next.val - 1)), msg="at its 300, followed to the line come")
  let two = job_frame_after(t, fn() { more(2) })
  assert_eq(job_long_end(t), (true, job_long_words(next.val - 1)), msg="two come, followed to the last")
  println("a line more: \{Repr(one)}; at its 300: \{Repr(capped)}; two at once: \{Repr(two)}")
  // One line came, one row made, its words alone measured; as many again for each line more come at once, whatever
  // rows show.
  assert_true(one.made > 0, msg="the line come made: \{Repr(one)}")
  assert_eq(one.measured, 1, msg="the line come's words alone measured: \{Repr(one)}")
  assert_eq((capped.made, capped.measured), (one.made, one.measured), msg="at its 300 as under them: \{Repr(capped)} \{Repr(one)}")
  assert_eq((two.made, two.measured), (2 * one.made, 2 * one.measured), msg="two come: twice one's: \{Repr(two)} \{Repr(one)}")
}

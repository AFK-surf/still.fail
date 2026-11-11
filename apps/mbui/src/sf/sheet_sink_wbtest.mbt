// A sheet's rise and sink while what it holds grows or shrinks (SheetRise): each way said once at its cause's moment,
// from where its top stood then and as fast as it went (View::grows_now), only its end following how tall it comes to.
// Judged frame by frame on the display's frames (sizes_steady: a place stopped dead, a step half way), the default
// run's alone (@ui.test_at_a_rate).

///|
/// What a sink_sheet holds besides its lines, how much more while `tall`, and how far into that changing the next
/// cause comes: a sheet some 280 tall growing or shrinking by 160, two frames in (as 新建 workspace's invite code's
/// field opens); some 400 by 200, three frames in, its own Move's length (move_ms, to whole frames) another as it
/// does (as 添加 station's body changes, 427 to 276).
let sink_cases : Array[(Double, Double, Double)] = [
  (0.0, 160.0, 2.0 * 1000.0 / 60.0),
  (80.0, 200.0, 3.0 * 1000.0 / 60.0),
]

///|
/// A phone's sheet holding a line, a block `body` tall, `more` more while `tall`, and a line; opened and come to rest
/// unless `rest` is false (its rise under way as it is given back).
fn sink_sheet(tall : @signals.Signal[Bool], body : Double, more : Double, rest? : Bool = true) -> @ui.Tester {
  let t = presenting_tester(phone, fn(_) {
    panel_nodes("沉", from=Unanchored, fn(v, _) {
      words_node(v, fn() { "第一行" }, fn() { paragraph }) |> ignore
      v.box(fn(b) { b.height(Is(Some(body))) |> ignore }) |> ignore
      v.show(fn() { tall.get() }, fn(b) { b.height(Is(Some(more))) |> ignore })
      words_node(v, fn() { "最后一行" }, fn() { paragraph }) |> ignore
    })
  })
  if rest {
    open_it(t)
    t.run_for(@ui.move_most_ms)
  } else {
    t.tap_text("打开")
  }
  t
}

///|
/// The display's frames drawn till `ms` on from now.
fn sink_frames(t : @ui.Tester, ms : Double) -> Unit {
  let till = t.time() + ms
  while t.time() < till {
    t.frame()
  }
}

///|
/// A sheet closed (Escape) `into` on from what it holds growing (`grow`) or shrinking, walked frame by frame till it
/// is gone.
fn sink_closed(grow : Bool, body : Double, more : Double, into : Double) -> Unit raise {
  let tall = @signals.signal(!grow)
  let t = sink_sheet(tall, body, more)
  tall.set(grow)
  sink_frames(t, into)
  t.key(@ui.key_escape)
  sink_frames(t, @ui.move_most_ms)
  assert_true(t.find("第一行") is None, msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}

///|
test "a sheet closed as what it holds shrinks: it sinks on from as fast as its top went, frame by frame" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  for c in sink_cases {
    sink_closed(false, c.0, c.1, c.2)
  }
}

///|
test "a sheet closed as what it holds grows: its top slows as one going up, then sinks, frame by frame" {
  if @ui.test_at_a_rate() {
    return
  }
  for c in sink_cases {
    sink_closed(true, c.0, c.1, c.2)
  }
}

///|
test "a sheet rising as what it holds grows: it rises to as tall as it comes to, frame by frame" {
  if @ui.test_at_a_rate() {
    return
  }
  for c in sink_cases {
    let tall = @signals.signal(false)
    let t = sink_sheet(tall, c.0, c.1, rest=false)
    sink_frames(t, c.2)
    tall.set(true)
    sink_frames(t, @ui.move_most_ms)
    // (risen: its foot at the window's, all of it in the window)
    guard t.find("最后一行") is Some((_, y)) else { fail("no 最后一行: \{Repr(t.words().map(fn(w) { w.0 }))}") }
    assert_true(y < 844.0, msg="\{y}")
  }
}

///|
/// Where 第一行 is at moments of a sheet's sink, closed `into` on from what it holds growing (`grow`) or shrinking: the
/// moments jumped to (`walk` false) or the display's frames walked to them.
fn sink_tops(grow : Bool, c : (Double, Double, Double), walk : Bool) -> Array[Double] {
  let tall = @signals.signal(!grow)
  let t = sink_sheet(tall, c.0, c.1)
  tall.set(grow)
  t.run_for(c.2)
  t.key(@ui.key_escape)
  let from = t.time()
  let tops = []
  for ms in sink_moments {
    if walk {
      while t.time() + 1000.0 / 60.0 < from + ms {
        t.frame()
      }
    }
    t.run_for(from + ms - t.time())
    tops.push(t.find("第一行").map(fn(p) { p.1 }).unwrap_or(-1.0))
  }
  tops
}

///|
/// Moments of its sink looked at, on from its close.
let sink_moments : Array[Double] = [30.0, 90.0, 200.0]

///|
test "a sheet closed as what it holds grows or shrinks: the same at each moment whatever frames are drawn" {
  for c in sink_cases {
    for grow in [true, false] {
      let jumped = sink_tops(grow, c, false)
      let walked = sink_tops(grow, c, true)
      for i in 0..<jumped.length() {
        assert_true((jumped[i] - walked[i]).abs() < 1.0e-6, msg="\{Repr(c)} \{grow}: \{Repr(jumped)} \{Repr(walked)}")
      }
    }
  }
}

///|
/// Where 第一行 is at moments of a sheet's sink, closed `into` on from what it holds shrinking; `again`: what it holds
/// growing again sink_changed_on into the sink.
fn sink_tops_after(c : (Double, Double, Double), again : Bool) -> Array[Double] {
  let tall = @signals.signal(true)
  let t = sink_sheet(tall, c.0, c.1)
  tall.set(false)
  t.run_for(c.2)
  t.key(@ui.key_escape)
  let from = t.time()
  let tops = []
  let mut changed = false
  for ms in sink_moments {
    if again && !changed && ms > sink_changed_on {
      changed = true
      t.run_for(from + sink_changed_on - t.time())
      tall.set(true)
    }
    t.run_for(from + ms - t.time())
    tops.push(t.find("第一行").map(fn(p) { p.1 }).unwrap_or(-1.0))
  }
  tops
}

///|
/// How far into a sink what it holds changes again: between the first moment looked at and the second.
let sink_changed_on : Double = 50.0

///|
test "a sheet's sink, said at its moment, goes as it was said whatever what it holds does after" {
  for c in sink_cases {
    let as_said = sink_tops_after(c, false)
    let changed = sink_tops_after(c, true)
    for i in 0..<as_said.length() {
      assert_true((as_said[i] - changed[i]).abs() < 1.0e-6, msg="\{Repr(c)}: \{Repr(as_said)} \{Repr(changed)}")
    }
  }
}

///|
/// A phone's sheet of nodes, 信息, growing by 200 as what it holds opens, its 看详情 pressed `into` that (the frames on
/// the way `step` apart; none: in one jump to it), closing it for 详情, a step further in: where 详情's sheet's top is
/// at moments on from then. What the step sets out from (how tall the sheet stands then, sheet_node's seen_from) is its
/// height laid out at that moment, never the frame drawn last's.
fn cause_own_tops(step : Double?, into : Double) -> Array[Double] raise {
  let tall = @signals.signal(false)
  let t = presenting_tester(phone, fn(_) {
    panel_nodes(
      "信息",
      fn(v, close) {
        words_node(v, fn() { "信息内容" }, fn() { paragraph }) |> ignore
        v.box(fn(b) { b.height(Is(Some(80.0))) |> ignore }) |> ignore
        v.show(fn() { tall.get() }, fn(b) { b.height(Is(Some(200.0))) |> ignore })
        button_node(v, fn() { "看详情" }, fn() {
          close()
          panel_nodes("详情", fn(v, _) { words_node(v, fn() { "详情内容" }, fn() { paragraph }) |> ignore }, from=Unanchored)
        })
        |> ignore
      },
      from=Unanchored,
    )
  })
  open_it(t)
  t.run_for(@ui.move_most_ms)
  tall.set(true)
  let at = t.time() + into
  match step {
    Some(ms) =>
      while t.time() + ms <= at + 0.001 {
        t.frame(ms~)
      }
    None => t.run_for(into)
  }
  t.tap_text("看详情")
  let from = t.time()
  let tops = []
  for ms in sink_moments {
    t.run_for(from + ms - t.time())
    tops.push(one_sheet(t).0)
  }
  tops
}

///|
test "a sheet of nodes closed for a step further in as what it holds grows: the step the same whatever frames were drawn before it" {
  if @ui.test_at_a_rate() {
    return
  }
  // (three frames of 60 a second, six of 120: the press at the same moment however they fall, what it holds rising
  // fast then)
  let into = 3.0 * 1000.0 / 60.0
  let jumped = cause_own_tops(None, into)
  for ms in [1000.0 / 60.0, 1000.0 / 120.0] {
    let walked = cause_own_tops(Some(ms), into)
    for i in 0..<jumped.length() {
      assert_true((jumped[i] - walked[i]).abs() < 1.0e-9, msg="frames \{ms} ms apart: \{Repr(walked)} against \{Repr(jumped)}")
    }
  }
}

///|
/// How far into a page's slide what it holds grows (ms): four frames of 120 a second, the slide still going.
let sheet_grows_into : Double = 4.0 * 1000.0 / 120.0

///|
test "a sheet of nodes a step further in, what the new page holds growing as it slides in: the sheet goes one way, frame by frame" {
  // (补齐线's steps: the page's way said with how tall the sheet was at its cause, only its end following what it holds)
  if @ui.test_at_a_rate() {
    return
  }
  let more = @signals.signal(false)
  let t = presenting_tester(phone, fn(_) {
    panel_nodes(
      "信息",
      fn(v, close) {
        words_node(v, fn() { "信息内容" }, fn() { paragraph }) |> ignore
        button_node(v, fn() { "看详情" }, fn() {
          close()
          panel_nodes(
            "详情",
            fn(v, _) {
              v.box(fn(b) { b.height(Is(Some(20.0))) |> ignore }) |> ignore
              v.show(fn() { more.get() }, fn(b) { b.height(Is(Some(600.0))) |> ignore })
            },
            from=Unanchored,
          )
        })
        |> ignore
      },
      from=Unanchored,
    )
  })
  open_it(t)
  t.run_for(@ui.move_most_ms)
  t.tap_text("看详情")
  // (four frames of 120 a second into the page's slide: what it holds grows then, the slide still going)
  let ms = 1000.0 / 120.0
  let into = t.time() + sheet_grows_into
  while t.time() < into - 0.001 {
    t.frame(ms~)
  }
  more.set(true)
  let tops = []
  let till = t.time() + @ui.move_most_ms
  while t.time() < till {
    t.frame(ms~)
    tops.push(one_sheet(t).0)
  }
  for i in 1..<tops.length() {
    assert_true(tops[i] <= tops[i - 1] + 1.0e-9, msg="frame \{i}: its top went back down, \{Repr(tops)}")
  }
}

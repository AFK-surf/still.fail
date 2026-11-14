// Sizes steady (sizes_steady.mbt) takes what an answer changed at once (the window's tree's answering.mbt and
// answer_marked.mbt) as that answer's change, done in one frame as it must be: in the column of what it changed, while
// nothing there is on its way, no step is said, whether the answer made a structure's part (a show coming at once) or
// only set what a binding reads (a height). Where something in that column is on its way as the answer comes, a step
// is said as ever (the coordinator of the migration, 2026-11-14).

///|
/// A column 300 wide in a window 400 by 400: a box 40 tall, what `shown` shows (a box 30 tall), and a box as tall as
/// `h` says, each on a ground of its own (what sizes steady measures draws its own). Sizes steady said but not held
/// (its faults read here, sizes_steady_laid_wbtest's way).
fn answer_case(
  shown : @signals.Signal[Bool],
  h : @signals.Signal[Double],
  thumb_from? : @signals.Signal[Double] = @signals.signal(-1.0e9),
) -> (Tester, Ref[@view.View?]) {
  let last : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      // (a control's thumb, sliding 100 along its track over 200 ms from `thumb_from`: its own way, a Move it is drawn by)
      col.box(fn(track) {
        track.width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
        track.box(fn(b) {
          b
          .width(Is(Some(60.0)))
          .height(Is(Some(20.0)))
          .ground(Is(0x333333FFL))
          .moved_by(
            fn(_w, _h, now) {
              let p = (now - thumb_from.get()) / 200.0
              (100.0 * (if p < 0.0 { 0.0 } else if p > 1.0 { 1.0 } else { p * (2.0 - p) }), 0.0)
            },
            fn(_w, _h) { thumb_from.get() + 200.0 },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
      col.box(fn(b) { b.width(Is(Some(200.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)) |> ignore }) |> ignore
      col.show(fn() { shown.get() }, fn(s) {
        s.box(fn(b) { b.width(Is(Some(200.0))).height(Is(Some(30.0))).ground(Is(0x669933FFL)) |> ignore }) |> ignore
      })
      col.box(fn(b) {
        last.val = Some(b)
        b.width(Is(Some(200.0))).height(By(fn() { Some(h.get()) })).ground(Is(0x996633FFL)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, last)
}

///|
/// `frames` frames drawn one at a time, the display's; what sizes steady finds in each, gathered.
fn answer_frames(t : Tester, frames : Int) -> Array[String] {
  let out = []
  for _ in 0..<frames {
    t.frame()
    out.append(g().sizes_steady_faults(t.fake.time, t.period))
  }
  out
}

///|
test "sizes steady: an answer making a part at once in a still column steps what is under it, no fault; the same told by no answer at once is one" {
  let shown = @signals.signal(false)
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let (t, last) = answer_case(shown, h)
  answer_frames(t, 4) |> ignore
  let y0 = last.val.unwrap().placed_window_now().1
  @view.answering(fn() { shown.set(true) })
  let found = answer_frames(t, 4)
  let y1 = last.val.unwrap().placed_window_now().1
  assert_eq((found, y1 - y0), ([], 30.0), msg="the answer's part: \{Repr(found)} \{y1 - y0}")
}

///|
test "sizes steady: an answer setting what a binding reads in a still column, a height stepping, no fault; the same set by no answer, one" {
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let (t, _) = answer_case(@signals.signal(false), h)
  answer_frames(t, 4) |> ignore
  @view.answering(fn() { h.set(180.0) })
  let found = answer_frames(t, 4)
  assert_eq(found, [], msg="the answer's height: \{Repr(found)}")
  // (set by no answer: a step, as ever)
  h.set(260.0)
  assert_true(answer_frames(t, 4).length() > 0, msg="no answer's: none found")
}

///|
test "sizes steady: an answer stepping a height in a column with a part on its way in it: a fault, as ever" {
  let shown = @signals.signal(false)
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let (t, _) = answer_case(shown, h)
  answer_frames(t, 4) |> ignore
  // (a cause's part making its way in, under way as the answer comes)
  shown.set(true)
  answer_frames(t, 3) |> ignore
  @view.answering(fn() { h.set(180.0) })
  assert_true(answer_frames(t, 4).length() > 0, msg="a step while a way goes in its column: none found")
}

///|
test "sizes steady: an answer stepping a height while a control's thumb slides its own way in the column: no fault" {
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let thumb_from = @signals.signal(-1.0e9)
  let (t, _) = answer_case(@signals.signal(false), h, thumb_from~)
  answer_frames(t, 4) |> ignore
  // (pressed: the thumb sets out; the answer comes 120 ms after, the thumb still on its way)
  thumb_from.set(t.fake.time)
  answer_frames(t, 7) |> ignore
  @view.answering(fn() { h.set(180.0) })
  let found = answer_frames(t, 8)
  assert_eq(found, [], msg="the answer's height beside the thumb: \{Repr(found)}")
}

///|
test "sizes steady: two answers in two frames one after the other, each done at once: no fault" {
  let shown = @signals.signal(false)
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let (t, _) = answer_case(shown, h)
  answer_frames(t, 4) |> ignore
  @view.answering(fn() { shown.set(true) })
  let first = answer_frames(t, 1)
  @view.answering(fn() { h.set(180.0) })
  let found = first + answer_frames(t, 4)
  assert_eq(found, [], msg="two answers: \{Repr(found)}")
}

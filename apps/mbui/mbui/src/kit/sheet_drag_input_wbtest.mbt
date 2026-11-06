// The old sheet can opt into deciding a drag at the input, so a presenter snapshots the stack at the release rather
// than at whichever frame happens to follow it.

///|
fn input_sheet_close(with_frames : Bool, delayed? : Bool = false) -> (Double, Double, Double, Int, Array[SheetDrag]) raise {
  let open = @signals.signal(true)
  let height = @signals.signal(100.0)
  let extent : Ref[@view.View?] = Ref(None)
  let close_at = Ref(0.0)
  let measured = Ref(0.0)
  let closes = Ref(0)
  let result : Array[SheetDrag] = []
  let top = Ref(0)
  let sheet_id = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    extent.val = Some(root.box(fn(v) { v.over(Is(true)).height(By(fn() { Some(height.get()) })) |> ignore }))
    let island = @ui.old(root, fn(c) {
      top.val = c.id("input-sheet/top")
      sheet_id.val = c.id("input-sheet")
      let sheet = sheet(c, "input-sheet", open.get(), h=300.0, on_drag_close=fn() {
        root.event_action(fn() {
          closes.val += 1
          close_at.val = root.cause_at()
          measured.val = extent.val.unwrap().laid_size().1
          open.set(false)
        })
        (0.0, 600.0)
      }, fn() { c.box(w=Px(200.0), h=Px(80.0), fn() {  }) |> ignore })
      match sheet.dragged { Some(dragged) => result.push(dragged); None => () }
    })
    island.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
  })
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.ctx().rect_of(top.val).unwrap()
  let x = x + 30.0
  let y = y + 10.0
  let began_at = t.time()
  let down_at = began_at + @ui.input_step_ms
  let moved_at = down_at + @ui.input_step_ms
  let ended_at = moved_at + @ui.input_step_ms
  if delayed {
    let delivery_delay_ms = @ui.move_most_ms / 2.0
    t.advance(delivery_delay_ms)
    t.touch_at(0, x, y, down_at)
    t.touch_at(1, x, y + 150.0, moved_at)
  } else {
    t.advance(@ui.input_step_ms)
    t.touch(0, x, y)
    t.advance(@ui.input_step_ms)
    t.touch(1, x, y + 150.0)
  }
  if with_frames { t.frame_at(t.time()) }
  height.set(220.0)
  let released_at = if delayed {
    t.touch_at(2, x, y + 150.0, ended_at)
    ended_at
  } else {
    t.advance(@ui.input_step_ms)
    let at = t.time()
    t.touch(2, x, y + 150.0)
    at
  }
  assert_eq((closes.val, measured.val, close_at.val), (1, 220.0, released_at))
  assert_false(open.get())
  height.set(300.0)
  let s = kit.val.sheets[sheet_id.val]
  assert_eq(s.below.target(), 600.0)
  let sample_ms = @ui.move_most_ms / 3.0
  let at_sample = s.below.value(released_at + sample_ms)
  t.advance(sample_ms)
  t.frame_at(t.time())
  t.frame_at(t.time())
  (at_sample, measured.val, close_at.val, closes.val, result)
}

///|
test "an old sheet closes at drag release using that event's stack geometry" {
  let with_frames = input_sheet_close(true)
  let without_frames = input_sheet_close(false)
  assert_eq(with_frames, without_frames)
  assert_eq(with_frames.4, [DraggedClosed])
}

///|
test "a delayed old sheet drag still closes from the release time" {
  assert_eq(input_sheet_close(false, delayed=true), input_sheet_close(false))
}

///|
fn input_sheet_detent(with_frames : Bool, cancel : Bool) -> (Double, Double, Int, Array[SheetDrag]) {
  let closed = Ref(0)
  let reported : Array[SheetDrag] = []
  let top = Ref(0)
  let sheet_id = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    top.val = c.id("detent-sheet/top")
    sheet_id.val = c.id("detent-sheet")
    let sheet = sheet(c, "detent-sheet", true, h=844.0 * 0.55, detents=[0.55, 0.94], on_drag_close=fn() {
      closed.val += 1
      (0.0, 0.0)
    }, fn() { c.box(w=Px(200.0), h=Px(80.0), fn() {  }) |> ignore })
    match sheet.dragged { Some(dragged) => reported.push(dragged); None => () }
  }, w=390.0, h=844.0)
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.ctx().rect_of(top.val).unwrap()
  let x = x + 30.0
  let y = y + 10.0
  t.advance(@ui.input_step_ms)
  t.touch(0, x, y)
  t.advance(@ui.input_step_ms)
  t.touch(1, x, y - 200.0)
  if with_frames { t.frame_at(t.time()) }
  t.advance(@ui.input_step_ms)
  let released_at = t.time()
  t.touch(if cancel { 3 } else { 2 }, x, y - 200.0)
  let s = kit.val.sheets[sheet_id.val]
  let target = s.h.target()
  let sample_ms = @ui.move_most_ms / 3.0
  let sample = s.h.value(released_at + sample_ms)
  t.advance(sample_ms)
  t.frame_at(t.time())
  t.frame_at(t.time())
  (target, sample, closed.val, reported)
}

///|
test "an old sheet keeps its detent and release velocity without intermediate frames" {
  let with_frames = input_sheet_detent(true, false)
  let without_frames = input_sheet_detent(false, false)
  assert_eq(with_frames, without_frames)
  assert_eq(with_frames.0, 844.0 * 0.94)
  assert_eq(with_frames.2, 0)
  assert_eq(with_frames.3, [DraggedTo(0.94)])
}

///|
test "an old sheet's cancelled input drag returns to its previous detent" {
  let (target, _, closed, reported) = input_sheet_detent(false, true)
  assert_eq(target, 844.0 * 0.55)
  assert_eq(closed, 0)
  assert_eq(reported, [])
}

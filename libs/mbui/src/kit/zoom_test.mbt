// A picture's zoom (zoom.mbt): fitted within its margin and never enlarged, pinched round the fingers and kept within
// the stage, a double tap in and back, and a stage's own (fitted edge to edge) resized keeping a point in sight.

///|
fn near_rect(r : (Double, Double, Double, Double)?, x : Double, y : Double, w : Double, h : Double) -> Bool {
  match r {
    Some((a, b, c, d)) => (a - x).abs() < 0.0001 && (b - y).abs() < 0.0001 && (c - w).abs() < 0.0001 && (d - h).abs() < 0.0001
    None => false
  }
}

///|
test "fitted within a margin, never enlarged; pinched round a point that stays put; kept within the stage" {
  let z = @kit.Zoom::new()
  z.boxed(390.0, 844.0, at=now())
  z.natural(600.0, 400.0, at=now())
  // (390 - 24) / 600
  assert_true((z.scale - 366.0 / 600.0).abs() < 0.0001)
  assert_true(near_rect(z.rect(cur()), 12.0, 300.0, 366.0, 244.0))
  let small = @kit.Zoom::new()
  small.boxed(390.0, 844.0, at=now())
  small.natural(100.0, 50.0, at=now())
  assert_eq(small.scale, 1.0)
  // twice as large round (100, 422): that point of the picture stays under it
  let (x0, _, w0, _) = z.rect(cur()).unwrap()
  let u = (100.0 - x0) / w0
  z.transform(100.0, 422.0, 2.0, 0.0, 0.0, at=now())
  let (x1, _, w1, _) = z.rect(cur()).unwrap()
  assert_true((x1 + u * w1 - 100.0).abs() < 0.0001)
  assert_true(z.zoomed(cur()))
  // panned far: no gap at its edges
  z.pan(10000.0, 0.0, at=now())
  assert_true(z.rect(cur()).unwrap().0.abs() < 0.0001)
  // no further than 16 times
  z.transform(195.0, 422.0, 1000.0, 0.0, 0.0, at=now())
  assert_true((z.scale - 16.0).abs() < 0.0001)
}

///|
test "a stage's own: fitted edge to edge, the keyboard up keeping the frame as large and its point in sight" {
  let z = @kit.Zoom::new(margin=fn(_) { 0.0 }, enlarge=true, min_scale=fn(fit) { fit }, max_scale=fn(fit) {
    fit * 5.0
  })
  z.natural(1280.0, 720.0, at=now())
  z.boxed(800.0, 360.0, at=now())
  assert_true(near_rect(z.rect(cur()), 80.0, 0.0, 640.0, 360.0))
  z.resize_keeping(800.0, 150.0, Some((0.5, 0.9)), 40.0, when=now())
  let (_, y, w, h) = z.rect(cur()).unwrap()
  assert_true((w - 640.0).abs() < 0.0001)
  assert_true(y + 0.9 * h >= 0.0 && y + 0.9 * h <= 150.0)
  z.resize_keeping(800.0, 360.0, Some((0.5, 0.9)), 40.0, when=now())
  assert_true(!z.zoomed(cur()))
  z.fit_now(at=now())
  assert_true(near_rect(z.rect(cur()), 80.0, 0.0, 640.0, 360.0))
}

///|
test "a page on a canvas: free, dragged anywhere; its fitted scale by thousandths; its own bounds of scale" {
  let z = @kit.Zoom::new(margin=fn(_) { 16.0 }, min_scale=fn(_) { 0.05 }, max_scale=fn(_) { 4.0 }, free=true, fit_step=0.001)
  z.boxed(390.0, 600.0, at=now())
  z.natural(1280.0, 800.0, at=now())
  // (390 - 32) / 1280 = 0.2796875, down to 0.279
  assert_true((z.scale - 0.279).abs() < 0.0000001)
  // dragged far off: it goes there
  z.pan(-1000.0, 0.0, at=now())
  assert_true(z.rect(cur()).unwrap().0 < -800.0)
  // pinched down past its least: 0.05
  z.transform(195.0, 300.0, 0.01, 0.0, 0.0, at=now())
  assert_true((z.scale - 0.05).abs() < 0.0000001)
  z.fit_now(at=now())
  assert_true(z.fitted && (z.scale - 0.279).abs() < 0.0000001)
}

///|
test "what reads where a zoom shows is told as that changes, by any way it changes: resized keeping a point in place" {
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(200.0, 200.0, at=now())
  let shown = @signals.computed(fn(_) { z.rect(cur()) })
  assert_true(near_rect(shown.get(), 50.0, 50.0, 100.0, 100.0))
  // (the stage larger, the picture's middle where it was, then kept centred: nothing to bring in sight)
  z.resize_keeping(300.0, 300.0, Some((0.5, 0.5)), 0.0, when=now())
  assert_true(near_rect(z.rect(cur()), 100.0, 100.0, 100.0, 100.0), msg="\{Repr(z.rect(cur()))}")
  assert_eq(shown.get(), z.rect(cur()))
}

///|
test "what reads where a zoom shows is not told where nothing it shows changed, nor of another zoom" {
  let a = @kit.Zoom::new(free=true)
  a.natural(100.0, 100.0, at=now())
  a.boxed(400.0, 400.0, at=now())
  let b = @kit.Zoom::new(free=true)
  b.natural(100.0, 100.0, at=now())
  b.boxed(400.0, 400.0, at=now())
  let b_was = b.rect(cur())
  let reads = Ref(0)
  let shown = @signals.computed(fn(_) {
    reads.val = reads.val + 1
    a.rect(cur())
  })
  shown.get() |> ignore
  let first = reads.val
  // (moved nowhere; another one moved, and it did)
  a.pan(0.0, 0.0, at=now())
  b.pan(30.0, 0.0, at=now())
  b.transform(200.0, 200.0, 1.5, 0.0, 0.0, at=now())
  shown.get() |> ignore
  assert_eq(reads.val, first)
  assert_true(b.rect(cur()) != b_was, msg="\{Repr(b.rect(cur()))}")
  // (a small one kept centred in its stage, pushed against its edges, pinched by nothing: as it was, told nothing)
  let c = @kit.Zoom::new()
  c.natural(100.0, 100.0, at=now())
  c.boxed(400.0, 400.0, at=now())
  let c_reads = Ref(0)
  let c_shown = @signals.computed(fn(_) {
    c_reads.val = c_reads.val + 1
    c.rect(cur())
  })
  c_shown.get() |> ignore
  c.pan(60.0, -20.0, at=now())
  c.transform(200.0, 200.0, 1.0, 0.0, 0.0, at=now())
  c_shown.get() |> ignore
  assert_eq(c_reads.val, 1)
  // (and moved: told)
  a.pan(30.0, 0.0, at=now())
  shown.get() |> ignore
  assert_eq(reads.val, first + 1)
}

///|
/// A picture gliding in from fitted (3 times, round a point off the stage's middle), frames drawn 100 ms on (its step
/// sampling it then, or not), then told `then`: where it is.
fn glide_cut(sampled : Bool, then : (@kit.Zoom) -> Unit) -> (Double, Double, Double, Double)? {
  let t = @ui.Tester::new(fn(_c) {  })
  t.draw()
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  z.zoom_to(3.0, 150.0, 170.0, true, at=now())
  // (frames on, as a host draws them: none of them steps it)
  t.run_for(some_frames_ms)
  if sampled {
    z.step(cur())
  }
  then(z)
  z.rect(cur())
}

///|
test "a glide cut short at a moment goes on from where it was then, a frame sampled it or not: panned, or sent elsewhere" {
  let pan = fn(z : @kit.Zoom) { z.pan(10.0, 0.0, at=now()) }
  let other = fn(z : @kit.Zoom) { z.zoom_to(1.5, 100.0, 100.0, false, at=now()) }
  let tapped = fn(z : @kit.Zoom) { z.double_tap(200.0, 200.0, at=now()) }
  assert_eq(glide_cut(false, pan), glide_cut(true, pan))
  assert_eq(glide_cut(false, other), glide_cut(true, other))
  // (a double tap midway: zoomed in by then, sampled or not: back to fitted, gliding there)
  assert_eq(glide_cut(false, tapped), glide_cut(true, tapped))
  // (cut short midway: neither where it set out nor where it went)
  let mid = glide_cut(false, fn(_z) {  }).unwrap()
  assert_true(mid.2 > 100.0 && mid.2 < 300.0, msg="\{Repr(mid)}")
}

///|
test "a zoom told a command tells what reads it once, as the command leaves it: fitted again, a glide cut short by a pan" {
  let t = @ui.Tester::new(fn(_c) {  })
  t.draw()
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  z.zoom_to(2.0, 150.0, 150.0, false, at=now())
  // (what reads it, run as it is told: what it reads then)
  let seen : Array[(Bool, Bool)] = []
  let stop = @signals.effect(fn() {
    z.rect(cur()) |> ignore
    seen.push((z.fitted, z.zoomed(cur())))
  })
  seen.clear()
  z.fit_now(at=now())
  assert_eq(seen, [(true, false)])
  seen.clear()
  z.zoom_to(3.0, 150.0, 150.0, true, at=now())
  t.run_for(some_frames_ms)
  seen.clear()
  z.pan(10.0, 0.0, at=now())
  assert_eq(seen.length(), 1)
  stop()
}

///|
/// A picture set gliding in at `t0` between frames, the last frame before a pan at `t0 + 20` drawn at `t0 + last`:
/// where the pan leaves it.
fn pan_after_frame(last : Double) -> (Double, Double, Double, Double)? {
  let t = @ui.Tester::new(fn(_c) {  })
  t.draw()
  let t0 = t.time()
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  z.zoom_to(3.0, 150.0, 170.0, true, at=now())
  t.frame_at(t0 + last)
  t.advance(t0 + 20.0 - t.time())
  z.pan(10.0, 0.0, at=now())
  z.rect(cur())
}

///|
test "a pan told at a moment between frames starts from where the glide has it then, whenever the frame before it was drawn" {
  let ten = pan_after_frame(10.0)
  assert_eq(pan_after_frame(15.0), ten)
  // (by then it had left where it set out)
  assert_true(ten.unwrap().2 > 100.0, msg="\{Repr(ten)}")
}

///|
/// A large picture zoomed in, flung across at `t0` between frames: the tester, the zoom and when the fling ends.
fn flung() -> (@ui.Tester, @kit.Zoom, Double) {
  let t = @ui.Tester::new(fn(_c) {  })
  t.draw()
  let z = @kit.Zoom::new()
  z.natural(1000.0, 1000.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  z.zoom_to(1.0, 200.0, 200.0, false, at=now())
  z.fling(1.5, 0.0, at=now())
  (t, z, z.fling_ends())
}

///|
test "a press after a fling's end takes nothing, a frame drawn at its end (and stepped) or not; one before it, the fling" {
  let after = fn(drawn : Bool) {
    let (t, z, end) = flung()
    if drawn {
      t.frame_at(end)
      z.step(cur())
    }
    t.advance(end + 1.0 - t.time())
    z.stop_fling(at=now())
  }
  // (one tester at a time: the one before let go as another is made)
  let (t, z, end) = flung()
  t.advance(end - 10.0 - t.time())
  let before = z.stop_fling(at=now())
  assert_eq((after(true), after(false), before), (false, false, true))
}

///|
/// A fling, a frame drawn (and stepped) ahead past its end or none, then a pan told for a moment midway through it
/// (50 ms in): where the pan leaves it.
fn pan_before_end(ahead : Bool) -> (Double, Double, Double, Double)? {
  let (t, z, end) = flung()
  let t0 = t.time()
  if ahead {
    t.frame_at(end + 5.0)
    z.step(cur())
  }
  // (the pan's own moment, before the frame drawn ahead: said by who tells it, and as the host's clock has it)
  t.advance(t0 + 50.0 - t.time())
  z.pan(10.0, 0.0, at=t0 + 50.0)
  z.rect(cur())
}

///|
test "a fling drawn ahead past its end, then told a pan at a moment before it: from where its way had it then, as drawn or not" {
  let unread = pan_before_end(false)
  assert_eq(pan_before_end(true), unread)
}

///|
/// A picture the window's tree sets gliding at 1050 (a moment it said, done as a frame comes at or past it), frames
/// drawn at each of `frames` and at 1200: where it is then.
fn glide_told_by_tree(frames : Array[Double]) -> (Double, Double, Double, Double)? {
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  let t = @ui.Tester::new(fn(_c) {  }, time=1000.0, tree=fn(root : @view.View) {
    root.at_moment(1050.0, fn() { z.zoom_to(3.0, 150.0, 170.0, true, at=now()) }) |> ignore
  })
  t.draw()
  for f in frames {
    t.frame_at(f)
  }
  t.frame_at(1200.0)
  z.rect(cur())
}

///|
test "a glide the window's tree tells at a moment sets out from that moment, the frame that does it whenever it comes" {
  let each = glide_told_by_tree([1050.0, 1100.0])
  let one = glide_told_by_tree([])
  assert_eq(one, each)
  // (on its way by then, from 1050)
  assert_true(one.unwrap().2 > 100.0, msg="\{Repr(one)}")
}

///|
/// A picture a press on the window's tree sets gliding, the press at 1050 handed on at 1080 between frames, frames drawn
/// at each of `frames` and at 1200: where it is then.
fn glide_pressed_on_tree(frames : Array[Double]) -> (Double, Double, Double, Double)? {
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  let t = @ui.Tester::new(fn(_c) {  }, time=1000.0, tree=fn(root : @view.View) {
    root.box(fn(b) {
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(100.0)))
      .on_press(fn() { z.zoom_to(3.0, 150.0, 170.0, true, at=now()) })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (handed on later than it happened, as a host may, said so)
  t.advance(handed_on_at - t.time())
  t.touch_at(0, 50.0, 50.0, happened_at)
  t.touch_at(2, 50.0, 50.0, 1050.0)
  for f in frames {
    t.frame_at(f)
  }
  t.frame_at(1200.0)
  z.rect(cur())
}

///|
test "a glide a press on the window's tree tells sets out from the press's moment, the frame that takes it whenever it comes" {
  let each = glide_pressed_on_tree([1090.0, 1100.0])
  let one = glide_pressed_on_tree([])
  assert_eq(one, each)
  // (as one told to set out at 1050, read at 1200)
  let t = @ui.Tester::new(fn(_c) {  }, time=1000.0)
  t.draw()
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0, at=now())
  z.boxed(400.0, 400.0, at=now())
  t.advance(happened_at - t.time())
  z.zoom_to(3.0, 150.0, 170.0, true, at=happened_at)
  t.frame_at(1200.0)
  assert_eq(one, z.rect(cur()))
}

///|
/// A while of frames as a host draws them (some of a glide's way, not all of it).
let some_frames_ms : Double = 100.0

///|
/// When a finger's event happened, and when a host handed it on (later, as a host may).
let happened_at : Double = 1050.0

///|
let handed_on_at : Double = 1080.0

///|
test "a bar over the stage: the fitted picture clear of it, in the middle of what is left; zoomed in, its top comes to the bar's foot" {
  let z = @kit.Zoom::new()
  z.boxed(1400.0, 820.0, at=now())
  z.natural(880.0, 1280.0, at=now())
  // (no bar: 32 round it)
  assert_eq(z.rect(cur()).unwrap().1, 32.0)
  z.under_bars(45.0, 0.0, at=now())
  // (16 past the bar, 32 from the foot)
  let (_, y, _, h) = z.rect(cur()).unwrap()
  assert_eq(y, 61.0)
  assert_eq(y + h, 788.0)
  // (panned as far down as it goes, its top no higher than the bar's foot needs; as far up, its foot at the stage's)
  z.zoom_to(2.0, 700.0, 410.0, false, at=now())
  z.pan(0.0, 10000.0, at=now())
  assert_eq(z.rect(cur()).unwrap().1, 45.0)
  z.pan(0.0, -10000.0, at=now())
  let (_, y, _, h) = z.rect(cur()).unwrap()
  assert_eq(y + h, 820.0)
  // (a picture short of the room: in the middle of the room between the margins, zoomed or not)
  z.reset(at=now())
  z.natural(100.0, 100.0, at=now())
  z.fit_now(at=now())
  let (_, y, _, h) = z.rect(cur()).unwrap()
  assert_eq(y - 61.0, 788.0 - (y + h))
}

///|
test "a bar over the stage's foot too: the fitted picture between them; zoomed in, its foot comes to the lower bar's top" {
  let z = @kit.Zoom::new()
  z.boxed(1400.0, 820.0, at=now())
  z.natural(880.0, 1280.0, at=now())
  z.under_bars(45.0, 60.0, at=now())
  let (_, y, _, h) = z.rect(cur()).unwrap()
  assert_eq(y, 61.0)
  assert_eq(y + h, 744.0)
  z.zoom_to(2.0, 700.0, 410.0, false, at=now())
  z.pan(0.0, -10000.0, at=now())
  let (_, y, _, h) = z.rect(cur()).unwrap()
  assert_eq(y + h, 760.0)
  z.pan(0.0, 10000.0, at=now())
  assert_eq(z.rect(cur()).unwrap().1, 45.0)
}

///|
/// The old view these tests read a zoom as (the current one, none of their own), and its moment, what tells it.
fn cur() -> @ui.Ctx {
  @ui.current()
}

///|
fn now() -> Double {
  cur().moment()
}

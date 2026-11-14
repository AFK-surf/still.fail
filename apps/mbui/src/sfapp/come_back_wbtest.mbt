// What a show makes down a column, closing its room on a Move and called back on its way (mbui's View::come_back): on
// from as fast as its room closed, past where it was a little and back, never stopped dead as it turned (sizes_steady,
// on the display's frames walked here), in a column of its own and in one centred in the window, as a dialog's.

///|
/// A column (its ground drawn: sizes_steady looks at it) of 上 (30 tall), what `here` shows (a box holding 甲, 255
/// tall: what it holds cut by it as it closes) and 下 (30),
/// at the window's top or centred in it (`centred`, as a dialog's).
fn come_back_tester(here : @signals.Signal[Bool], centred : Bool) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=600.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(outer) {
      if centred {
        @sf.style_node(outer, fn() { come_back_centred })
      }
      outer.box(fn(col) {
        col.ground(Is(0xffeeeeeeL)) |> ignore
        col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("上")) |> ignore }) |> ignore
        col.show(fn() { here.get() }, fn(a) {
          a.box(fn(b) { b.height(Is(Some(255.0))).words(Is("甲")) |> ignore }) |> ignore
        })
        col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("下")) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
let come_back_centred : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// Where 下 is.
fn come_back_y(t : @ui.Tester) -> Double {
  t.rect_of("下").map(fn(r) { r.1 }).unwrap_or(-1.0)
}

///|
/// A frame's length at 60 a second, as a display draws them.
let come_back_frame_ms : Double = 1000.0 / 60.0

///|
/// How long 甲's room takes to close (a Move over its 255 points).
fn come_back_close_ms() -> Double {
  @ui.move_ms(255.0)
}

///|
/// 甲 let go of, called back `after` later (on a frame); from then, a frame each `ms` (a 60th of a second) till it is
/// back: where 下 was at each, first where it stood, and the index of the frame it was called back in.
fn come_back_walk(centred : Bool, after : Double, ms? : Double = come_back_frame_ms) -> (Array[Double], Int) {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let t = come_back_tester(here, centred)
  // (as a test walks to it: a run first, the frames' clock where that leaves it)
  t.run_for(@ui.move_most_ms)
  let ys = [come_back_y(t)]
  here.set(false)
  t.frame()
  ys.push(come_back_y(t))
  let back = t.time() + after
  while t.time() + ms <= back {
    t.run_for(ms)
    ys.push(come_back_y(t))
  }
  let turn = ys.length() - 1
  here.set(true)
  t.frame()
  ys.push(come_back_y(t))
  let end = t.time() + @ui.move_most_ms
  while t.time() < end {
    t.run_for(ms)
    ys.push(come_back_y(t))
  }
  t.assert_idle()
  (ys, turn)
}

///|
/// Called back `after` its room began to close: 下 goes up as 甲 closes, on up a little from as fast as it went as it
/// is called back, then down to where it stood, once: no frame of its turning still while those round it move.
fn come_back_holds(centred : Bool, after : Double) -> Unit raise {
  let (ys, turn) = come_back_walk(centred, after)
  let rest = ys[0]
  // (closing: up, each frame from the first it moved)
  for i in 2..=turn {
    assert_true(ys[i] < ys[i - 1], msg="\{centred} \{after}: closing at \{i}: \{Repr(ys)}")
  }
  // (called back: up a little more first, from as fast as it went; not still, not down at once)
  assert_true(ys[turn + 1] < ys[turn], msg="\{centred} \{after}: on from its speed as it is called back: \{Repr(ys)}")
  // (then down to where it stood, never up again)
  let mut down = false
  for i in (turn + 2)..<ys.length() {
    if ys[i] > ys[i - 1] {
      down = true
    } else {
      assert_true(!down || ys[i] == ys[i - 1], msg="\{centred} \{after}: up again at \{i}: \{Repr(ys)}")
    }
  }
  assert_eq(ys[ys.length() - 1], rest)
}

///|
test "a show's node called back a frame after it starts closing its room: on from its speed, then back; in a column, and centred" {
  come_back_holds(false, come_back_frame_ms)
  come_back_holds(true, come_back_frame_ms)
}

///|
test "a show's node called back half way through closing its room: on from its speed, then back; in a column, and centred" {
  come_back_holds(false, come_back_close_ms() / 2.0)
  come_back_holds(true, come_back_close_ms() / 2.0)
}

///|
test "a show's node called back as it has all but closed its room: on from its speed, then back; in a column, and centred" {
  come_back_holds(false, come_back_close_ms() * come_back_late)
  come_back_holds(true, come_back_close_ms() * come_back_late)
}

///|
/// How far through closing its room the last is called back: still going, slowly.
let come_back_late : Double = 0.8

///|
/// 甲 let go of and called back `after` later; where 下 is at each of `moments` (ms from the call), walked to on the
/// display's frames (`frames`) or in one step to each.
fn come_back_at(after : Double, moments : Array[Double], frames : Bool) -> Array[Double] {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let t = come_back_tester(here, false)
  t.run_for(@ui.move_most_ms)
  here.set(false)
  t.frame()
  t.run_for(after)
  here.set(true)
  t.frame()
  let at = t.time()
  moments.map(fn(m) {
    let to = at + m
    if frames {
      while t.time() + come_back_frame_ms < to {
        t.run_for(come_back_frame_ms)
      }
    }
    t.run_for(to - t.time())
    come_back_y(t)
  })
}

///|
test "a show's node called back: where its way has it at each moment the same however the frames fell before it" {
  let moments = [10.0, 50.0, 125.0, 200.0, 333.0]
  for after in [come_back_frame_ms, come_back_close_ms() / 2.0, come_back_close_ms() * come_back_late] {
    let walked = come_back_at(after, moments, true)
    let jumped = come_back_at(after, moments, false)
    assert_eq(walked, jumped, msg="called back \{after} on")
  }
}

///|
/// Seen hanging at its turn (the coordinator of the migration, 2026-11-10: 「松手，滑一下，愣住，再弹回去」): of `ys`, a
/// thing's place on frames `ms` apart from the one it set off again on, the longest run of frames each going less than
/// half a point a 60th of a second (ms): from the first till the frame it went fastest on after it turned; none where it
/// never turned.
fn hung_at_turn(ys : Array[Double], ms : Double) -> Double {
  let steps = Array::makei(ys.length() - 1, fn(i) { ys[i + 1] - ys[i] })
  let first = steps.search_by(fn(d) { d != 0.0 })
  guard first is Some(f) else { return 0.0 }
  let set_out = steps[f]
  let turned = steps.search_by(fn(d) { d * set_out < 0.0 })
  guard turned is Some(ti) else { return 0.0 }
  let mut fastest = ti
  for i in ti..<steps.length() {
    if steps[i].abs() > steps[fastest].abs() {
      fastest = i
    }
  }
  let still = turn_still_speed * ms
  let mut run = 0
  let mut most = 0
  for i in 0..=fastest {
    run = if steps[i].abs() < still { run + 1 } else { 0 }
    most = if run > most { run } else { most }
  }
  most.to_double() * ms
}

///|
/// Under half a point a 60th of a second (points a ms): a frame seen still.
let turn_still_speed : Double = 0.5 / come_back_frame_ms

///|
/// Two 60ths of a second (ms): frames still that long, together, are seen hanging.
let turn_hung_ms : Double = 2.0 * come_back_frame_ms

///|
/// How fast (points a ms) a thing set off again has to go for its turn to be judged: one slower than that is all but
/// still as it sets off.
let turn_judged_from : Double = 0.05

///|
/// Hanging at its turn as `ys` (on frames `ms` apart) has it, called `what`: none, frames still as long as turn_hung_ms.
fn assert_not_hung(ys : Array[Double], ms : Double, what : String) -> Unit raise {
  let hung = hung_at_turn(ys, ms)
  assert_true(hung + 0.01 < turn_hung_ms, msg="\{what}: still \{hung} ms at its turn: \{Repr(ys)}")
}

///|
test "a show's node called back as it closes its room: never hanging near still at its turn, at 60 and 120 a second" {
  for ms in [1000.0 / 60.0, 1000.0 / 120.0] {
    for after in [100.0, 150.0, 200.0, 220.0, 240.0] {
      let (ys, turn) = come_back_walk(false, after, ms~)
      let v = (ys[turn] - ys[turn - 1]) / ms
      if v.abs() > turn_judged_from {
        assert_not_hung(ys[turn:].to_owned(), ms, "called back \{after} ms on, frames \{ms} ms apart")
      }
    }
  }
}

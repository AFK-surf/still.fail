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
/// 甲 let go of, called back `after` later (on a frame); from then, a frame each 60th of a second till it is back: where
/// 下 was at each, first where it stood, and the index of the frame it was called back in.
fn come_back_walk(centred : Bool, after : Double) -> (Array[Double], Int) {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let t = come_back_tester(here, centred)
  // (as a test walks to it: a run first, the frames' clock where that leaves it)
  t.run_for(@ui.move_most_ms)
  let ys = [come_back_y(t)]
  here.set(false)
  t.frame()
  ys.push(come_back_y(t))
  let back = t.time() + after
  while t.time() + come_back_frame_ms <= back {
    t.run_for(come_back_frame_ms)
    ys.push(come_back_y(t))
  }
  let turn = ys.length() - 1
  here.set(true)
  t.frame()
  ys.push(come_back_y(t))
  let end = t.time() + @ui.move_most_ms
  while t.time() < end {
    t.run_for(come_back_frame_ms)
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
    assert_true(ys[i] < ys[i - 1], msg="\{centred} \{after}: closing at \{i}: \{ys}")
  }
  // (called back: up a little more first, from as fast as it went; not still, not down at once)
  assert_true(ys[turn + 1] < ys[turn], msg="\{centred} \{after}: on from its speed as it is called back: \{ys}")
  // (then down to where it stood, never up again)
  let mut down = false
  for i in (turn + 2)..<ys.length() {
    if ys[i] > ys[i - 1] {
      down = true
    } else {
      assert_true(!down || ys[i] == ys[i - 1], msg="\{centred} \{after}: up again at \{i}: \{ys}")
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

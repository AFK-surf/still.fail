// A message's table wider than its column dragged across and flung on 小屏 (mbui's Ctx::sideways): where it is read as
// it is painted, the message's row kept, nothing of the list built for it (2026-11-10: each frame of it built the
// message's rows again, twice a frame's work of the list dragged up and down, frames dropped); drawn at each moment as
// building every row draws it.

///|
/// A frame at 60 a second: how far apart the finger's moves are.
let table_slid_frame_ms : Double = 16.0

///|
/// chat-md's table dragged across and flung, then back: what is drawn at each moment after, and the rows the frames
/// built while it followed the finger and as it was flung on (none where they are drawn again: `again`; else every
/// one, every frame). The press going down and up is an event the frame is built for, its rows with it: not counted.
fn table_slid(again : Bool) -> (Array[Array[String]], Array[(Int, Int)]) {
  let t = kept_rows_open("chat-md", 390.0, 844.0)
  t.set_rows_on_pixels(true)
  t.drawn_again(again)
  t.said() |> ignore
  let (_, y) = t.drawn_of("只排可见的行").unwrap()
  let out = []
  let built = []
  for way in [-1.0, 1.0] {
    let x0 = if way < 0.0 { 360.0 } else { 60.0 }
    t.press_at(x0, y)
    // (past the slop: from there it follows the finger)
    t.move_to(x0 + way * 20.0, y)
    t.rows_built() |> ignore
    for step in 1..=6 {
      t.move_to(x0 + way * (20.0 + step.to_double() * 30.0), y)
      t.run_for(table_slid_frame_ms)
      out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_said(t))
    }
    built.append(t.rows_built().filter(fn(b) { b.1 >= 0 }))
    // (let go moving: flung on)
    t.release(x0 + way * 200.0, y)
    t.rows_built() |> ignore
    for _ in 0..<5 {
      t.run_for(kept_rows_step_ms)
      out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_said(t))
    }
    built.append(t.rows_built().filter(fn(b) { b.1 >= 0 }))
  }
  (out, built)
}

///|
test "a table dragged across and flung on 小屏: its message's row kept, drawn as building every row draws it" {
  let (kept, built) = table_slid(true)
  // (nothing of the list built for it: the rows drawn again, the table moved as they are painted)
  assert_eq(built, [])
  let (whole, _) = table_slid(false)
  assert_eq(kept.length(), whole.length())
  for k in 0..<kept.length() {
    assert_true(kept[k] == whole[k], msg="moment \{k} drawn otherwise kept than built")
  }
}

///|
test "a table dragged across on 小屏: it moves under the finger and back" {
  let t = kept_rows_open("chat-md", 390.0, 844.0)
  t.set_rows_on_pixels(true)
  t.drawn_again(true)
  let cell = "只排可见的行"
  let (x0, y) = t.drawn_of(cell).unwrap()
  // (held still at its end before it is let go: no fling)
  t.press_at(360.0, y)
  for step in 1..=8 {
    t.move_to(360.0 - step.to_double() * 40.0, y)
  }
  t.run_for(long_press_ms)
  t.release(40.0, y)
  t.run_for(kept_rows_step_ms)
  let (x1, _) = t.drawn_of(cell).unwrap()
  assert_true(x1 < x0, msg="\{Repr((x0, x1))}")
  t.press_at(40.0, y)
  for step in 1..=8 {
    t.move_to(40.0 + step.to_double() * 40.0, y)
  }
  t.run_for(long_press_ms)
  t.release(360.0, y)
  t.run_for(kept_rows_step_ms)
  let (x2, _) = t.drawn_of(cell).unwrap()
  assert_eq(x2, x0)
}


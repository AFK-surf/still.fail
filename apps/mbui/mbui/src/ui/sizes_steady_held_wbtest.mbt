// Sizes steady (sizes_steady.mbt) leaves out the frames drawn while the pointer is down, whoever holds the press: a node
// of the window's tree held and dragged goes as the hand has it, however far in one frame, as one of the old frame's
// does. Once let go, its frames are judged again: a step then is a fault.

///|
/// A handle of the tree's (200 wide, on a ground of its own: what sizes steady measures draws its own) at the top of a
/// window 400 by 300, as tall as `h` says; dragged, 100 tall while the finger is above 60 down the window, 180 below
/// it: one step of 80 in the frame the finger crosses. Sizes steady said but not held (its faults read here).
fn held_case(h : @signals.Signal[Double]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(200.0)))
      .height(By(fn() { Some(h.get()) }))
      .ground(Is(0x336699FFL))
      .presses(Is(true))
      .says(Is(Some(@view.said(Button, label="把手"))))
      .on_drag(fn(d) {
        if d.kind == Moved {
          h.set(if d.wy < 60.0 { 100.0 } else { 180.0 })
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// What sizes steady finds on the frame just drawn.
fn held_faults(t : Tester) -> Array[String] {
  g().sizes_steady_faults(t.fake.time, t.period)
}

///|
/// `frames` frames drawn one at a time, the display's; what sizes steady finds in each, gathered.
fn held_frames(t : Tester, frames : Int) -> Array[String] {
  let out = []
  for _ in 0..<frames {
    t.frame()
    out.append(held_faults(t))
  }
  out
}

///|
/// How many frames are drawn at rest before and after the drag (as many as sizes steady reads a way by).
let held_rest_frames : Int = 4

///|
test "sizes steady: a node of the tree's held and dragged, a step of 80 in one frame under the finger, none; let go, a step the next is one" {
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let t = held_case(h)
  let before = held_frames(t, held_rest_frames)
  // (the finger down at 20 and on to 100 a move a frame, 8 each: past 60 at the fifth, 80 taller at once)
  let held : Array[String] = []
  t.touch(0, 100.0, 20.0)
  for i in 1..=10 {
    t.hold_move(100.0, 20.0 + 8.0 * i.to_double())
    held.append(held_faults(t))
  }
  t.release(100.0, 100.0)
  let after = held_frames(t, held_rest_frames)
  // (let go, nobody holding it: 80 taller again in one frame)
  h.set(260.0)
  let stepped = held_frames(t, held_rest_frames)
  assert_eq((before, held, after), ([], [], []))
  assert_true(stepped.length() > 0, msg="a step once let go: none found")
}

// Sizes steady (sizes_steady.mbt) takes the frame a node of the tree's lays what it holds out at another width
// (View::lays_anew) as that node's step, for what it holds alone: what it holds comes out another height in that frame,
// as all of it does in the frame the window is made another size. Any other frame is judged as ever, and what is beside
// it is judged in that one too.

///|
/// A column 300 wide in a window 400 by 300 holding a box on a ground of its own (what sizes steady measures draws its
/// own), as tall as `h` says, saying it lays what it holds out at `laid` (View::lays_anew) where `says`; beside it, out of
/// the column, a box as tall as `beside` says. Sizes steady said but not held (its faults read here).
fn laid_case(
  h : @signals.Signal[Double],
  laid : @signals.Signal[Double],
  beside : @signals.Signal[Double],
  says : Bool,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(col) {
        col.width(Is(Some(300.0))) |> ignore
        if says {
          col.lays_anew(By(fn() { laid.get() })) |> ignore
        }
        col.box(fn(b) {
          b.width(Is(Some(200.0))).height(By(fn() { Some(h.get()) })).ground(Is(0x336699FFL)) |> ignore
        })
        |> ignore
      })
      |> ignore
      r.box(fn(b) {
        b.width(Is(Some(80.0))).height(By(fn() { Some(beside.get()) })).ground(Is(0x996633FFL)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// `frames` frames drawn one at a time, the display's; what sizes steady finds in each, gathered.
fn laid_frames(t : Tester, frames : Int) -> Array[String] {
  let out = []
  for _ in 0..<frames {
    t.frame()
    out.append(g().sizes_steady_faults(t.fake.time, t.period))
  }
  out
}

///|
test "sizes steady: what a column holds 80 taller in the frame it says it lays it out at another width, none; in a frame it says nothing, or one not saying it, a step is one; what is beside it stepping in that frame, one" {
  // (said: the width and the height step together, between frames, taken by the next frame's bindings)
  let h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let laid = @signals.signal(300.0, same=fn(a, b) { a == b })
  let beside = @signals.signal(100.0, same=fn(a, b) { a == b })
  let t = laid_case(h, laid, beside, true)
  let before = laid_frames(t, 4)
  laid.set(200.0)
  h.set(180.0)
  let at_step = laid_frames(t, 4)
  // (the width as it was, the height stepping again: a fault)
  h.set(260.0)
  let unsaid = laid_frames(t, 4)
  assert_eq((before, at_step), ([], []))
  assert_true(unsaid.length() > 0, msg="a step with the width as it was: none found")
  // (the same step where the column says nothing of its width: a fault)
  let h2 = @signals.signal(100.0, same=fn(a, b) { a == b })
  let t2 = laid_case(h2, @signals.signal(300.0), @signals.signal(100.0), false)
  laid_frames(t2, 4) |> ignore
  h2.set(180.0)
  assert_true(laid_frames(t2, 4).length() > 0, msg="a column saying nothing: none found")
  // (what is beside the column stepping in the frame its width steps: its own fault)
  let h3 = @signals.signal(100.0, same=fn(a, b) { a == b })
  let laid3 = @signals.signal(300.0, same=fn(a, b) { a == b })
  let beside3 = @signals.signal(100.0, same=fn(a, b) { a == b })
  let t3 = laid_case(h3, laid3, beside3, true)
  laid_frames(t3, 4) |> ignore
  laid3.set(200.0)
  h3.set(180.0)
  beside3.set(180.0)
  assert_true(laid_frames(t3, 4).length() > 0, msg="what is beside it stepping then: none found")
}

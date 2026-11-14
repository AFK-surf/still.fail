// A page's list held stretched at an end (Android's): a frame whose stretch differs from the one presented before tells
// the host the list drawn anew where it shows, none of its instances compared for how far it went (damage_known:
// Damage::step not known, the frame drawn at the display's every frame, as what scrolls is); held still there by a
// finger, nothing changes: no frame asked for after the one its move came in, nothing drawn again.

///|
/// Android's list of 12 rows 50 tall in a box 300 tall at the top of a phone's window (less than half of it, so what
/// changes in it is compared, not the window drawn whole), drawn.
fn stretch_tree() -> (Tester, @view.Scroll) {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, platform=2)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col
      .width(Is(Some(390.0)))
      .height(Is(Some(300.0)))
      .scrolls(s, fn(body) {
        for i in 0..<12 {
          body.box(fn(row) {
            row.height(Is(Some(50.0))).ground(Is(if i % 2 == 0 { 0x3366CCFFL } else { 0xEEEEEEFFL })).row(Is(true)) |> ignore
            row.box(fn(w) { w.words(Is("row \{i}")) |> ignore }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, s)
}

///|
test "Android: a page's list flung into its foot, its stretch changing: drawn anew where it shows, nothing compared for how far it went" {
  let (t, s) = stretch_tree()
  let tree = view_tree().unwrap()
  swipe(t, 280.0, -20.0, 12)
  let end = t.time() + 3000.0
  let mut was = 0.0
  let mut changed = 0
  let faults = []
  while t.time() < end {
    t.frame()
    let ov = s.past(tree)
    if ov != 0.0 && ov != was {
      changed = changed + 1
      if presented.step() is Some(st) {
        faults.push("at \{t.time()}, stretched \{ov} (\{was} before): compared, \{Repr(st)}")
      }
      if presented_share.val <= 0.0 {
        faults.push("at \{t.time()}, stretched \{ov} (\{was} before): nothing drawn again")
      }
    }
    was = ov
  }
  assert_true(changed > 5, msg="stretched otherwise in \{changed} frames")
  assert_eq(faults, [])
}

///|
test "Android: a page's list stretched at its foot and held there still by a finger: no frame asked for, nothing drawn again" {
  let (t, s) = stretch_tree()
  let tree = view_tree().unwrap()
  // (pulled up past its foot by a finger, and held where it is)
  t.touch(0, 200.0, 280.0)
  let mut y = 280.0
  for k in 1..=30 {
    t.advance(drag_step_ms)
    y = 280.0 - 20.0 * k.to_double()
    t.touch(1, 200.0, y)
    t.frames_owed()
  }
  let ov = s.past(tree)
  assert_true(ov < 0.0, msg="not past its foot: \{ov}")
  let faults = []
  for k in 0..<5 {
    let serial = frame_serial.val
    t.advance(drag_step_ms)
    t.touch(1, 200.0, y)
    t.frames_owed()
    if s.past(tree) != ov {
      faults.push("\{k}: stretched \{s.past(tree)}, held at \{ov}")
    }
    if frame_serial.val != serial && presented_share.val != 0.0 {
      faults.push("\{k}: \{presented_share.val} of the window drawn again")
    }
    match t.idle_said() {
      Some(why) => faults.push("\{k}: not at rest: \{why}")
      None => ()
    }
  }
  t.touch(2, 200.0, y)
  assert_eq(faults, [])
}

///|
/// stretch_tree's list flung into its foot: each frame till the first it shows past it, that one too (the run left there,
/// stretched as it is then), how far it shows past it, what the frame was compared to (Damage::step), how much of the
/// window was drawn again and why it was drawn whole, if it was.
fn stretch_flung_frames() -> Array[(Double, (Double, Double)?, Double, Int)] {
  let (t, s) = stretch_tree()
  let tree = view_tree().unwrap()
  swipe(t, 280.0, -20.0, 12)
  let end = t.time() + 3000.0
  let out = []
  while t.time() < end {
    t.frame()
    out.push((s.past(tree), presented.step(), presented_share.val, presented.why()))
    if s.past(tree) != 0.0 {
      break
    }
  }
  out
}

///|
test "Android: a page's list flung into its foot twice in one process, a Tester each, each run left stretched: each frame of the second told and drawn again as the first's" {
  // (read whole before the next Tester is made; the second's first stretch is the first's last: told all the same)
  let first = stretch_flung_frames()
  let second = stretch_flung_frames()
  assert_true(first.last().unwrap().0 != 0.0, msg="never stretched")
  assert_eq(first.last().unwrap().1, None)
  assert_eq(second, first)
}

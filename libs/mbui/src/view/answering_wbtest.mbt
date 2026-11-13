// What a part woken from rest finds changed comes at once (answering.mbt): a show, 30 tall over a line, in a part put to
// rest (View::rests) and woken; what it shows set while it rests is there as it wakes, no way in. The same set while it
// is awake makes its way in. At 7, 24, 60 and 120 frames a second.

///|
/// A part shown by `flag` in a column, rested at 50 where `rested`, the flag set at 60, woken at 200 (as nothing where
/// not rested): whether what the show made makes its way in.
fn woken_way(period : Double, rested : Bool) -> Bool {
  let clock = Ref(0.0)
  let flag = @signals.signal(false)
  let made : Ref[View?] = Ref(None)
  let part : Ref[View?] = Ref(None)
  let tree = Tree::new(time=fn() { clock.val }, fn(root) {
    root.box(fn(col) {
      col.box(fn(p) {
        part.val = Some(p)
        p.show(fn() { flag.get() }, fn(s) {
          made.val = Some(s)
          s.box(fn(b) { b.height(Is(Some(30.0))) |> ignore }) |> ignore
        })
        p.box(fn(line) { line.height(Is(Some(40.0))) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let frames_to = fn(until : Double) {
    while clock.val + period <= until {
      clock.val += period
      tree.frame(390.0, 844.0, now=clock.val) |> ignore
    }
  }
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  frames_to(50.0)
  clock.val = 50.0
  let wake = match (rested, part.val) {
    (true, Some(p)) => p.rests()
    _ => fn() {  }
  }
  let came = fn() {
    clock.val += period
    tree.frame(390.0, 844.0, now=clock.val) |> ignore
    match made.val {
      Some(v) => v.comes_end() >= 0.0
      None => false
    }
  }
  frames_to(60.0)
  clock.val = 60.0
  flag.set(true)
  if !rested {
    return came()
  }
  frames_to(200.0)
  clock.val = 200.0
  wake()
  came()
}

///|
test "answering: what a part woken from rest finds changed comes at once; set while awake it makes its way in" {
  for period in [1000.0 / 7.0, 1000.0 / 24.0, 1000.0 / 60.0, 1000.0 / 120.0] {
    assert_true(!woken_way(period, true), msg="at \{period} ms a frame: woken, it made its way in")
    assert_true(woken_way(period, false), msg="at \{period} ms a frame: awake, it came at once")
    assert_true(!answer_marks_left(), msg="at \{period} ms a frame: an answer's marks left set")
  }
}

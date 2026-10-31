// Rows steady (rows_steady.mbt) across the window made another size: what a list lays out anew for it is there at once,
// no move of its rows (measured anew from that frame); a row's height jumping with the window as it was is still a
// jolt, and so after the window changed, its rows measured on from there.

///|
/// A list of rows, the first 48.782 high in a window 400 wide and 52 in one wider (as a sidebar's head is on a tape and
/// off it), 30 higher once `jolted`; frames drawn each 16 ms for 640 ms, the window made 800 wide at `resize_at` and the
/// first row jolted at `jolt_at` (from the start, between frames; none: never): the jolts found.
fn rows_across_resize(resize_at : Double?, jolt_at : Double?) -> Int {
  let jolted = @signals.signal(false)
  let t = Tester::new(
    fn(c) {
      let wide = c.width > 600.0
      c.list(
        "rows",
        20,
        36.0,
        fn(k) {
          let h = if k == 0 {
            (if wide { 52.0 } else { 48.782 }) + (if jolted.get() { 30.0 } else { 0.0 })
          } else {
            36.0
          }
          c.box(w=Fill(1.0), h=Px(h), fn() { c.text("row \{k}", wrap=false) |> ignore }) |> ignore
        },
      )
      |> ignore
    },
    w=400.0,
    h=400.0,
  )
  // (each found counted, none failing this Tester: the file it was made in may show as many as it finds)
  rows_steady_bars[rows_steady.file] = 99
  let t0 = t.time()
  let mut resized = false
  let mut jumped = false
  while t.time() < t0 + 640.0 {
    let next = t.time() + 16.0
    match resize_at {
      Some(at) if !resized && t0 + at <= next => {
        resized = true
        t.advance(t0 + at - t.time())
        t.resize(800.0, 400.0)
        continue
      }
      _ => ()
    }
    match jolt_at {
      Some(at) if !jumped && t0 + at <= next => {
        jumped = true
        jolted.set(true)
      }
      _ => ()
    }
    t.frame_at(next)
  }
  rows_steady.found.length()
}

///|
test "rows steady: the window made another size as frames come, its rows laid out anew at once: no jolt" {
  assert_eq(rows_across_resize(Some(300.0), None), 0)
}

///|
test "rows steady: a row's height jumping, the window as it was: a jolt; and so after the window changed, measured on from there" {
  assert_true(rows_across_resize(None, Some(300.0)) > 0)
  assert_true(rows_across_resize(Some(200.0), Some(400.0)) > 0)
}

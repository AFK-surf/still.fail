// What a finger hides, for a loupe (loupe.mbt): where a finger reads, and a box showing the frame larger.

///|
test "a box magnified: what the frame drew round its point, larger, in it" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFFFFFFFFL, fn() {
        c.box(w=Px(20.0), h=Px(10.0), tx=190.0, ty=270.0, bg=0x336699FFL, fn() {  }) |> ignore
      })
      |> ignore
      c.layer(fn() { c.magnified(200.0, 275.0, 2.0, 120.0, 48.0) |> ignore }) |> ignore
    },
    w=400.0,
    h=400.0,
  )
  t.frame()
  let c = g()
  let mut copied = false
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 2] == 40.0 && c.inst[q + 3] == 20.0 {
      // (about the box's middle: its own middle where the point was)
      assert_eq(c.inst[q] + 20.0, 60.0)
      copied = true
    }
  }
  assert_true(copied)
}

///|
test "where a finger reads: none unless it drags what needs seeing" {
  let t = Tester::new(fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore }, w=400.0, h=400.0, platform=2)
  t.press_at(100.0, 100.0)
  assert_eq(g().finger_reads(), None)
  t.release(100.0, 100.0)
}

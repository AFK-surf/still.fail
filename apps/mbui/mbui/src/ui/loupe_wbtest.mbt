// The loupe (loupe.mbt): while a finger drags what asks for it, what is under the finger shown larger over it.

///|
/// Whether this frame draws the loupe's capsule: its ground, loupe_w by loupe_h.
fn loupe_drawn() -> Bool {
  let c = g()
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 5] == 0.0 && c.inst[q + 2] == loupe_w && c.inst[q + 3] == loupe_h {
      return true
    }
  }
  false
}

///|
test "a finger on what asks for the loupe: it grows out of it, what is under it larger in it; let go, gone back into it" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFFFFFFFFL, fn() {
        c.box(w=Px(20.0), h=Px(10.0), tx=190.0, ty=270.0, bg=0x336699FFL, fn() {  }) |> ignore
      })
      |> ignore
      if c.pointer().2 {
        c.loupe(reach=30.0)
      }
    },
    w=400.0,
    h=400.0,
    platform=2,
  )
  t.frame()
  assert_false(loupe_drawn())
  t.press_at(200.0, 305.0)
  t.frame()
  // (grown out of the finger on its spring, to its end)
  t.run_for(g().spring_rest("\u{2}loupe/grow") - t.time())
  t.frame()
  assert_true(loupe_drawn())
  // the box under the finger (30 over it, as asked), copied larger into the capsule over it
  let c = g()
  let mut copied = false
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 2] == 20.0 * loupe_zoom && c.inst[q + 3] == 10.0 * loupe_zoom {
      assert_true(c.inst[q + 1] < 305.0 - loupe_lift + loupe_h / 2.0)
      copied = true
    }
  }
  assert_true(copied)
  t.release(200.0, 305.0)
  t.frame()
  // (gone back into where the finger was)
  t.run_for(g().spring_rest("\u{2}loupe/grow") - t.time())
  t.frame()
  assert_false(loupe_drawn())
}

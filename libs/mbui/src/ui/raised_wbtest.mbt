// OverScrim (strata.mbt): what a modal layer is of, put over that layer's scrim and under what the layer holds (a row held for
// its menu, standing out of what the menu dims); where no layer with a scrim is up, in its place among the rest.

///|
/// Where in this frame's instances the first one `w` by `h` is (-1 none).
fn painted_at(w : Double, h : Double) -> Int {
  let c = g()
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 2] == w && c.inst[q + 3] == h {
      return k
    }
  }
  -1
}

///|
/// A page of a box 50 by 30 put over (z 3) and a box 70 by 40 after it, over both; with `menu` a modal layer over
/// them, its scrim and a panel 80 by 80 in it.
fn raised_page(menu : Bool) -> (Ctx) -> Unit {
  fn(c) {
    c.column(fn() {
      let b = c.box(w=Px(50.0), h=Px(30.0), bg=0x336699FFL, fn() {  })
      c.stratum(b, OverScrim)
      c.box(w=Px(70.0), h=Px(40.0), ty=-20.0, bg=0x993366FFL, fn() {  }) |> ignore
      if menu {
        c.overlay("menu", modal=true, scrim=0x00000040L, fn() {
          c.box(w=Px(80.0), h=Px(80.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
}

///|
test "what is put over a scrim is drawn over the modal layer's scrim and under what the layer holds" {
  let t = Tester::new(raised_page(true), w=400.0, h=300.0)
  t.frame()
  let scrim = painted_at(400.0, 300.0)
  let raised = painted_at(50.0, 30.0)
  let panel = painted_at(80.0, 80.0)
  let after = painted_at(70.0, 40.0)
  assert_true(scrim >= 0 && raised >= 0 && panel >= 0 && after >= 0)
  assert_true(after < scrim)
  assert_true(scrim < raised)
  assert_true(raised < panel)
}

///|
test "with no scrim up, what is put over one is drawn in its place" {
  let t = Tester::new(raised_page(false), w=400.0, h=300.0)
  t.frame()
  let raised = painted_at(50.0, 30.0)
  let after = painted_at(70.0, 40.0)
  assert_true(raised >= 0 && after >= 0)
  assert_true(raised < after)
}

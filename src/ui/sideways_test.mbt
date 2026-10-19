// What scrolls inside a list (sideways.mbt), a node drawn as its top only (draw.mbt). The fake host makes Latin 5 px
// wide at size 10.

///|
/// A list of rows, the second holding a line 600 wide that scrolls sideways.
fn sideways_view(at : Ref[Double]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.list("rows", 30, 40.0, fn(i) {
        if i == 1 {
          // where it is scrolled to, read where it is built (its key is the row's)
          at.val = c.sideways_at("wide")
          c.sideways("wide", fn() {
            c.rich([@ui.plain("x".repeat(120))], size=10.0, wrap=false) |> ignore
          })
          |> ignore
        } else {
          c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "sideways: what it holds is laid out as wide as it is, cut to the box" {
  let t = sideways_view(Ref::new(0.0))
  t.draw()
  let (_, _, w, _) = t.rect_of("xxxx").unwrap()
  assert_eq(w, 600.0)
}

///|
test "sideways: a finger moving sideways drags it; up or down, the list scrolls" {
  let at = Ref::new(0.0)
  let t = sideways_view(at)
  t.draw()
  let (_, y, _, _) = t.rect_of("xxxx").unwrap()
  t.drag(250.0, y + 5.0, 50.0, y + 5.0)
  t.draw()
  let was = at.val
  assert_true(was > 150.0)
  assert_eq(t.list_offset(), 0.0)
  t.drag(250.0, y + 5.0, 250.0, y - 115.0)
  t.draw()
  assert_true(t.list_offset() > 80.0)
}

///|
test "sideways: it stops at its ends" {
  let at = Ref::new(0.0)
  let t = sideways_view(at)
  t.draw()
  let (_, y, _, _) = t.rect_of("xxxx").unwrap()
  t.drag(50.0, y + 5.0, 250.0, y + 5.0)
  t.draw()
  assert_eq(at.val, 0.0)
  for _ in 0..<4 {
    t.drag(280.0, y + 5.0, 20.0, y + 5.0)
    t.draw()
  }
  t.frame()
  assert_eq(at.val, 300.0)
}

///|
test "a node drawn as its top only: its bottom cut, its taps whole" {
  let cut = Ref::new(-1.0)
  let t = @ui.Tester::new(
    fn(c) {
      let b = c.box(w=Px(100.0), h=Px(100.0), fn() {
        c.box(w=Px(100.0), h=Px(30.0), fn() {  }) |> ignore
        c.box(w=Px(100.0), h=Px(30.0), bg=0x55667788L, fn() {  }) |> ignore
      })
      if cut.val >= 0.0 {
        c.cut_to_top(b, cut.val)
      }
    },
    w=300.0,
    h=300.0,
  )
  t.frame()
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x55667788L }).length(), 1)
  cut.val = 20.0
  t.frame()
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x55667788L }).length(), 0)
}


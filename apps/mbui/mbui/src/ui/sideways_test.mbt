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
test "sideways: flung, it slows by a way solved once: at rest at a time of its own, the same at any frame rate" {
  let run = fn(step : Double) -> (Double, Double) raise {
    let at = Ref::new(0.0)
    let t = sideways_view(at)
    t.draw()
    let (_, y, _, _) = t.rect_of("xxxx").unwrap()
    // a quick move left, let go: flung on
    t.drag(280.0, y + 5.0, 200.0, y + 5.0, steps=2)
    let rest = t.rest_of("a fling")
    assert_true(rest > t.time() && rest < @double.infinity)
    let mid = t.time() + 100.0
    while t.time() + step < mid {
      t.frame(ms=step)
    }
    t.frame(ms=mid - t.time())
    let x_mid = at.val
    t.run_for(rest - t.time())
    t.draw()
    let x_end = at.val
    t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
    assert_eq(at.val, x_end)
    t.assert_idle()
    (x_mid, x_end)
  }
  let (m8, e8) = run(8.0)
  let (m16, e16) = run(16.0)
  assert_eq(m8, m16)
  assert_eq(e8, e16)
  assert_true(e16 > m16)
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


///|
test "sideways: a row in it is as wide as what it holds, not squeezed to the box (a toolbar's chips beside its tools)" {
  let t = @ui.Tester::new(
    fn(c) {
      // a bar 200 wide: the chips scroll sideways in what the tools (100) leave
      c.box(dir=Row, w=Px(200.0), h=Px(40.0), fn() {
        c.sideways("chips", w=Fill(1.0), fn() {
          c.box(dir=Row, gap=2.0, fn() {
            for k in 0..<6 {
              c.box(padx=13.0, fn() { c.text("ab\{k}", size=10.0, wrap=false) |> ignore }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
        c.box(w=Px(100.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=300.0,
  )
  t.draw()
  // each chip its words (15) and its sides (13 each), 2 apart: 43 from one to the next, as with room for all
  let (x0, _, w0, _) = t.rect_of("ab0").unwrap()
  let (x1, _, _, _) = t.rect_of("ab1").unwrap()
  let (x5, _, _, _) = t.rect_of("ab5").unwrap()
  assert_eq(w0, 15.0)
  assert_eq(x1 - x0, 43.0)
  assert_eq(x5 - x0, 215.0)
}

///|
test "sideways across rows: a long text's rows scroll as one, as far as the widest of them" {
  let at = Ref::new(0.0)
  let words = ["a".repeat(120), "b".repeat(80), "c".repeat(40)]
  let t = @ui.Tester::new(
    fn(c) {
      c.list("rows", 3, 40.0, fn(i) {
        at.val = c.sideways_at("code", across=true)
        c.sideways("code", across=true, fn() {
          // 600, 400 and 200 wide
          c.rich([@ui.plain(words[i])], size=10.0, wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  // the narrowest row dragged: they all go, as far as the widest's end (600 in 300)
  let (_, y, _, _) = t.rect_of(words[2]).unwrap()
  t.drag(250.0, y + 5.0, 0.0, y + 5.0)
  t.drag(250.0, y + 5.0, 0.0, y + 5.0)
  t.draw()
  assert_eq(at.val, 300.0)
  // each row drawn as far to the left
  let (x0, _, _, _) = t.rect_of(words[0]).unwrap()
  let (x2, _, _, _) = t.rect_of(words[2]).unwrap()
  assert_eq(x0, -300.0)
  assert_eq(x2, -300.0)
}

///|
test "sideways to its end: a path's end in view as it is first laid out and as it goes deeper, where it was left between" {
  let path = Ref::new("a".repeat(100))
  let at = Ref::new(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      at.val = c.sideways_at("way")
      c.sideways("way", to_end=path.val, fn() { c.rich([@ui.plain(path.val)], size=10.0, wrap=false) |> ignore })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  t.draw()
  // 500 wide in 300: at its end, in the frame it is first laid out
  assert_eq(at.val, 200.0)
  path.val = "a".repeat(100) + "b".repeat(40)
  t.draw()
  assert_eq(at.val, 400.0)
}

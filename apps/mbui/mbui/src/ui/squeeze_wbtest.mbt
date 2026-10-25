// Short of room (docs/style.md): what holds its size, what gives way and how, and what Tester::squeeze_faults says.

///|
/// Box `id` as the last frame laid it out (x, y, w, h) and how it shows (its opacity).
fn laid_box(id : Int) -> (Double, Double, Double, Double, Double) {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.id == id {
      return (n.x, n.y, n.fw, n.fh, n.opacity)
    }
  }
  abort("no box \{id}")
}

///|
test "a box sized by what it holds is never laid narrower than that in a short row: what does not fit lies past it" {
  let ids = Ref((0, 0))
  let t = Tester::new(
    fn(c) {
      let a = c.id("a")
      let b = c.id("b")
      ids.val = (a, b)
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        c.box(dir=Row, id=a, taps=false, fn() {
          c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
          c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
        })
        |> ignore
        c.box(dir=Row, id=b, taps=false, fn() { c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (a, b) = ids.val
  let (_, _, aw, _, _) = laid_box(a)
  let (bx, _, bw, _, _) = laid_box(b)
  assert_eq(aw, 80.0)
  assert_eq(bw, 40.0)
  assert_eq(bx, 80.0)
}

///|
test "a row leaves out what it may, the lowest drop first, and shows its ⋯ only while it does" {
  let ids : Ref[Array[Int]] = Ref([])
  let width = Ref(100.0)
  let t = Tester::new(
    fn(c) {
      let x = c.id("x")
      let y = c.id("y")
      let m = c.id("more")
      ids.val = [x, y, m]
      c.box(dir=Row, w=Px(width.val), h=Px(20.0), fn() {
        c.box(w=Px(60.0), h=Px(20.0), fn() {  }) |> ignore
        c.box(w=Px(30.0), h=Px(20.0), id=x, taps=false, drop=2, fn() {  }) |> ignore
        c.box(w=Px(30.0), h=Px(20.0), id=y, taps=false, drop=1, fn() {  }) |> ignore
        c.box(w=Px(20.0), h=Px(20.0), id=m, taps=false, more=true, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (x, y, m) = (ids.val[0], ids.val[1], ids.val[2])
  // 60 + 30 + 30 is more than 100: the ⋯ comes (20), y goes (the lowest), then x; 60 and the ⋯ are left
  assert_eq(laid_box(y).4, 0.0)
  assert_eq(laid_box(x).4, 0.0)
  let (mx, _, mw, _, mo) = laid_box(m)
  assert_eq((mx, mw, mo), (60.0, 20.0, 1.0))
  // with the room for all of them, none goes and there is no ⋯
  width.val = 200.0
  t.frame()
  assert_eq(laid_box(x).4, 1.0)
  assert_eq(laid_box(y).4, 1.0)
  assert_eq(laid_box(m).2, 0.0)
  assert_eq(laid_box(m).4, 0.0)
}

///|
test "what a row left out is said as it is built (Ctx::left_out), in the same frame" {
  let said : Ref[Bool?] = Ref(None)
  let t = Tester::new(
    fn(c) {
      let x = c.id("x")
      c.box(dir=Row, w=Px(50.0), h=Px(20.0), fn() {
        c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
        c.box(w=Px(40.0), h=Px(20.0), id=x, taps=false, drop=1, fn() {  }) |> ignore
      })
      |> ignore
      said.val = Some(c.left_out(x))
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  assert_eq(said.val, Some(true))
}

///|
test "words said to be cut (Cut) are as wide as they are, and cut with an ellipsis where the row has less" {
  let ids = Ref(0)
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        let i = c.text("words longer than the row has room for", w=Cut, wrap=false)
        ids.val = i
        c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let n = g().nodes[ids.val]
  assert_eq(n.fw, 60.0)
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "squeeze_faults: what a box that takes its room squeezes lies over what is beside it" {
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        c.box(dir=Row, w=Fill(1.0), fn() { c.box(w=Px(80.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore })
        |> ignore
        c.box(w=Px(50.0), h=Px(20.0), bg=0x00FF00FFL, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("overlap by 30"), msg=faults[0])
}

///|
test "squeeze_faults: words wrapped narrower than a word of them (broken inside it) are squeezed; wrapped between words they are not" {
  let narrow = Ref(30.0)
  let t = Tester::new(
    fn(c) { c.box(w=Px(narrow.val), fn() { c.text("Studio settings", size=14.0) |> ignore }) |> ignore },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("wrapped"), msg=faults[0])
  narrow.val = 80.0
  t.frame()
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "a row leaves out what it may before words cut short in it go under four of their size; then they take its room" {
  let ids = Ref((0, 0))
  let t = Tester::new(
    fn(c) {
      let d = c.id("d")
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        let i = c.text("words much longer than the row", size=10.0, w=Cut, wrap=false)
        c.box(w=Px(70.0), h=Px(20.0), id=d, taps=false, drop=1, fn() {  }) |> ignore
        ids.val = (i, d)
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (i, d) = ids.val
  // (70 beside them would leave the words 30, less than four of their 10)
  assert_eq(laid_box(d).4, 0.0)
  assert_eq(g().nodes[i].fw, 100.0)
}

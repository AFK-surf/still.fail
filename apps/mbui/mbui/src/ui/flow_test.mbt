// A row that goes on in lines (Ctx::box `flow`: Compose's FlowRow) and a box that keeps its width in a row short of
// room (`keep`: what has no weight in Compose's Row).

///|
test "a flow: what does not fit the line goes on the next, each as wide as it is, gap apart and line_gap between" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), gap=8.0, flow=true, line_gap=4.0, fn() {
        for k in 0..<3 {
          c.box(w=Px(40.0), h=Px(20.0), fn() { c.text("chip\{k}", wrap=false) |> ignore }) |> ignore
        }
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  let (x0, y0, w0, _) = t.rect_of("chip0").unwrap()
  let (x1, y1, _, _) = t.rect_of("chip1").unwrap()
  let (x2, y2, _, _) = t.rect_of("chip2").unwrap()
  assert_eq(x0, 0.0)
  assert_eq(x1, 48.0)
  assert_eq(y1, y0)
  // 40 + 8 + 40 + 8 + 40 > 100: the third on a line of its own, 20 + 4 down
  assert_eq(x2, 0.0)
  assert_eq(y2, y0 + 24.0)
  assert_true(w0 <= 40.0)
}

///|
test "one of: ways of saying one thing, the first that fits the room whole shown, the last where none does, the rest drawn nowhere" {
  let room = Ref(200.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(room.val), one_of=true, fn() {
        for way in [("long", 120.0), ("mid", 70.0), ("short", 30.0)] {
          c.box(dir=Row, w=Px(way.1), h=Px(20.0), fn() { c.text(way.0, wrap=false) |> ignore }) |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  let shown = fn() {
    t.words().filter(fn(w) { w.5 > 0.5 }).map(fn(w) { w.0 })
  }
  t.draw()
  assert_eq(shown(), ["long"])
  room.val = 100.0
  t.frame()
  assert_eq(shown(), ["mid"])
  room.val = 50.0
  t.frame()
  assert_eq(shown(), ["short"])
  // (none fits: the last, the shortest)
  room.val = 10.0
  t.frame()
  assert_eq(shown(), ["short"])
  // (what it shows where it would be, at its start)
  room.val = 100.0
  t.frame()
  let (x, _, w, _) = t.rect_of("mid").unwrap()
  assert_eq(x, 0.0)
  assert_true(w <= 70.0)
}

///|
test "kept: a box in a row short of room keeps its width, its sibling cut short" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), fn() {
        c.box(clip=true, fn() { c.text("a long title that does not fit", wrap=false) |> ignore }) |> ignore
        c.box(keep=true, fn() { c.text("button", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  let (bx, _, bw, _) = t.rect_of("button").unwrap()
  // the button whole, at the row's end
  assert_true((bx + bw - 100.0).abs() < 0.5)
}

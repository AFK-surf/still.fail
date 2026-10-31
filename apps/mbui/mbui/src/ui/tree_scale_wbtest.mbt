// A node of the window's tree drawn bigger or smaller (View::scale), what it holds with it: drawn, pressed, taken and
// read out where it is drawn, as big (one projection: Tree::projected); its scale changed, composed again only (no
// instance made again, its words, its icon).

///|
/// A holder 200 by 100 at (20, 20) drawn `s` as big about its top left, holding a button 100 by 50 at its right (taking
/// a finger only on its left half, View::takes), an icon under it, and a plain one taking presses below them: how
/// many times each was pressed.
fn scaled_tester(s : @signals.Signal[Double], pressed : Map[String, Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  t.check_looks(false)
  let count = fn(k : String) { pressed[k] = pressed.get(k).unwrap_or(0) + 1 }
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      h.box(fn(b) {
        b
        .over(Is(true))
        .offset(Is((100.0, 0.0)))
        .width(Is(Some(100.0)))
        .height(Is(Some(50.0)))
        .ground(Is(0x3366CCFFL))
        .words(Is("go"))
        .says(Is(Some(@view.said(Button, label="node button"))))
        .takes(fn(w, h, _) { [(0.0, 0.0, w / 2.0, h)] })
        .on_press(fn() { count("node") })
        |> ignore
      })
      |> ignore
      // (a plain one below them, taking presses wherever it is drawn: laid out at (170, 120) 100 by 50, drawn at
      // (95, 70) 50 by 25)
      h.box(fn(p) {
        p.over(Is(true)).offset(Is((150.0, 100.0))).width(Is(Some(100.0))).height(Is(Some(50.0))).on_press(fn() { count("plain") }) |> ignore
      })
      |> ignore
      h.box(fn(i) {
        i
        .over(Is(true))
        .offset(Is((100.0, 60.0)))
        .width(Is(Some(20.0)))
        .height(Is(Some(20.0)))
        .shapes(Is([shape_of([([0.0, 0.0, 20.0, 0.0, 20.0, 20.0], true)], fill=0xCC3333FFL)]))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "scale: a node drawn half as big, what it holds pressed, taken and read out where it is drawn, as big; nothing where it is laid out but not drawn" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = scaled_tester(s, pressed)
  // (the button laid out at (120, 20) 100 by 50, drawn at (70, 20) 50 by 25)
  assert_eq(t.get(Button, label="node button").rect, (70.0, 20.0, 50.0, 25.0), msg="read out where it is drawn")
  t.tap(80.0, 30.0)
  assert_eq(pressed.get("node"), Some(1), msg="pressed where it is drawn, its left half")
  t.tap(110.0, 30.0)
  assert_eq(pressed.get("node"), Some(1), msg="its right half drawn: takes none, as it says")
  t.tap(150.0, 30.0)
  assert_eq(pressed.get("node"), Some(1), msg="where it is laid out but not drawn: nothing")
  t.tap(180.0, 100.0)
  assert_eq(pressed.get("plain"), None, msg="a plain node where it is laid out but not drawn: nothing")
  t.tap(130.0, 80.0)
  assert_eq(pressed.get("plain"), Some(1), msg="a plain node where it is drawn")
  // (another scale: composed again, nothing made again)
  let made = view_paint_work.made
  let copied = view_paint_work.copied
  s.set(0.8)
  t.draw()
  assert_eq(view_paint_work.made, made, msg="nothing made again")
  assert_true(view_paint_work.copied > copied, msg="composed again")
  assert_eq(t.get(Button, label="node button").rect, (100.0, 20.0, 80.0, 40.0), msg="read out where it is drawn now")
  t.tap(110.0, 30.0)
  assert_eq(pressed.get("node"), Some(2), msg="pressed where it is drawn now")
}

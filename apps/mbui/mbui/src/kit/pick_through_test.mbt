// Words picked by a finger held still on a cover of the window's tree over them, its hold handed through to them
// (View::gesture's `through`): as with no cover, frames drawn between or none.

///|
let pick_later_ms : Double = 100.0

///|
/// Words in an old view, a cover of the tree's over them holding through; a finger held still on the first word past a
/// long press and let go, frames drawn as it is held or (`frames` false) none between its down and its up. What was
/// picked then, and what the cover was told.
fn picked_through(frames : Bool) -> ((Int, Int, Bool), Array[String]) {
  let p = @kit.Pick::new()
  let said : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      @ui.old(b, fn(c) {
        let id = c.id("w")
        c.takes_presses(id)
        let box = c.box(id~, fn() { c.rich([@ui.plain("alpha beta gamma delta")], wrap=false) |> ignore })
        c.words(box, "w", a=p.a, b=p.b, color=0x3B82F640L)
        if p.hold(c, "w", id) {
          c.take_press()
        }
        p.slide(c)
      })
      .over(Is(true))
      |> ignore
      b.box(fn(cv) {
        cv
        .over(Is(true))
        .width(Is(Some(400.0)))
        .height(Is(Some(200.0)))
        .gesture(
          @ui.touch_slop(),
          press=fn(_) { said.push("cover press") },
          tap=fn(_) { said.push("cover tap") },
          drag=fn(d) { said.push("cover drag \{d.kind}") },
          through=@ui.long_press_ms,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (rx, ry, _, rh) = t.rect_of("alpha beta gamma delta").unwrap()
  let (x, y) = (rx + 4.0, ry + rh / 2.0)
  t.touch(0, x, y)
  if frames {
    t.draw()
    t.run_for(@ui.long_press_ms + pick_later_ms)
  } else {
    t.advance(@ui.long_press_ms + pick_later_ms)
  }
  t.touch(2, x, y)
  t.draw()
  ((p.a, p.b, p.of("w")), said)
}

///|
test "words under a cover holding through, held still past a long press and let go: the word under the finger picked, the cover's hold called off (no tap); with no frame between its down and its up, the same" {
  let want = ((0, 5, true), ["cover press", "cover drag Off"])
  assert_eq(picked_through(true), want, msg="frames between")
  assert_eq(picked_through(false), want, msg="no frame between")
}

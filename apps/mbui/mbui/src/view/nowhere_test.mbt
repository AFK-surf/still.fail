// A node laid out nowhere (View::laid_nowhere): it and all it holds out of the scene, of what is pressed (by a finger,
// by its id, by a screen reader) and of what is read out, a press held on it called off, and none of the gap what holds
// it leaves; back, the same nodes, as big as they were.

///|
test "laid nowhere: a box holding a coloured box, words and a button: none of it drawn, read out or pressed by its id or by a screen reader, no gap left for it; a finger held on its button called off then; back, the same nodes as big as they were, pressed again" {
  let nowhere = @signals.signal(false, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let pressed = Ref(0)
  let seen : Array[@view.Drag] = []
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.over(Is(true)).gap(Is(12.0)) |> ignore
        col.box(fn(a) { a.height(Is(Some(10.0))) |> ignore }) |> ignore
        col.box(fn(v) {
          ids["box"] = v.id()
          v.laid_nowhere(By(fn() { nowhere.get() })) |> ignore
          v.box(fn(g) {
            ids["ground"] = g.id()
            g.width(Is(Some(40.0))).height(Is(Some(20.0))).ground(Is(0x3366CCFFL)) |> ignore
          })
          |> ignore
          v.box(fn(w) {
            ids["words"] = w.id()
            w.words(Is("Join"), look={ size: 15.0, weight: 400, line: 20.0, wrap: false }) |> ignore
          })
          |> ignore
          v.box(fn(b) {
            ids["button"] = b.id()
            b
            .width(Is(Some(80.0)))
            .height(Is(Some(30.0)))
            .presses(Is(true))
            .says(Is(Some(@view.said(Button, label="Go"))))
            .on_press(fn() { pressed.val = pressed.val + 1 })
            .on_drag(fn(d) { seen.push(d) })
            |> ignore
          })
          |> ignore
        })
        |> ignore
        col.box(fn(z) {
          ids["after"] = z.id()
          z.height(Is(Some(10.0))) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let mine = ["ground", "words", "button"]
  let drawn = fn() { mine.filter(fn(k) { t.drawn_of(ids[k]) is Some(_) }) }
  let said = fn() { t.said_order().iter().any(fn(s) { s.id == ids["button"] }) }
  let after_y = fn() { t.drawn_of(ids["after"]).map(fn(d) { d.y }) }
  let sizes = fn() { mine.map(fn(k) { t.drawn_of(ids[k]).map(fn(d) { (d.w, d.h) }) }) }
  let before = (drawn(), said(), after_y(), sizes())
  // (a finger held on its button as it is laid out nowhere)
  t.drag_at(ids["button"], Down, 20.0, 70.0, 10.0) |> ignore
  t.event(20.0, fn() { nowhere.set(true) })
  t.frame(400.0, 300.0) |> ignore
  let gone = (
    drawn(),
    said(),
    after_y(),
    t.reads_out(ids["button"]),
    t.run_press_at(ids["button"], 30.0),
    t.activate_at(ids["button"], 30.0),
    seen.map(fn(d) { d.kind == Off }),
  )
  t.drag_at(ids["button"], Up, 20.0, 70.0, 40.0) |> ignore
  t.event(50.0, fn() { nowhere.set(false) })
  t.frame(400.0, 300.0) |> ignore
  let back = (drawn(), said(), after_y(), sizes() == before.3, t.run_press_at(ids["button"], 60.0))
  // (its ground and its button as big as they say; its words as big as they were: as wide as what holds it, a line of them tall)
  let said_sizes = (before.3[0], before.3[2])
  assert_eq(
    (before.0, before.1, before.2, said_sizes, gone, back, pressed.val, seen.length()),
    (
      mine,
      true,
      Some(10.0 + 12.0 + 20.0 + 18.0 + 30.0 + 12.0),
      (Some((40.0, 20.0)), Some((80.0, 30.0))),
      ([], false, Some(10.0 + 12.0), false, false, false, [false, true]),
      (mine, true, Some(10.0 + 12.0 + 20.0 + 18.0 + 30.0 + 12.0), true, true),
      1,
      2,
    ),
    msg="\{before} \{gone} \{back}",
  )
}

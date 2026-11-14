// What goes beside another as wide as it (View::beside's `width=Anchor`: Tree::beside_widened): as wide as its anchor is
// laid out from the first frame it is drawn in, what it holds made by that width (View::by_room), following the anchor's
// width in the frame it changes and nothing laid out after; as wide as what it holds where it says nothing so, as before.

///|
/// An anchor `aw` wide (or, where `other`, a second anchor 260 wide instead), at (40, 40), 20 high, its box drawn
/// `grow` as big about its top left; beside it below, a panel holding a box 50 by 30 and, where `room`, a box made by its
/// room (the widths it was given, in `rooms`), as wide as its anchor where `wide` (and `own` does not say otherwise
/// now); where `presses`, the panel pressed counted in its first, a box over all of the window under it in its second.
/// The panel's node.
fn widened_tester(
  aw : @signals.Signal[Double],
  rooms : Array[Double],
  wide? : Bool = true,
  own? : @signals.Signal[Bool] = @signals.signal(false),
  presses? : Ref[(Int, Int)],
  room? : Bool = true,
  other? : @signals.Signal[Bool] = @signals.signal(false),
  grow? : (@view.View) -> Double = fn(_) { 1.0 },
) -> (Tester, Ref[@view.NodeId?]) {
  let t = Tester::new(fn(_c) {  }, w=600.0, h=400.0)
  // (each frame drawn in part drawn whole after it as well and the two compared: on in every Tester, said here)
  t.check_looks(true)
  let panel : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    let first : Ref[@view.NodeId?] = Ref(None)
    match presses {
      Some(n) =>
        root.box(fn(u) {
          u
          .over(Is(true))
          .presses(Is(true))
          .says(Is(Some(@view.said(Button, label="under"))))
          .on_press(fn() { n.val = (n.val.0, n.val.1 + 1) })
          |> ignore
        })
        |> ignore
      None => ()
    }
    root.box(fn(h) {
      h.over(Is(true)).scale(By(fn() { grow(h) }), about=At(0.0, 0.0)) |> ignore
      h.box(fn(a) {
        first.val = Some(a.id())
        a.over(Is(true)).offset(Is((40.0, 40.0))).width(By(fn() { Some(aw.get()) })).height(Is(Some(20.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
    let second = root.box(fn(a) {
      a.over(Is(true)).offset(Is((40.0, 200.0))).width(Is(Some(260.0))).height(Is(Some(20.0))) |> ignore
    })
    root.box(fn(l) {
      l.over(Is(true)) |> ignore
      l.box(fn(p) {
        panel.val = Some(p.id())
        let anchor = fn(o : Bool) { if o { second.id() } else { first.val.unwrap() } }
        p.reacts(fn() { (other.get(), own.get()) }, fn(said) {
          let (o, mine) = said
          p.beside(anchor(o), side=Bottom, along=Start, offset=6.0, width=if wide && !mine { Anchor } else { Own }) |> ignore
        })
        match presses {
          Some(n) =>
            p
            .presses(Is(true))
            .says(Is(Some(@view.said(Button, label="panel"))))
            .on_press(fn() { n.val = (n.val.0 + 1, n.val.1) })
            |> ignore
          None => ()
        }
        p.box(fn(b) { b.width(Is(Some(50.0))).height(Is(Some(30.0))) |> ignore }) |> ignore
        if room {
          p.by_room(fn(held, room) {
          held.box(fn(c) {
            c
            .height(Is(Some(10.0)))
            .width(By(fn() {
              rooms.push(room.width())
              Some(room.width() / 2.0)
            }))
            |> ignore
          })
          |> ignore
        })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, panel)
}

///|
/// How wide and where node `id` is drawn.
fn drawn_box(id : Ref[@view.NodeId?]) -> (Double, Double, Double) {
  match view_app.val.bind(fn(tree) { tree.drawn_of(id.val.unwrap()) }) {
    Some(d) => (d.x, d.y, d.w)
    None => (-1.0, -1.0, -1.0)
  }
}

///|
test "beside as wide as its anchor: in the first frame it is drawn, its anchor's 200 (not its own 50), what it holds made by that room; one saying nothing as wide as what it holds, as before" {
  let rooms : Array[Double] = []
  let (_, p) = widened_tester(@signals.signal(200.0), rooms)
  assert_eq(drawn_box(p), (40.0, 66.0, 200.0))
  assert_eq(rooms.last(), Some(200.0))
  let (_, own) = widened_tester(@signals.signal(200.0), [], wide=false, room=false)
  assert_eq(drawn_box(own), (40.0, 66.0, 50.0))
  // (saying nothing, with what is made by its room in it: as wide as it was before there was a width to say, 300)
  let (_, own) = widened_tester(@signals.signal(200.0), [], wide=false)
  assert_eq(drawn_box(own), (40.0, 66.0, 300.0))
}

///|
test "beside as wide as its anchor: the anchor 200, 260, then 200 again: in the frame each comes, as wide, nothing laid out after it (the tree at rest)" {
  let aw = @signals.signal(200.0)
  let rooms : Array[Double] = []
  let (t, p) = widened_tester(aw, rooms)
  t.assert_idle()
  for w in [260.0, 200.0, 260.0] {
    aw.set(w)
    t.frame()
    assert_eq(drawn_box(p), (40.0, 66.0, w), msg="\{w}")
    assert_eq(rooms.last(), Some(w), msg="\{w}")
    t.assert_idle()
  }
}

///|
test "beside as wide as its anchor, the same panel beside one anchor then another: as wide as each, back as wide as the first" {
  let other = @signals.signal(false)
  let (t, p) = widened_tester(@signals.signal(200.0), [], other~)
  assert_eq(drawn_box(p), (40.0, 66.0, 200.0))
  other.set(true)
  t.frame()
  assert_eq(drawn_box(p), (40.0, 226.0, 260.0))
  other.set(false)
  t.frame()
  assert_eq(drawn_box(p), (40.0, 66.0, 200.0))
  t.assert_idle()
}

///|
/// How long the anchor's box takes to grow to its whole size.
// kept across runs: a value
let grow_ms : Double = 300.0

///|
test "beside as wide as its anchor, the anchor's box growing from half as big (its look, drawn): as wide as the anchor is laid out all the way, at any rate of frames" {
  let (t, p) = widened_tester(@signals.signal(200.0), [], grow=fn(h) {
    let at = h.drawn_while(fn(now) { now < grow_ms })
    if at >= grow_ms {
      1.0
    } else {
      0.5 + 0.5 * at / grow_ms
    }
  })
  t.run_for(grow_ms / 2.0)
  assert_eq(drawn_box(p).2, 200.0)
  t.run_for(grow_ms)
  assert_eq(drawn_box(p), (40.0, 66.0, 200.0))
}

///|
test "beside as wide as its anchor: in the frame the anchor goes from 200 to 260, a press between the two lands on it, not on what is under it" {
  let aw = @signals.signal(200.0)
  let presses = Ref((0, 0))
  let (t, p) = widened_tester(aw, [], room=false, presses~)
  aw.set(260.0)
  // (the frame it widens in, then the press on what that frame placed)
  t.frame()
  t.tap(40.0 + 230.0, 66.0 + 15.0)
  assert_eq(drawn_box(p).2, 260.0)
  assert_eq(presses.val, (1, 0))
}

///|
test "beside as wide as its anchor, then saying nothing: in the next frame as wide as what it holds again" {
  let own = @signals.signal(false)
  let (t, p) = widened_tester(@signals.signal(200.0), [], room=false, own~)
  assert_eq(drawn_box(p).2, 200.0)
  own.set(true)
  t.frame()
  assert_eq(drawn_box(p), (40.0, 66.0, 50.0))
  t.assert_idle()
}

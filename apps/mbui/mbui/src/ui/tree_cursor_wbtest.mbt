// The pointer's shape where the window is a tree (view_host.mbt view_cursor_tell): a node's of what the pointer is over
// (what it says, else a hand where a press on it does something), the old views' over theirs, the one a press is held
// by while held; told as the pointer moves, and as what a still pointer is over changes, at no frame of a test's.

///|
/// In a row: a tree button "B" (a hand, said nothing), an edge "E" 10 wide (dragged, its shape `edge`), and an old view
/// with a button of its own (its hand); over the old view's button, while `cover`, a ground of the tree's taking presses,
/// said to be the arrow. "B" taking presses while `b_on`. Over all of it while `layer`, a layer of the old frame's.
fn shaped_tester(
  edge : @signals.Signal[Cursor?],
  cover : @signals.Signal[Bool],
  b_on : @signals.Signal[Bool],
  layer? : @signals.Signal[Bool] = @signals.signal(false),
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(By(fn() { b_on.get() }))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    root.box(fn(e) {
      e.width(Is(Some(10.0))).height(Is(Some(40.0))).cursor(By(fn() { edge.get() })).on_drag(fn(_) {  }) |> ignore
    })
    |> ignore
    root.box(fn(h) {
      h.width(Is(Some(200.0))) |> ignore
      old(h, fn(c) {
        let id = c.id("old button")
        c.clicked(id) |> ignore
        c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
        // (a layer of the old frame's over all of the window, taking no press itself, while `layer`)
        if layer.get() {
          c.overlay("sheet", modal=true, fn() { c.box(w=Px(400.0), h=Px(200.0), fn() {  }) |> ignore }) |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
      // (the tree's ground over the old view's button, said to be the arrow)
      h.show(fn() { cover.get() }, fn(g) {
        g
        .over(Is(true))
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .on_press(fn() {  })
        .cursor(Is(Some(Arrow)))
        |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "the pointer's shape over the tree and the old views: a node's hand, an edge's own, the old view's button's hand; an arrow said over it, the arrow, not the hand of what lies under it" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let edge : @signals.Signal[Cursor?] = @signals.signal(Some(ResizeX), same=fn(a, b) { a == b })
  let cover = on(false)
  let t = shaped_tester(edge, cover, on(true))
  finger(1, 40.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), Hand, msg="over the tree's button")
  finger(1, 85.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), ResizeX, msg="over the edge")
  finger(1, 130.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), Hand, msg="over the old view's button")
  cover.set(true)
  t.frames_owed()
  assert_eq(t.cursor(), Arrow, msg="the tree's ground said to be the arrow over it: the arrow")
}

///|
test "a still pointer over a node: its shape said anew, and the node taking presses no more, told the host by the frames owed, no move" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let edge : @signals.Signal[Cursor?] = @signals.signal(Some(ResizeX), same=fn(a, b) { a == b })
  let b_on = on(true)
  let t = shaped_tester(edge, on(false), b_on)
  finger(1, 85.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), ResizeX)
  edge.set(Some(Grab))
  t.frames_owed()
  assert_eq(t.cursor(), Grab, msg="said anew")
  finger(1, 40.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), Hand)
  b_on.set(false)
  t.frames_owed()
  assert_eq(t.cursor(), Arrow, msg="the button taking presses no more: the arrow of the ground under it")
}

///|
test "a press held on an edge: its shape kept as the pointer goes off it over a button, and once let go, the button's" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let edge : @signals.Signal[Cursor?] = @signals.signal(Some(ResizeX), same=fn(a, b) { a == b })
  let t = shaped_tester(edge, on(false), on(true))
  finger(1, 85.0, 20.0)
  finger(0, 85.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), ResizeX)
  finger(1, 40.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), ResizeX, msg="held: the edge's, over the button")
  finger(2, 40.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), Hand, msg="let go: the button's under it")
}

///|
test "a still pointer over a node's hand, a layer of the old frame's opening over it: its shape, the arrow, by the frame it opens in; closed, the node's again" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let edge : @signals.Signal[Cursor?] = @signals.signal(Some(ResizeX), same=fn(a, b) { a == b })
  let layer = on(false)
  let t = shaped_tester(edge, on(false), on(true), layer~)
  finger(1, 40.0, 20.0)
  t.frames_owed()
  assert_eq(t.cursor(), Hand)
  layer.set(true)
  t.draw()
  assert_eq(t.cursor(), Arrow, msg="the layer's over it")
  layer.set(false)
  t.draw()
  assert_eq(t.cursor(), Hand, msg="closed: the node's again")
}

///|
test "the pointer's shape told the host at each event of the mouse's, no frame drawn: moved between a button and an edge, pressed on the edge and moved off it, let go; as with the frames drawn" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let run = fn(frames : Bool) {
    let edge : @signals.Signal[Cursor?] = @signals.signal(Some(ResizeX), same=fn(a, b) { a == b })
    let t = shaped_tester(edge, on(false), on(true))
    let seen : Array[Cursor] = []
    let step = fn(kind : Int, x : Double) {
      finger(kind, x, 20.0)
      if frames {
        t.frames_owed()
      }
      seen.push(t.cursor())
    }
    step(1, 40.0)
    step(1, 85.0)
    step(1, 40.0)
    step(1, 85.0)
    step(0, 85.0)
    step(1, 40.0)
    step(2, 40.0)
    seen
  }
  let want : Array[Cursor] = [Hand, ResizeX, Hand, ResizeX, ResizeX, ResizeX, Hand]
  assert_eq(run(false), want, msg="no frame drawn")
  assert_eq(run(true), want, msg="the frames drawn")
}

///|
test "a node's shape said by a saying, said anew as a value or the node let go: the saying let go of then" {
  let shape : @signals.Signal[Cursor?] = @signals.signal(Some(Grab), same=fn(a, b) { a == b })
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let v : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { there.get() }, fn(n) {
      v.val = Some(n)
      n.width(Is(Some(40.0))).height(Is(Some(40.0))).cursor(By(fn() { shape.get() })) |> ignore
    })
  })
  t.draw()
  assert_true(shape.watched(), msg="followed")
  v.val.unwrap().cursor(Is(Some(Arrow))) |> ignore
  assert_false(shape.watched(), msg="said anew as a value: let go of then")
  v.val.unwrap().cursor(By(fn() { shape.get() })) |> ignore
  assert_true(shape.watched(), msg="followed again")
  let tree = view_app.val.unwrap()
  tree.event(view_moment(), fn() { there.set(false) })
  assert_false(shape.watched(), msg="the node let go: let go of then")
}

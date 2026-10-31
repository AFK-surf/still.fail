// What goes beside another (View::beside): placed by its anchor as the tree is placed, to the other side where it has
// not the room, kept in the window, following its anchor as that moves with no frame of its own; let go with what it
// lives with (View::lives_with).

///|
test "beside: below its anchor, its middle on its anchor's; above it where there is no room below; kept in the window; following its anchor moved" {
  let ax = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(By(fn() { (ax.get(), ay.get()) })) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b.width(Is(Some(60.0))).height(Is(Some(30.0))).beside(ids["a"], side=Bottom, along=Middle, offset=6.0) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let at = fn() {
    let d = t.drawn_of(ids["b"]).unwrap()
    (d.x, d.y)
  }
  assert_eq(at(), (90.0, 126.0), msg="below, its middle on its anchor's")
  t.event(10.0, fn() { ay.set(260.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (90.0, 224.0), msg="above: no room below")
  t.event(20.0, fn() { ax.set(380.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (332.0, 224.0), msg="kept in the window")
}

///|
test "lives_with: a node held elsewhere let go with its owner" {
  let owner_on = @signals.signal(true, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      let layer = root.box(fn(l) { l.over(Is(true)) |> ignore })
      root.show(fn() { owner_on.get() }, fn(o) {
        made.val = Some(layer.box(fn(x) { x.width(Is(Some(10.0))) |> ignore }).lives_with(o))
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let m = made.val.unwrap()
  assert_true(m.alive(), msg="there")
  t.event(10.0, fn() { owner_on.set(false) })
  assert_false(m.alive(), msg="let go with its owner")
}

///|
test "beside: one beside another that goes beside a third, made and said the other way round: placed in their order, whatever order made or said; following the first's holder moved, in the one frame after; a colour alone changed, none placed again" {
  let hx = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ink = @signals.signal(0x000000FFL, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      // (the last of the chain made first: its anchor a node made after it)
      let late : Ref[@view.View?] = Ref(None)
      root.box(fn(c) {
        ids["c"] = c.id()
        late.val = Some(c)
        c.width(Is(Some(20.0))).height(Is(Some(10.0))).ground(By(fn() { ink.get() })) |> ignore
      })
      |> ignore
      root.box(fn(h) {
        h.over(Is(true)).width(Is(Some(50.0))).height(Is(Some(20.0))).offset(By(fn() { (hx.get(), 50.0) })) |> ignore
        h.box(fn(a) {
          ids["a"] = a.id()
          a.width(Is(Some(40.0))).height(Is(Some(20.0))) |> ignore
        })
        |> ignore
      })
      |> ignore
      let mid = root.box(fn(b) {
        ids["b"] = b.id()
        b.width(Is(Some(60.0))).height(Is(Some(30.0))) |> ignore
      })
      // (said the other way round too: the last of the chain first)
      late.val.unwrap().beside(ids["b"], side=Bottom, along=Start, offset=0.0) |> ignore
      mid.beside(ids["a"], side=Bottom, along=Start, offset=0.0) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let at = fn(k : String) {
    let d = t.drawn_of(ids[k]).unwrap()
    (d.x, d.y)
  }
  assert_eq((at("b"), at("c")), ((100.0, 70.0), (100.0, 100.0)), msg="in their order")
  t.event(10.0, fn() { hx.set(200.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq((at("b"), at("c")), ((200.0, 70.0), (200.0, 100.0)), msg="the holder moved: the frame after")
  let placed = t.work().besides
  t.event(20.0, fn() { ink.set(0xFF0000FFL) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(t.work().besides, placed, msg="a colour alone: none placed again")
}

///|
test "beside: two beside each other (a ring), and one beside what it holds: each goes beside nothing, where it is laid out, frame after frame" {
  let grow = @signals.signal(30.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let made : Map[String, @view.View] = {}
  let t = @view.Tree::new(
    fn(root) {
      for k in ["a", "b", "c"] {
        made[k] = root.box(fn(v) {
          ids[k] = v.id()
          v.width(By(fn() { Some(grow.get()) })).height(Is(Some(20.0))) |> ignore
          if k == "c" {
            v.box(fn(inner) {
              ids["inner"] = inner.id()
              inner.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
            })
            |> ignore
          }
        })
      }
      made["a"].beside(ids["b"]) |> ignore
      made["b"].beside(ids["a"]) |> ignore
      made["c"].beside(ids["inner"]) |> ignore
    },
    time=fn() { 0.0 },
  )
  let laid = fn() {
    ["a", "b", "c"].map(fn(k) {
      let d = t.drawn_of(ids[k]).unwrap()
      (d.x, d.y)
    })
  }
  t.frame(400.0, 300.0) |> ignore
  let first = laid()
  assert_eq(first, [(0.0, 0.0), (0.0, 0.0), (0.0, 0.0)], msg="where laid out: out of the flow, at its holder's start")
  // (laid out and placed again: the same, not where any went before)
  t.event(10.0, fn() { grow.set(60.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(laid(), first, msg="the same, frame after frame")
}

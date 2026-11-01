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
test "lives_with: held beside its owner in one layer, the layer let go whole (a tip of a menu's row, the menu made anew as the theme changes): each let go once, nothing read past what the layer holds" {
  let theme = @signals.signal(0, same=fn(a, b) { a == b })
  let mades : Array[@view.View] = []
  // (one made elsewhere as the owner goes, in the place the tip let go of)
  let after : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.pick(fn() { theme.get() }, fn(p, _) {
        let layer = p.box(fn(l) { l.over(Is(true)) |> ignore })
        layer.box(fn(o) {
          mades.push(layer.box(fn(x) { x.width(Is(Some(10.0))) |> ignore }).lives_with(o))
          o.owns(fn() { after.val = Some(root.box(fn(_) {  })) }) |> ignore
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  t.event(10.0, fn() { theme.set(1) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(mades.length(), 2, msg="made anew")
  assert_false(mades[0].alive(), msg="the first let go with its owner")
  assert_true(mades[1].alive(), msg="the new one there")
  assert_true(after.val.unwrap().alive(), msg="what was made elsewhere as it went, not let go with it")
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

///|
test "went_told: the side it went on told the frame it is first placed, and again only the frame it goes to the other side: moved along its anchor or within the room it has, what reads it is not told" {
  let ax = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let b : Ref[@view.View?] = Ref(None)
  let reads = Ref(0)
  let said : Ref[@view.Side?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(By(fn() { (ax.get(), ay.get()) })) |> ignore
      })
      |> ignore
      b.val = Some(
        root.box(fn(b) {
          b.width(Is(Some(60.0))).height(Is(Some(30.0))).beside(ids["a"], side=Bottom, along=Middle, offset=6.0) |> ignore
        }),
      )
      // (what reads it: a node as tall as it says)
      root.box(fn(r) {
        r
        .height(By(fn() {
          reads.val = reads.val + 1
          said.val = b.val.unwrap().went_told()
          Some(if said.val is Some(Top) { 2.0 } else { 1.0 })
        }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let first = (said.val, reads.val)
  // (moved along it, and down within the room below it)
  t.event(10.0, fn() { ax.set(200.0) })
  t.frame(400.0, 300.0) |> ignore
  t.event(20.0, fn() { ay.set(150.0) })
  t.frame(400.0, 300.0) |> ignore
  let moved = (said.val, reads.val)
  // (no room below: above it)
  t.event(30.0, fn() { ay.set(260.0) })
  t.frame(400.0, 300.0) |> ignore
  let flipped = (said.val, reads.val)
  t.event(40.0, fn() { ay.set(100.0) })
  t.frame(400.0, 300.0) |> ignore
  let back = (said.val, reads.val)
  assert_eq(
    (first.0, moved.0, moved.1 - first.1, flipped.0, flipped.1 - moved.1, back.0, back.1 - flipped.1),
    (Some(@view.Side::Bottom), Some(@view.Side::Bottom), 0, Some(@view.Side::Top), 1, Some(@view.Side::Bottom), 1),
    msg="first \{first} moved \{moved} flipped \{flipped} back \{back}",
  )
}

///|
/// A tree in a window 400×500: an anchor 40×20 at (100, `ay`) while `on`, a node 60×484 beside it (Bottom, 6 off) and
/// a node reading the side that one went on (View::went_told): the side read, how many times it was read.
fn went_tree(
  ay : @signals.Signal[Double],
  on : @signals.Signal[Bool],
  said : Ref[@view.Side?],
  reads : Ref[Int],
) -> (@view.Tree, Map[String, @view.NodeId]) {
  let ids : Map[String, @view.NodeId] = {}
  let b : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { on.get() }, fn(s) {
        s.box(fn(a) {
          ids["a"] = a.id()
          a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(By(fn() { (100.0, ay.get()) })) |> ignore
        })
        |> ignore
      })
      |> ignore
      b.val = Some(
        root.box(fn(n) {
          ids["b"] = n.id()
          n.over(Is(true)).width(Is(Some(60.0))).height(Is(Some(484.0))).beside(ids["a"], side=Bottom, along=Middle, offset=6.0) |> ignore
        }),
      )
      root.box(fn(r) {
        r
        .height(By(fn() {
          reads.val = reads.val + 1
          said.val = b.val.unwrap().went_told()
          Some(if said.val is Some(Top) { 2.0 } else { 1.0 })
        }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  (t, ids)
}

///|
test "went_told: as tall as the window less its padding, kept at the window's top on either side, its anchor moved from 200 to 300 down a 500 high window: told it went below, then above, the frame it does, nothing else of it changed" {
  let ay = @signals.signal(200.0, same=fn(a, b) { a == b })
  let said : Ref[@view.Side?] = Ref(None)
  let reads = Ref(0)
  let (t, ids) = went_tree(ay, @signals.signal(true), said, reads)
  t.frame(400.0, 500.0) |> ignore
  let y = fn() { t.drawn_of(ids["b"]).unwrap().y }
  let first = (y(), said.val, reads.val)
  t.event(10.0, fn() { ay.set(300.0) })
  t.frame(400.0, 500.0) |> ignore
  let moved = (y(), said.val, reads.val)
  assert_eq(
    (first.0, first.1, moved.0, moved.1, moved.2 - first.2),
    (8.0, Some(@view.Side::Bottom), 8.0, Some(@view.Side::Top), 1),
    msg="first \{first} moved \{moved}",
  )
}

///|
test "went_told: placed above its anchor, then its anchor gone: told it goes beside nothing" {
  let ay = @signals.signal(300.0, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let said : Ref[@view.Side?] = Ref(None)
  let reads = Ref(0)
  let (t, _) = went_tree(ay, on, said, reads)
  t.frame(400.0, 500.0) |> ignore
  let placed = said.val
  t.event(10.0, fn() { on.set(false) })
  t.frame(400.0, 500.0) |> ignore
  assert_eq((placed, said.val), (Some(@view.Side::Top), None))
}

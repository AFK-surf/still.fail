// What goes beside another (View::beside): placed by its anchor as the tree is placed, to the other side where it has
// not the room, kept in the window, following its anchor as that moves with no frame of its own; let go with what it
// lives with (View::lives_with).

///|
test "beside: below its anchor, its middle on its anchor's; above it where there is no room below; kept in the window; following its anchor moved" {
  let ax = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = Map([])
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
test "beside: leaving, or its anchor gone, it stays where it last went beside it as it fades: never after its anchor, never where it is laid out" {
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let anchor_on = @signals.signal(true, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let fade = @signals.signal(1.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.show(at_once=true, fn() { anchor_on.get() }, fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(By(fn() { (100.0, ay.get()) })) |> ignore
      })
      root.show(at_once=true, fn() { on.get() }, leave=100.0, fn(b) {
        ids["b"] = b.id()
        b
        .width(Is(Some(60.0)))
        .height(Is(Some(30.0)))
        .alpha(By(fn() { fade.get() }))
        .beside(ids["a"], side=Bottom, along=Middle, offset=6.0)
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let at = fn() {
    let d = t.drawn_of(ids["b"]).unwrap()
    (d.x, d.y)
  }
  assert_eq(at(), (90.0, 126.0), msg="below its anchor")
  t.event(10.0, fn() { ay.set(140.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (90.0, 166.0), msg="following its anchor while both are there")
  // (leaving: its anchor moves on, it fades where it was)
  t.event(20.0, fn() { on.set(false) })
  t.event(30.0, fn() {
    ay.set(40.0)
    fade.set(0.5)
  })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (90.0, 166.0), msg="leaving: where it was")
  // (back, then its anchor gone: placed again by its own fading, where it was)
  t.event(40.0, fn() { on.set(true) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (90.0, 66.0), msg="back: beside its anchor again")
  t.event(50.0, fn() { anchor_on.set(false) })
  t.event(60.0, fn() { fade.set(0.25) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (90.0, 66.0), msg="its anchor gone: where it was")
}

///|
test "lives_with: a node held elsewhere let go with its owner" {
  let owner_on = @signals.signal(true, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      let layer = root.box(fn(l) { l.over(Is(true)) |> ignore })
      root.show(at_once=true, fn() { owner_on.get() }, fn(o) {
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
      root.pick(at_once=true, fn() { theme.get() }, fn(p, _) {
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
  let ids : Map[String, @view.NodeId] = Map([])
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
  let ids : Map[String, @view.NodeId] = Map([])
  let made : Map[String, @view.View] = Map([])
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
test "went_over: the side it went on as it is placed: moved along its anchor or within the room it has, the same; no room below, above; room again, below" {
  let ax = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = Map([])
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
        // (what it holds: the side what holds it went on, as it is)
        b.box(fn(c) { ids["c"] = c.id() }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let first = t.went_over(ids["c"])
  // (moved along it, and down within the room below it)
  t.event(10.0, fn() { ax.set(200.0) })
  t.frame(400.0, 300.0) |> ignore
  t.event(20.0, fn() { ay.set(150.0) })
  t.frame(400.0, 300.0) |> ignore
  let moved = t.went_over(ids["c"])
  // (no room below: above it)
  t.event(30.0, fn() { ay.set(260.0) })
  t.frame(400.0, 300.0) |> ignore
  let flipped = t.went_over(ids["b"])
  t.event(40.0, fn() { ay.set(100.0) })
  t.frame(400.0, 300.0) |> ignore
  let back = t.went_over(ids["b"])
  assert_eq(
    (first, moved, flipped, back, t.went_over(ids["a"])),
    (Some(@view.Side::Bottom), Some(@view.Side::Bottom), Some(@view.Side::Top), Some(@view.Side::Bottom), None),
  )
}

///|
/// A tree in a window 400×500: an anchor 40×20 at (100, `ay`) while `on`, a node 60×484 beside it (Bottom, 6 off).
fn went_tree(ay : @signals.Signal[Double], on : @signals.Signal[Bool]) -> (@view.Tree, Map[String, @view.NodeId]) {
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.show(at_once=true, fn() { on.get() }, fn(s) {
        s.box(fn(a) {
          ids["a"] = a.id()
          a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(By(fn() { (100.0, ay.get()) })) |> ignore
        })
        |> ignore
      })
      |> ignore
      root.box(fn(n) {
        ids["b"] = n.id()
        n.over(Is(true)).width(Is(Some(60.0))).height(Is(Some(484.0))).beside(ids["a"], side=Bottom, along=Middle, offset=6.0) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  (t, ids)
}

///|
test "went_over: as tall as the window less its padding, kept at the window's top on either side, its anchor moved from 200 to 300 down a 500 high window: below, then above" {
  let ay = @signals.signal(200.0, same=fn(a, b) { a == b })
  let (t, ids) = went_tree(ay, @signals.signal(true))
  t.frame(400.0, 500.0) |> ignore
  let y = fn() { t.drawn_of(ids["b"]).unwrap().y }
  let first = (y(), t.went_over(ids["b"]))
  t.event(10.0, fn() { ay.set(300.0) })
  t.frame(400.0, 500.0) |> ignore
  let moved = (y(), t.went_over(ids["b"]))
  assert_eq((first, moved), ((8.0, Some(@view.Side::Bottom)), (8.0, Some(@view.Side::Top))))
}

///|
test "went_over: placed above its anchor, then its anchor gone: beside nothing" {
  let ay = @signals.signal(300.0, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, ids) = went_tree(ay, on)
  t.frame(400.0, 500.0) |> ignore
  let placed = t.went_over(ids["b"])
  t.event(10.0, fn() { on.set(false) })
  t.frame(400.0, 500.0) |> ignore
  assert_eq((placed, t.went_over(ids["b"])), (Some(@view.Side::Top), None))
}

///|
test "beside a piece of its anchor (`piece`): by that piece, given how big the anchor is laid out, following the anchor moved; with none now, where it last was; what the piece reads alone changing places nothing" {
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let aw = @signals.signal(40.0, same=fn(a, b) { a == b })
  // (a plain value, not followed: what the piece reads, as it is placed)
  let piece_at = Ref(Some((10.0, 5.0)))
  let given : Array[(Double, Double)] = []
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(By(fn() { Some(aw.get()) })).height(Is(Some(20.0))).offset(By(fn() { (100.0, ay.get()) })) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b
        .width(Is(Some(60.0)))
        .height(Is(Some(30.0)))
        .beside(ids["a"], side=Bottom, along=Start, offset=6.0, piece=fn(w, h) {
          given.push((w, h))
          piece_at.val.map(fn(p) { (p.0, p.1, 20.0, 10.0) })
        })
        |> ignore
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
  assert_eq((at(), given), ((110.0, 121.0), [(40.0, 20.0)]), msg="under the piece, at its start")
  t.event(10.0, fn() { ay.set(150.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (110.0, 171.0), msg="following the anchor moved")
  // (what the piece reads changed alone: nothing placed again)
  piece_at.val = Some((30.0, 5.0))
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (110.0, 171.0), msg="its piece's reads are not followed")
  // (the anchor laid out again: asked again, given its new size)
  t.event(20.0, fn() { aw.set(50.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq((at(), given[given.length() - 1]), ((130.0, 171.0), (50.0, 20.0)), msg="asked again as it is laid out")
  // (no such piece now: where it last was, the anchor moved or not)
  piece_at.val = None
  t.event(30.0, fn() { ay.set(200.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (130.0, 171.0), msg="no piece: where it was")
  piece_at.val = Some((10.0, 5.0))
  t.event(40.0, fn() { ay.set(210.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), (110.0, 231.0), msg="by it again")
}

///|
/// Where a box 60 by 30 is drawn beside one 40 by 20 at (`ax`, 100) in a window 400 by 300: under it, 6 off, lined up at
/// its start, moved `shift` further along (View::beside's along_offset); beside the piece (10, 0, 20, 20) of it where
/// `piece`.
fn beside_shifted(ax : Double, shift : Double, piece? : Bool = false) -> (Double, Double) {
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(Is((ax, 100.0))) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b.width(Is(Some(60.0))).height(Is(Some(30.0))) |> ignore
        if piece {
          b.beside(ids["a"], side=Bottom, along=Start, offset=6.0, along_offset=shift, piece=fn(_, _) {
            Some((10.0, 0.0, 20.0, 20.0))
          })
          |> ignore
        } else {
          b.beside(ids["a"], side=Bottom, along=Start, offset=6.0, along_offset=shift) |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let d = t.drawn_of(ids["b"]).unwrap()
  (d.x, d.y)
}

///|
test "beside: moved along its side by along_offset, either way, from its anchor's start; kept in the window by its padding as ever; from a piece of its anchor where it has one" {
  assert_eq(beside_shifted(100.0, 0.0), (100.0, 126.0), msg="none: at its anchor's start")
  assert_eq(beside_shifted(100.0, 10.0), (110.0, 126.0), msg="10 on")
  assert_eq(beside_shifted(100.0, -10.0), (90.0, 126.0), msg="10 back")
  // (its anchor near the window's right: 340 would leave it past 400 - 8; kept in, at 332)
  assert_eq(beside_shifted(330.0, 10.0), (332.0, 126.0), msg="kept in the window")
  // (a piece of its anchor 10 in: from the piece's start, 110, 5 on)
  assert_eq(beside_shifted(100.0, 5.0, piece=true), (115.0, 126.0), msg="from its piece")
}

///|
test "beside holding its side: above its anchor where it had not the room below, kept above as it comes to fit below, only its top moving; shown again, below; one not holding it goes below at once" {
  let h = @signals.signal(200.0, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = Map([])
  let make = fn(holds : Bool) {
    @view.Tree::new(
      fn(root) {
        root.box(fn(a) {
          ids["a"] = a.id()
          a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(Is((100.0, 250.0))) |> ignore
        })
        |> ignore
        root.show(at_once=true, fn() { on.get() }, fn(b) {
          ids["b"] = b.id()
          b
          .width(Is(Some(60.0)))
          .height(By(fn() { Some(h.get()) }))
          .beside(ids["a"], side=Bottom, offset=6.0, holds_side=holds)
          |> ignore
        })
      },
      time=fn() { 0.0 },
    )
  }
  let t = make(true)
  t.frame(400.0, 400.0) |> ignore
  let at = fn() {
    let d = t.drawn_of(ids["b"]).unwrap()
    (d.y, d.h)
  }
  // (200 tall: 116 below, 236 above: above, its foot 6 over its anchor)
  assert_eq(at(), (44.0, 200.0), msg="above: no room below")
  // (80 tall: it would fit below now; kept above, its foot where it was)
  t.event(10.0, fn() { h.set(80.0) })
  t.frame(400.0, 400.0) |> ignore
  assert_eq(at(), (164.0, 80.0), msg="kept above, only its top moved")
  assert_eq(t.went_over(ids["b"]), Some(@view.Side::Top))
  // (shown again: on whichever side has the room then)
  t.event(20.0, fn() { on.set(false) })
  t.event(30.0, fn() { on.set(true) })
  t.frame(400.0, 400.0) |> ignore
  assert_eq(at(), (276.0, 80.0), msg="shown again: below")
  // (one not holding its side: below as soon as it fits)
  h.set(200.0)
  on.set(true)
  let u = make(false)
  u.frame(400.0, 400.0) |> ignore
  u.event(10.0, fn() { h.set(80.0) })
  u.frame(400.0, 400.0) |> ignore
  assert_eq(u.drawn_of(ids["b"]).map(fn(d) { d.y }), Some(276.0), msg="not holding it: below")
}

///|
test "beside holding its side: short below its anchor, grown past the room below: above, for want of it; shrunk again: kept above; shown below and the window made too short below: placed afresh, above" {
  let h = @signals.signal(80.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(Is((100.0, 250.0))) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b.width(Is(Some(60.0))).height(By(fn() { Some(h.get()) })).beside(ids["a"], side=Bottom, offset=6.0, holds_side=true)
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let at = fn() { t.drawn_of(ids["b"]).map(fn(d) { d.y }) }
  t.frame(400.0, 400.0) |> ignore
  assert_eq(at(), Some(276.0), msg="short: below")
  // (200 tall: 116 below, 236 above: above for want of room below)
  t.event(10.0, fn() { h.set(200.0) })
  t.frame(400.0, 400.0) |> ignore
  assert_eq(at(), Some(44.0), msg="grown: above")
  // (80 tall again: room below too; kept above, only its top moved)
  t.event(20.0, fn() { h.set(80.0) })
  t.frame(400.0, 400.0) |> ignore
  assert_eq(at(), Some(164.0), msg="shrunk: kept above")
  // (a 400 high window, the anchor at 250, one 30 tall: kept above as it has the room; the window 300 high as it is
  // above: kept above, the room there as it was)
  t.event(30.0, fn() { h.set(30.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), Some(214.0), msg="above still: room there")
}

///|
test "beside holding its side: below its anchor, the window made too short below: placed afresh, above" {
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(Is((100.0, 250.0))) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b.width(Is(Some(60.0))).height(Is(Some(80.0))).beside(ids["a"], side=Bottom, offset=6.0, holds_side=true) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let at = fn() { t.drawn_of(ids["b"]).map(fn(d) { d.y }) }
  t.frame(400.0, 400.0) |> ignore
  assert_eq(at(), Some(276.0), msg="below")
  // (300 high: 16 below, 236 above: not the room below any more, placed afresh: above)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at(), Some(164.0), msg="window too short below: above")
}

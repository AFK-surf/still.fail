// A node's edge round its ground (View::edge): one rect, filled and edged, as an old view's box with a border is drawn
// (scene.mbt's emit_rect): the same instance but for where it is.

///|
/// The rect instances the frame just drawn has `w` × `h` (its numbers from the corner radius on: radius, kind, edge
/// width, blur, fill, edge colour).
fn rects_sized(w : Double, h : Double) -> Array[Array[Double]] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let at = k * inst_size
    if c.inst[at + 2] == w && c.inst[at + 3] == h {
      out.push(Array::makei(12, fn(i) { c.inst[at + 4 + i] }))
    }
  }
  out
}

///|
test "a node's edge: one rect filled and edged, the instance an old view's box with that border draws" {
  let ring = 0xE5704AFFL
  let _ = Tester::new(fn(c) {
    c.box(tx=100.0, ty=100.0, w=Px(12.0), h=Px(12.0), radius=6.0, bg=0xFFFFFFFFL, border=1.5, border_color=ring, fn() {  })
    |> ignore
  })
  let old = rects_sized(12.0, 12.0)
  assert_eq(old.length(), 1, msg="the old box: one rect")
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.offset(Is((100.0, 100.0))).width(Is(Some(12.0))).height(Is(Some(12.0))).radius(Is(6.0)).ground(Is(0xFFFFFFFFL)).edge(Is((1.5, ring)))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let node = rects_sized(12.0, 12.0)
  assert_eq(node, old, msg="the node: the same one rect")
}

///|
test "a node's edge half seen (what holds it at 0.5): the instance an old view's box with that border draws at 0.5" {
  let ring = 0xE5704AFFL
  let _ = Tester::new(fn(c) {
    c.box(opacity=0.5, fn() {
      c.box(tx=100.0, ty=100.0, w=Px(12.0), h=Px(12.0), radius=6.0, bg=0xFFFFFFFFL, border=1.5, border_color=ring, fn() {  })
      |> ignore
    })
    |> ignore
  })
  let old = rects_sized(12.0, 12.0)
  assert_eq(old.length(), 1, msg="the old box: one rect")
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.alpha(Is(0.5)) |> ignore
      h.box(fn(n) {
        n.offset(Is((100.0, 100.0))).width(Is(Some(12.0))).height(Is(Some(12.0))).radius(Is(6.0)).ground(Is(0xFFFFFFFFL)).edge(Is((1.5, ring)))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(rects_sized(12.0, 12.0), old, msg="the node at 0.5: the same one rect")
}

///|
test "a node's edge round what it holds, reaching its edges: its ground inside the edge, what it holds, then the edge over it, the instances an old view's box with that border draws in that order" {
  let ring = 0xE5704AFFL
  let _ = Tester::new(fn(c) {
    c.box(tx=100.0, ty=100.0, w=Px(40.0), h=Px(24.0), radius=6.0, bg=0xFFFFFFFFL, border=1.5, border_color=ring, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0x2050A0FFL, fn() {  }) |> ignore
    })
    |> ignore
  })
  let old = rects_sized(40.0, 24.0)
  assert_eq(old.length(), 3, msg="the old box: its ground, what it holds, its border \{old}")
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.offset(Is((100.0, 100.0))).width(Is(Some(40.0))).height(Is(Some(24.0))).radius(Is(6.0)).ground(Is(0xFFFFFFFFL)).edge(Is((1.5, ring)))
      |> ignore
      n.box(fn(k) { k.grow(Is(1.0)).ground(Is(0x2050A0FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(rects_sized(40.0, 24.0), old, msg="the node: the same three, in that order")
}

///|
/// Where the frame just drawn has a rect instance edged in `ring` (its edge's colour, red at 8 bits in 12) or filled
/// `fill`: its index, the first such.
fn inst_where(pick : (Int) -> Bool) -> Int {
  let c = g()
  for k in 0..<c.ninst {
    if pick(k * inst_size) {
      return k
    }
  }
  -1
}

///|
/// A node 40 × 24 at (100, 100), round 6, its ground `ground`, edged 1.5 in a red, holding a node across all of it (its
/// own ground a blue), drawn as `look` says besides. The Tester, and the node.
fn edged_holder(ground : Int64, look : (@view.View) -> Unit) -> (Tester, Ref[@view.NodeId?]) {
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      id.val = Some(n.id())
      n.offset(Is((100.0, 100.0))).width(Is(Some(40.0))).height(Is(Some(24.0))).radius(Is(6.0)).ground(Is(ground)).edge(Is((1.5, 0xE5704AFFL)))
      |> ignore
      look(n)
      n.box(fn(k) { k.grow(Is(1.0)).ground(Is(0x2050A0FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, id)
}

///|
/// Whether instance `k`'s edge is the red of edged_holder's (its edge colour's red, 12, at 0xE5).
fn red_edged(at : Int) -> Bool {
  let c = g()
  (c.inst[at + 12] * 255.0).round() == 229.0 && c.inst[at + 15] > 0.0 && c.inst[at + 11] == 0.0
}

///|
test "a node's edge round what it holds, its ground drawn off and bigger and the node turned: the edge drawn off, bigger and turned as its ground is, after what it holds" {
  let (_, _) = edged_holder(0xFFFFFFFFL, fn(n) {
    n.ground_drawn(Is((-4.0, -2.0, 8.0, 4.0))).turn(Is(0.3)) |> ignore
  })
  let c = g()
  let fill = inst_where(fn(at) { c.inst[at + 8] == 1.0 && c.inst[at + 9] == 1.0 && c.inst[at + 11] == 1.0 && c.inst[at + 2] > 40.0 })
  let blue = inst_where(fn(at) { (c.inst[at + 10] * 255.0).round() == 160.0 && c.inst[at + 11] == 1.0 })
  let ring = inst_where(red_edged)
  let same = fill >= 0 && ring >= 0 && [0, 1, 2, 3, 4, 6, 32, 33, 34, 35].all(fn(j) { c.inst[fill * inst_size + j] == c.inst[ring * inst_size + j] })
  assert_eq((fill >= 0, blue > fill, ring > blue, same), (true, true, true, true), msg="\{fill} \{blue} \{ring}")
}

///|
test "a node's edge round what it holds, what holds it fading towards its edges: the edge faded as its ground is" {
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(f) {
      f.width(Is(Some(400.0))).height(Is(Some(300.0))).fades(Is((0.0, 60.0, 0.0, 60.0))) |> ignore
      f.box(fn(n) {
        n.offset(Is((100.0, 10.0))).width(Is(Some(40.0))).height(Is(Some(24.0))).radius(Is(6.0)).ground(Is(0xFFFFFFFFL)).edge(Is((1.5, 0xE5704AFFL)))
        |> ignore
        n.box(fn(k) { k.grow(Is(1.0)).ground(Is(0x2050A0FFL)) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let c = g()
  let fill = inst_where(fn(at) { c.inst[at + 8] == 1.0 && c.inst[at + 9] == 1.0 && c.inst[at + 11] == 1.0 && c.inst[at + 2] == 40.0 })
  let ring = inst_where(red_edged)
  // (the fade's own numbers: what fades it, its band from the top and the foot, as inst_fade wrote them)
  let fades_of = fn(k : Int) { Array::makei(8, fn(j) { c.inst[k * inst_size + 52 + j] }) }
  assert_true(fill >= 0 && ring > fill && fades_of(fill) == fades_of(ring) && fades_of(fill).iter().any(fn(v) { v != 0.0 }), msg="\{fill} \{ring} \{if fill >= 0 { fades_of(fill) } else { [] }} \{if ring >= 0 { fades_of(ring) } else { [] }}")
}

///|
test "a node with no ground of its own, only an edge, round what it holds, turned about what it draws: its edge turned about its own middle, its own" {
  inst_owners.track = true
  let (_, id) = edged_holder(0L, fn(n) { n.turn(Is(0.4), drawn=true) |> ignore })
  let c = g()
  let ring = inst_where(red_edged)
  // (turned about the middle of what it draws, the edge itself: its own rect's middle, 120, 112)
  let about = if ring >= 0 { (c.inst[ring * inst_size + 33], c.inst[ring * inst_size + 34]) } else { (-1.0, -1.0) }
  let own = ring >= 0 && inst_by(ring) == Node(id.val.unwrap())
  inst_owners.track = false
  assert_eq((about, own), ((120.0, 112.0), true), msg="\{ring}")
}

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

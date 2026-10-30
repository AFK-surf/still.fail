// A node of the window's tree's shapes (View::shapes): drawn where it is, in its tint (View::tint), their bands worked
// out once for the outlines said and their pieces put after each frame's wherever the node's block is composed again.

///|
test "a node's shapes: drawn where it is, the same as composed again in a later frame; another tint draws them in it, their bands as they were" {
  let tint = @signals.signal(0xFF0000FFL, same=fn(a, b) { a == b })
  let shapes = [shape_of([([2.0, 2.0, 18.0, 2.0, 18.0, 18.0, 2.0, 18.0], true)], fill=0x000000FFL)]
  // (another node's shapes, drawn before it once shown: their pieces before its own in the frame)
  let before = @signals.signal(false, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.show(fn() { before.get() }, fn(b) {
      b.over(Is(true)).shapes(Is([shape_of([([0.0, 0.0, 20.0, 0.0, 0.0, 20.0], true)], fill=0x0000FFFFL)])) |> ignore
    })
    root.box(fn(n) {
      id.val = Some(n.id())
      n.offset(Is((100.0, 100.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).shapes(Is(shapes)).tint(By(fn() { tint.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let colours = fn() { t.drawn_shapes().filter(fn(s) { s.0 >= 100.0 }).map(fn(s) { s.5 }) }
  assert_true(colours().length() > 0 && colours().all(fn(c) { c == 0xFF0000FFL }))
  let covered = t.shape_cover(110.0, 110.0)
  assert_true(covered > 0.9, msg="\{covered}")
  let bands = view_shape_bands.get(id.val.unwrap()).unwrap()
  // a later frame, another node's shapes drawn before it: its block composed again, its pieces where its bands say
  before.set(true)
  t.frame_at(t.time() + frame_period_default)
  // (each band's pieces its own: no two bands' the same pieces)
  let c = g()
  let ranges : Array[(Int, Int)] = []
  for k in 0..<c.ninst {
    if c.inst[k * inst_size + 5] == 11.0 {
      ranges.push((c.inst[k * inst_size + 12].to_int(), c.inst[k * inst_size + 13].to_int()))
    }
  }
  assert_true(ranges.length() >= 2)
  for i in 0..<ranges.length() {
    for j in (i + 1)..<ranges.length() {
      let (a0, an) = ranges[i]
      let (b0, bn) = ranges[j]
      assert_true(a0 + an <= b0 || b0 + bn <= a0, msg="\{ranges}")
    }
  }
  assert_eq(t.shape_cover(110.0, 110.0), covered)
  // another tint: drawn in it, the same bands
  tint.set(0x00FF00FFL)
  t.frame_at(t.time() + frame_period_default)
  assert_true(colours().all(fn(c) { c == 0x00FF00FFL }))
  assert_true(physical_equal(view_shape_bands.get(id.val.unwrap()).unwrap(), bands))
  assert_eq(t.shape_cover(110.0, 110.0), covered)
}

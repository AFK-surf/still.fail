// Two layers whose instances are in the order B, A (A raised over the scrim after B: its instances moved after B's)
// while their pieces are still in the order A, B, both drawn again, one of them to more instances: spliced into the
// frame, each one's pieces its own and within the pieces the frame then holds (a raise and a redraw of both, as the
// 7348 build crashed on: the next frame's splice read past them).

///|
fn order_layer(at : Int, start : Int, count : Int, seg_from : Int, seg_count : Int) -> SceneLayer {
  {
    id: { at, gen: 0 },
    start,
    count,
    seg_from,
    seg_count,
    bands: [],
    anchors: [],
    inner: [],
    outer: None,
    clip: FixedArray::make(0, 0.0),
    clip_window: true,
    clip_apart: false,
    fading: [],
    stretching: [],
    glyphing: [],
    held: (0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
    scrim: false,
    reach: @damage.nowhere,
    watch: None,
    told: false,
    own_only: false,
    each: false,
    plots: [],
    images: [],
    reads_clock: false,
    seen: scene.frame,
    entries: None,
    entries_as: (1.0, 1.0),
    place_said: 0,
  }
}

///|
test "two layers whose pieces lie in the other order than their instances, spliced: each one's pieces within the frame's" {
  let _t = Tester::new(fn(_c) {  }, w=100.0, h=100.0)
  let c = g()
  // (the frame: B's 2 instances at 0, A's 2 at 2, then the pieces' 4 instances: A's 12 pieces first, B's 12 after)
  let tail = 4
  c.segs = Array::makei(24 * 4, fn(i) { (i / 4).to_double() })
  c.ninst = tail + 4
  while c.inst.length() < c.ninst * inst_size {
    c.grow()
  }
  scene.seg_tail = tail
  looks_base.looks = false
  let b = order_layer(902, 0, 2, 12, 12)
  let a = order_layer(901, 2, 2, 0, 12)
  scene.layers[a.id] = a
  scene.layers[b.id] = b
  // (both drawn again: B to 3 instances, A as it was, each with its 12 pieces anew)
  let new_inst = fn(n : Int) { FixedArray::make(n * inst_size, 0.0) }
  // (each one's new pieces its own: B's 9, A's 7, the frame's before them their places)
  let new_segs = fn(v : Double) { Array::make(12 * 4, v) }
  let drawn = [
    (b, 0, 12, new_inst(3), new_segs(9.0), None, 3, 2, 12),
    (a, 2, 0, new_inst(2), new_segs(7.0), None, 2, 2, 12),
  ]
  c.scene_spliced(drawn)
  let pieces = c.segs.length() / 4
  let held = (c.ninst - scene.seg_tail) * 6
  for lv in [(a, 7.0), (b, 9.0)] {
    let (l, mine) = lv
    assert_true(l.seg_from + l.seg_count <= pieces, msg="layer \{l.id.at}: pieces \{l.seg_from}..\{l.seg_from + l.seg_count} of \{pieces}")
    assert_true(l.seg_from + l.seg_count <= held, msg="layer \{l.id.at}: pieces \{l.seg_from}..\{l.seg_from + l.seg_count}, the frame's tail holds \{held}")
    // (and its own: the pieces it drew anew, none of the other's nor of the frame's before)
    for p in l.seg_from..<(l.seg_from + l.seg_count) {
      assert_eq(c.segs[p * 4], mine, msg="layer \{l.id.at}: piece \{p} not its own: \{c.segs[p * 4]}")
    }
  }
  assert_eq(pieces, 24)
}

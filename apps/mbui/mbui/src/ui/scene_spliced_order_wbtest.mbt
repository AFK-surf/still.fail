// Two layers whose instances are in the order B, A (A raised over the scrim after B: its instances moved after B's)
// while their pieces are still in the order A, B, both drawn again, one of them to more instances: spliced into the
// frame, each one's pieces its own and within the pieces the frame then holds. A case made by hand (the order a raise
// makes, both drawn again): not shown to be what the 7348 build crashed on, its stack an index past an array as
// scene_alone wrote the old frame back.

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

///|
test "the same with bands, one drawn again to more pieces, and a layer between them kept: each band at its own pieces" {
  let _t = Tester::new(fn(_c) {  }, w=100.0, h=100.0)
  let c = g()
  // (instances: B's 2 at 0, A's 2 at 2, C's band at 4; pieces: A's 12 (1), C's 1 (5), B's 12 (3))
  let tail = 5
  c.segs = Array::makei(25 * 4, fn(i) { if i / 4 < 12 { 1.0 } else if i / 4 == 12 { 5.0 } else { 3.0 } })
  c.ninst = tail + 5
  while c.inst.length() < c.ninst * inst_size {
    c.grow()
  }
  for z in 0..<(c.ninst * inst_size) {
    c.inst[z] = 0.0
  }
  c.inst[4 * inst_size + 5] = 11.0
  c.inst[4 * inst_size + 12] = 12.0
  c.inst[4 * inst_size + 13] = 1.0
  scene.seg_tail = tail
  looks_base.looks = false
  let b = order_layer(912, 0, 2, 13, 12)
  let a = order_layer(911, 2, 2, 0, 12)
  let k = order_layer(913, 4, 1, 12, 1)
  k.bands.push(0)
  scene.layers[a.id] = a
  scene.layers[b.id] = b
  scene.layers[k.id] = k
  // (each drawn again with a band at its first instance, its pieces from 0 in what it drew: A to 14 pieces of 7, B to 3
  // instances and 12 pieces of 9)
  let drawn_of = fn(n : Int, pieces : Int, v : Double) {
    let inst = FixedArray::make(n * inst_size, 0.0)
    inst[5] = 11.0
    inst[13] = pieces.to_double()
    (inst, Array::make(pieces * 4, v))
  }
  let (ai, asegs) = drawn_of(2, 14, 7.0)
  let (bi, bsegs) = drawn_of(3, 12, 9.0)
  a.bands.push(0)
  b.bands.push(0)
  c.scene_spliced([(b, 0, 13, bi, bsegs, None, 3, 2, 12), (a, 2, 0, ai, asegs, None, 2, 2, 12)])
  let pieces = c.segs.length() / 4
  assert_eq(pieces, 27)
  // (each band at its own pieces: A's 7, B's 9, C's 5 moved on by the 2 A grew by)
  for lv in [(a, 7.0, 14), (b, 9.0, 12), (k, 5.0, 1)] {
    let (l, mine, n) = lv
    let q = l.start * inst_size
    assert_eq(c.inst[q + 5], 11.0, msg="layer \{l.id.at}: no band at its start \{l.start}")
    let first = c.inst[q + 12].to_int()
    assert_eq(c.inst[q + 13].to_int(), n, msg="layer \{l.id.at}")
    assert_true(first >= 0 && first + n <= pieces, msg="layer \{l.id.at}: its band's pieces \{first}+\{n} of \{pieces}")
    for p in first..<(first + n) {
      assert_eq(c.segs[p * 4], mine, msg="layer \{l.id.at}: its band's piece \{p} not its own")
    }
    assert_eq(l.seg_from, first, msg="layer \{l.id.at}: said its pieces at \{l.seg_from}, its band at \{first}")
  }
}

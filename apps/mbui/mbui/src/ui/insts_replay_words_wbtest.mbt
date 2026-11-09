// A saved frame may be painted after the frame's nodes have changed. Its glyphs must not inherit the owners left at
// those instance slots by another frame: adjacent glyphs of one word can overlap within their picture's padding.

///|
test "a saved frame's glyphs do not inherit unrelated nodes when drawn again" {
  let t = Tester::new(fn(c) {
    c.box(fn() {
      c.text("first", wrap=false) |> ignore
      c.text("unrelated", wrap=false) |> ignore
    })
    |> ignore
  }, w=300.0, h=200.0, words_over_held=false)
  t.draw()
  let c = g()
  let mut glyph = -1
  let mut own = -1
  let mut other = -1
  for k in 0..<c.ninst {
    let o = inst_owner(k)
    if o >= 0 && o < c.count {
      if c.nodes[o].text == "first" && c.inst[k * inst_size + 5] == 1.0 && glyph < 0 {
        glyph = k
        own = o
      }
      if c.nodes[o].text == "unrelated" {
        other = o
      }
    }
  }
  assert_true(glyph >= 0 && other >= 0 && own != other)
  let count = c.ninst
  let saved = FixedArray::make((count + 1) * inst_size, 0.0)
  c.inst.blit_to(saved, len=count * inst_size)
  // A second glyph of this word occupies the same ink, as a combining mark may; it was drawn by the same node.
  c.inst.blit_to(saved, len=inst_size, src_offset=glyph * inst_size, dst_offset=count * inst_size)
  let pieces = c.segs.copy()
  // Another frame has since used these instance slots for other nodes.
  inst_owners.painting = other
  inst_owned(count)
  inst_owners.cell[glyph] = (0.0, 1.0)
  inst_owners.cell[count] = (0.0, 1.0)
  // The saved frame is drawn under the new one, owned by its own snapshot node.
  inst_owners.painting = own
  c.ninst = 0
  c.insts_replay(saved, (count + 1) * inst_size, pieces)
  assert_eq(c.words_over_faults().length(), 0)
}

// Each glyph drawn by a look of its own (Ctx::glyphs_by): words coming in a glyph at a time.

///|
/// The y of each glyph drawn in the last frame, and its height, in the order drawn.
fn glyph_boxes(t : Tester) -> Array[(Double, Double)] {
  ignore(t)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 {
      out.push((c.inst[b + 1], c.inst[b + 3]))
    }
  }
  out
}

///|
/// Two lines of words in a column, its glyphs from the `shown`th on hidden, the first moved down 10 at half its size.
fn glyphs_tester(shown : Int) -> Tester {
  Tester::new(fn(c) {
    let col = c.column(align=AStart, fn() {
      c.text("ab") |> ignore
      c.text("cd") |> ignore
    })
    let n = shown
    c.glyphs_by(col, fn(at) {
      let i = at.index
      if i >= n {
        { alpha: 0.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
      } else if i == 0 {
        { alpha: 1.0, dx: 0.0, dy: 10.0, scale: 0.5, sx: 1.0 }
      } else {
        { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
      }
    })
  })
}

///|
test "glyphs by a look of their own: numbered in reading order over what the node holds, moved, scaled, hidden" {
  let t = glyphs_tester(4)
  t.draw()
  let all = glyph_boxes(t)
  assert_eq(all.length(), 4)
  // the first moved down by 10 about its middle at half its size; the second as laid out, beside it
  let (y0, h0) = all[0]
  let (y1, h1) = all[1]
  assert_true((h0 - h1 / 2.0).abs() < 0.01, msg="\{h0} \{h1}")
  assert_true((y0 + h0 / 2.0 - (y1 + h1 / 2.0) - 10.0).abs() < 1.0, msg="\{y0} \{y1}")
  // the glyphs from the third on hidden: across both texts, in the order they read
  let t = glyphs_tester(2)
  t.draw()
  assert_eq(glyph_boxes(t).length(), 2)
}

///|
/// The full boxes of the monochrome glyphs just drawn.
fn glyph_rects(t : Tester) -> Array[(Double, Double, Double, Double)] {
  ignore(t)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 {
      out.push((c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3]))
    }
  }
  out
}

///|
test "a glyph moves and scales about its advance in plain and rich text" {
  for rich in [false, true] {
    let shown = fn(turned : Bool) {
      let cells : Ref[Array[(Double, Double)]] = Ref::new([])
      let t = Tester::new(fn(c) {
        let style = text_style(size=Sm, wrap=false)
        cells.val = c.words_glyph_cells("ab", style)
        let node = if rich { c.rich([span("ab")], style~) } else { c.text("ab", style~) }
        c.glyphs_by(node, fn(at) {
          if at.index == 0 && turned {
            { alpha: 1.0, dx: 7.0, dy: 3.0, scale: 1.0, sx: 0.75 }
          } else {
            { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
          }
        })
      })
      t.draw()
      let (_, x, _, _, _, _) = t.words().iter().find_first(fn(w) { w.0 == "ab" }).unwrap()
      (glyph_rects(t), x + cells.val[0].0)
    }
    let (before, cell_x) = shown(false)
    let (after, _) = shown(true)
    assert_eq(before.length(), 2)
    assert_eq(after.length(), 2)
    let (x, y, w, h) = before[0]
    let (nx, ny, nw, nh) = after[0]
    assert_true((nw - w * 0.75).abs() < 0.01 && (nx - cell_x - (x - cell_x) * 0.75 - 7.0).abs() < 0.01)
    assert_true((nh - h).abs() < 0.01 && (ny - y - 3.0).abs() < 0.01)
    assert_eq(before[1], after[1])
  }
}

///|
test "a line's glyph cells match the shaped rich words, including different widths and scripts" {
  for words in ["Wi 正在检查", "مرحبا", "á 😀"] {
    for mono in [false, true] {
      let cells : Ref[Array[(Double, Double)]] = Ref::new([])
      let t = Tester::new(fn(c) {
        let style = text_style(size=Sm, wrap=false)
        cells.val = c.words_glyph_cells(words, style, mono~)
        c.rich([span(words, mono~)], style~) |> ignore
      })
      t.draw()
      let (layout, _, _) = t.rich_of(words).unwrap()
      let expected : Array[(Double, Double)] = []
      for i in 0..<layout.keys.length() {
        if layout.keys[i] >= 0 {
          expected.push((layout.xs[i] + layout.adv[i] / 2.0, layout.adv[i]))
        }
      }
      assert_eq(cells.val.length(), expected.length(), msg=words)
      for i in 0..<expected.length() {
        assert_true((cells.val[i].0 - expected[i].0).abs() < 0.01 && (cells.val[i].1 - expected[i].1).abs() < 0.01, msg="\{words}: \{cells.val} / \{expected}")
      }
    }
  }
}

///|
/// The grounds (not glyphs) drawn in the last frame that show at all.
fn grounds_shown(t : Tester) -> Int {
  ignore(t)
  let c = g()
  let mut n = 0
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 && c.inst[b + 11] > 0.0 {
      n += 1
    }
  }
  n
}

///|
test "what is not a glyph comes with the glyph after it: a mark before a line's words hidden while its first is" {
  let first_shown = fn(shown : Bool) {
    Tester::new(fn(c) {
      let col = c.column(align=AStart, fn() {
        c.box(w=Px(6.0), h=Px(6.0), bg=0x2233AAFFL, fn() {  }) |> ignore
        c.text("ab") |> ignore
      })
      c.glyphs_by(col, fn(at) { { alpha: if at.index == 0 && !shown { 0.0 } else { 1.0 }, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 } })
    })
  }
  let t = first_shown(false)
  t.draw()
  assert_eq(grounds_shown(t), 0)
  let t = first_shown(true)
  t.draw()
  assert_eq(grounds_shown(t), 1)
}

///|
test "a glyph is told what cuts the node that says the looks, not a box of its own that cuts it (a code block's)" {
  let tops : Array[Double] = []
  let t = Tester::new(fn(c) {
    let col = c.column(align=AStart, fn() {
      c.text("ab") |> ignore
      c.box(w=Px(100.0), h=Px(40.0), clip=true, fn() { c.text("cd") |> ignore }) |> ignore
    })
    c.glyphs_by(col, fn(at) {
      tops.push(at.top)
      { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
    })
  })
  t.draw()
  assert_true(tops.length() >= 4)
  assert_true(tops.iter().all(fn(y) { y == tops[0] }), msg="\{tops}")
}

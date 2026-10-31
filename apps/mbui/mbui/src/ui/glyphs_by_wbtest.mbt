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
        { alpha: 0.0, dy: 0.0, scale: 1.0 }
      } else if i == 0 {
        { alpha: 1.0, dy: 10.0, scale: 0.5 }
      } else {
        { alpha: 1.0, dy: 0.0, scale: 1.0 }
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
      c.glyphs_by(col, fn(at) { { alpha: if at.index == 0 && !shown { 0.0 } else { 1.0 }, dy: 0.0, scale: 1.0 } })
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
      { alpha: 1.0, dy: 0.0, scale: 1.0 }
    })
  })
  t.draw()
  assert_true(tops.length() >= 4)
  assert_true(tops.iter().all(fn(y) { y == tops[0] }), msg="\{tops}")
}

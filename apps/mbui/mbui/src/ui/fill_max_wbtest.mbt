// A Fill across its parent, held to a max there (Ctx::flex_tree): as wide (high) as the parent up to its max, and
// placed as the parent places its children, as Compose's fillMaxWidth().widthIn(max) in a centred Column; in a
// parent that stretches or starts its children, at the start as before.

///|
let fill_max_ink : Int64 = 0xFF3B30FFL

///|
/// The rectangle (x, y, w, h) of the node filled `color` in the last frame.
fn rect_of_bg(color : Int64) -> (Double, Double, Double, Double) raise {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bg == color {
      return (n.x, n.y, n.fw, n.fh)
    }
  }
  fail("no node filled \{color}")
}

///|
/// A column `pw` wide aligning as `align`, holding a box as wide as it up to 28: where that box is.
fn in_column(align : Align, pw? : Double = 100.0) -> (Double, Double, Double, Double) raise {
  let t = Tester::new(fn(c) {
    c.box(align=AStart, fn() {
      c.box(w=Px(pw), h=Px(40.0), align~, fn() {
        c.box(w=Fill(1.0), max_w=28.0, h=Px(10.0), bg=fill_max_ink, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  rect_of_bg(fill_max_ink)
}

///|
test "fill across held to a max: in the middle of a centred column, at the end of an ending one" {
  let (x, _, w, _) = in_column(ACenter)
  assert_eq((x, w), (36.0, 28.0))
  let (x, _, w, _) = in_column(AEnd)
  assert_eq((x, w), (72.0, 28.0))
}

///|
test "fill across held to a max: at the start where the column starts or stretches what it holds" {
  let (x, _, w, _) = in_column(AStart)
  assert_eq((x, w), (0.0, 28.0))
  let (x, _, w, _) = in_column(AStretch)
  assert_eq((x, w), (0.0, 28.0))
}

///|
test "fill across held to a max: as wide as a column narrower than its max" {
  let (x, _, w, _) = in_column(ACenter, pw=20.0)
  assert_eq((x, w), (0.0, 20.0))
}

///|
test "fill across held to a max: high, in the middle of a row centring what it holds" {
  let t = Tester::new(fn(c) {
    c.box(align=AStart, fn() {
      c.box(dir=Row, w=Px(40.0), h=Px(100.0), align=ACenter, fn() {
        c.box(w=Px(10.0), h=Fill(1.0), max_h=28.0, bg=fill_max_ink, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (_, y, _, h) = rect_of_bg(fill_max_ink)
  assert_eq((y, h), (36.0, 28.0))
}

///|
test "fill across held to a max: a day's bar in the middle of its day, as wide as the day once days are narrow" {
  // (the usage page's days: `n` days 6 apart sharing a row `w` wide, each a bar at most 28 wide standing on its foot)
  let days = fn(n : Int, w : Double) -> Array[((Double, Double, Double, Double), (Double, Double, Double, Double))] raise {
    let t = Tester::new(fn(c) {
      c.box(align=AStart, fn() {
        c.box(dir=Row, w=Px(w), h=Px(150.0), gap=6.0, fn() {
          for i in 0..<n {
            c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JEnd, bg=0x10101000L + i.to_int64(), fn() {
              c.box(w=Fill(1.0), max_w=28.0, h=Px(60.0), bg=0xFF000000L + i.to_int64(), fn() {  }) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    let out = []
    for i in 0..<n {
      out.push((rect_of_bg(0x10101000L + i.to_int64()), rect_of_bg(0xFF000000L + i.to_int64())))
    }
    out
  }
  // seven days 38 wide: each bar 5 in from its day's sides
  for p in days(7, 302.0) {
    let ((dx, _, dw, _), (bx, by, bw, bh)) = p
    assert_eq(bw, 28.0)
    assert_eq(bx + bw / 2.0, dx + dw / 2.0)
    assert_eq((by, bh), (90.0, 60.0))
  }
  // thirty days 4 wide
  for p in days(30, 294.0) {
    let ((dx, _, dw, _), (bx, _, bw, _)) = p
    assert_eq((bx, bw), (dx, dw))
  }
}

///|
/// A column `pw` wide starting what it holds, a box in it as wide as its words (`Cut`) and at least 320 within the
/// column (`min_w=Within(320)`): where that box is.
fn within_column(pw : Double, words : String) -> (Double, Double, Double, Double) raise {
  let t = Tester::new(fn(c) {
    c.box(w=Px(pw), align=AStart, fn() {
      c.box(style=style(w=Cut, min_w=Within(320.0)), bg=fill_max_ink, pad=8.0, fn() {
        c.text(words, size=14.0) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  rect_of_bg(fill_max_ink)
}

///|
test "a least within the room: 320 where the column has it, the column's where it has less, its words' past it" {
  let (_, _, w, _) = within_column(600.0, "Keep it")
  assert_eq(w, 320.0)
  let (_, _, w, _) = within_column(300.0, "Keep it")
  assert_eq(w, 300.0)
  let (_, _, w, _) = within_column(600.0, "Keep the token for the deploys of tomorrow, and of the day after it")
  assert_true(w > 320.0 && w <= 600.0, msg="as wide as its words: \{w}")
}

// An old view as tall as what it holds at the width the tree gives it (old's `natural`): from the first frame it is
// drawn, and the frame after what it holds or its width changes, the node as tall as its content laid out at that
// width, what comes after it placed under that; shorter, smaller again; held by its window, the same whether opened in
// a short one and grown or opened in the tall one. Moved, faded, scaled: its body not built again.

///|
/// A window `w`×`h` whose tree holds a column: an old view `width` wide, as tall as what it holds (`rows` boxes 30 high,
/// then `words` wrapped), held to the window less 100; under it a marker. How many times its body was built, in `built`.
fn natural_tester(
  w : Double,
  h : Double,
  rows : @signals.Signal[Int],
  words : @signals.Signal[String],
  width : @signals.Signal[Double],
  at : @signals.Signal[(Double, Double)],
  alpha : @signals.Signal[Double],
  built : Ref[Int],
  ids : Map[String, @view.View],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w~, h~)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(w))) |> ignore
      let o = old(col, natural=true, fn(c) {
        built.val = built.val + 1
        c.box(w=Fill(1.0), fn() {
          for i in 0..<rows.get() {
            c.box(w=Fill(1.0), h=Px(30.0), fn() { c.text("行\{i}", wrap=false) |> ignore }) |> ignore
          }
          c.text(words.get(), wrap=true) |> ignore
        })
        |> ignore
      })
      o
      .width(By(fn() { Some(width.get()) }))
      .max_height(By(fn() { Some(o.window().1 - 100.0) }))
      .offset(By(fn() { at.get() }))
      .alpha(By(fn() { alpha.get() }))
      |> ignore
      ids["old"] = o
      col.box(fn(m) {
        ids["marker"] = m
        m.height(Is(Some(10.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // (the first frame the tree is drawn: what is read is that one's)
  t.frame()
  t
}

///|
/// Where node `v` is laid out (x, y, w, h).
fn laid_of(v : @view.View) -> (Double, Double, Double, Double) {
  let tree = view_tree().unwrap()
  let (x, y) = tree.laid_origin(v.id()).unwrap_or((-1.0, -1.0))
  let (w, h) = v.laid_size()
  (x, y, w, h)
}

///|
/// The old view's height, what it holds laid out at its width (its outermost box's height, as the old frame laid it
/// out), and the marker's top less the old view's foot.
fn natural_said(t : Tester, ids : Map[String, @view.View]) -> (Double, Double, Double) {
  ignore(t)
  let (_, oy, _, oh) = laid_of(ids["old"])
  let (_, my, _, _) = laid_of(ids["marker"])
  (oh, natural_content_h(), my - (oy + oh))
}

///|
/// What the old view holds, laid out: its outermost box's height (the one under the island's own).
fn natural_content_h() -> Double {
  let c = g()
  let mut h = -1.0
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.text.has_prefix("行") || n.text.has_prefix("词") {
      // (its column: the box holding the rows and the words)
      let p = n.parent
      if p >= 0 {
        let q = c.nodes[p]
        let col = if n.text.has_prefix("行") { q.parent } else { p }
        if col >= 0 {
          h = c.nodes[col].fh
        }
      }
    }
  }
  h
}

///|
test "old natural: as tall as what it holds the first frame, and as it grows, narrows and shrinks; the next node under it" {
  let rows = @signals.signal(3)
  let words = @signals.signal("词 " + "一二三四五六七八九十".repeat(3))
  let width = @signals.signal(240.0)
  let at = @signals.signal((0.0, 0.0))
  let alpha = @signals.signal(1.0)
  let built = Ref(0)
  let ids : Map[String, @view.View] = {}
  let t = natural_tester(400.0, 800.0, rows, words, width, at, alpha, built, ids)
  let first = natural_said(t, ids)
  rows.set(5)
  t.frame()
  let grown = natural_said(t, ids)
  width.set(120.0)
  t.frame()
  let narrowed = natural_said(t, ids)
  rows.set(1)
  words.set("词")
  t.frame()
  let shrunk = natural_said(t, ids)
  let ok = fn(s : (Double, Double, Double)) { s.0 > 0.0 && s.0 == s.1 && s.2 == 0.0 }
  assert_eq(
    (ok(first), ok(grown), grown.0 > first.0, ok(narrowed), narrowed.0 > grown.0, ok(shrunk), shrunk.0 < narrowed.0),
    (true, true, true, true, true, true, true),
    msg="first \{first} grown \{grown} narrowed \{narrowed} shrunk \{shrunk}",
  )
}

///|
test "old natural: held by a short window and grown, the same as opened in the tall one" {
  let mk = fn(h : Double) {
    let rows = @signals.signal(12)
    let built = Ref(0)
    let ids : Map[String, @view.View] = {}
    let t = natural_tester(400.0, h, rows, @signals.signal("词"), @signals.signal(240.0), @signals.signal((0.0, 0.0)), @signals.signal(1.0), built, ids)
    (t, ids)
  }
  let (short, sids) = mk(300.0)
  let held = laid_of(sids["old"])
  short.resize_next(400.0, 800.0)
  short.frame()
  let grown = (laid_of(sids["old"]), laid_of(sids["marker"]))
  let (_, tids) = mk(800.0)
  let tall = (laid_of(tids["old"]), laid_of(tids["marker"]))
  // (its node cut to the window less 100 while short; tall, as tall as what it holds: 12 rows of 30 and a line of words)
  assert_eq((held.3 == 200.0, grown, tall.0.3 == natural_content_h(), tall.0.3 > 360.0), (true, tall, true, true), msg="held \{held} tall \{tall}")
}

///|
test "old natural: moved, faded: painted alone, nothing built nor laid out, its height the same" {
  let rows = @signals.signal(3)
  let at = @signals.signal((0.0, 0.0))
  let alpha = @signals.signal(1.0)
  let built = Ref(0)
  let ids : Map[String, @view.View] = {}
  let t = natural_tester(400.0, 800.0, rows, @signals.signal("词"), @signals.signal(240.0), at, alpha, built, ids)
  let h = laid_of(ids["old"]).3
  // (laid out the same twice: what comes after it may be painted alone, as island_moved_wbtest has it)
  t.clock_frame()
  t.clock_frame()
  // (each frame after a move or a fade painted alone: nothing built nor laid out, the Tester's own check drawing it
  // whole after it and comparing, as ever)
  let alone = fn(change : () -> Unit) {
    change()
    let was = paints_alone.val
    t.clock_frame()
    paints_alone.val - was == 1
  }
  let moved = alone(fn() { at.set((20.0, 15.0)) })
  let faded = alone(fn() { alpha.set(0.5) })
  assert_eq((moved, faded, laid_of(ids["old"]).3), (true, true, h))
}

///|
test "old natural: the one old view, as tall as the window, then shorter: smaller that frame" {
  let rows = @signals.signal(10)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let held : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    held.val = Some(
      old(root, natural=true, fn(c) {
        for i in 0..<rows.get() {
          c.box(w=Fill(1.0), h=Px(30.0), fn() {  }) |> ignore
          ignore(i)
        }
      }),
    )
  })
  t.frame()
  let whole = laid_of(held.val.unwrap()).3
  rows.set(4)
  t.frame()
  assert_eq((whole, laid_of(held.val.unwrap()).3), (300.0, 120.0))
}

///|
test "old natural: scaled: laid out as tall as it was, what comes after where it was, drawn at that scale, painted alone" {
  let s = @signals.signal(1.0)
  let ids : Map[String, @view.View] = {}
  let t = Tester::new(fn(_c) {  }, w=400.0, h=800.0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))) |> ignore
      let o = old(col, natural=true, fn(c) {
        for i in 0..<4 {
          // (the second row's a block 100 by 30 of its own colour, what it draws)
          if i == 1 {
            c.box(w=Px(100.0), h=Px(30.0), bg=natural_mark, fn() {  }) |> ignore
          } else {
            c.box(w=Fill(1.0), h=Px(30.0), fn() {  }) |> ignore
          }
        }
      })
      o.width(Is(Some(240.0))).scale(By(fn() { s.get() }), about=At(0.0, 0.0)) |> ignore
      ids["old"] = o
      col.box(fn(m) {
        ids["marker"] = m
        m.height(Is(Some(10.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.frame()
  t.clock_frame()
  t.clock_frame()
  let (before, marker) = (laid_of(ids["old"]), laid_of(ids["marker"]))
  let block = fn() { t.drawn_rects().filter(fn(r) { r.4 == natural_mark }).map(fn(r) { (r.0, r.1, r.2, r.3) }) }
  let whole = block()
  s.set(0.5)
  let was = paints_alone.val
  t.clock_frame()
  let alone = paints_alone.val - was == 1
  // (drawn half as big about its top left: the block where it was from there, by half, half as big)
  let (ox, oy) = (before.0, before.1)
  let half = whole.map(fn(r) { (ox + (r.0 - ox) * 0.5, oy + (r.1 - oy) * 0.5, r.2 * 0.5, r.3 * 0.5) })
  assert_eq(
    (before.3, laid_of(ids["old"]), laid_of(ids["marker"]), whole.length(), block(), alone),
    (120.0, before, marker, 1, half, true),
    msg="whole \{whole}",
  )
}

///|
/// The colour of the block an old view as tall as what it holds draws, where it is drawn (its scale's case).
let natural_mark : Int64 = 0x33AA55FFL

///|
test "old natural: holding a row that grows in its column, a box in it scrolling past 100 (Ctx::capped past_most, a panel's column of its own): as tall as that box shows, 100, whatever the window, from the first frame" {
  let out = []
  for h in [800.0, 300.0] {
    let ids : Map[String, @view.View] = {}
    let t = Tester::new(fn(_c) {  }, w=400.0, h~)
    set_view_app(fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(400.0))) |> ignore
        let o = old(col, natural=true, fn(c) {
          c.box(style=style(row=true, w=Full, h=Grow(1.0)), fn() {
            c.capped("rows", 100.0, past_most=true, fn() {
              for _ in 0..<10 {
                c.box(w=Fill(1.0), h=Px(30.0), fn() {  }) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        })
        o.width(Is(Some(240.0))) |> ignore
        ids["old"] = o
      })
      |> ignore
    })
    t.frame()
    let first = laid_of(ids["old"]).3
    t.clock_frame()
    out.push((first, laid_of(ids["old"]).3))
  }
  assert_eq(out, [(100.0, 100.0), (100.0, 100.0)])
}

///|
/// A box 100 by 50 (taller than a press's room: its own edges where it takes one) under one 10.4 tall (a place off the pixels), read out "old block" and its presses counted into
/// `pressed`: the old frame's own, one under the other (`how` 0); an old view as tall as what it holds under a node of
/// the window's tree 10.4 tall (1); or in a node of the tree's moved down 10.4 (View::offset, 2). Where it is drawn and read out, and how many times it was pressed by a press just
/// over its top edge and one just under it.
fn off_pixels_block(how : Int) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), Int, Int) {
  let pressed = Ref(0)
  let block = fn(c : Ctx) {
    let id = c.id("old block")
    if c.clicked(id) {
      pressed.val = pressed.val + 1
    }
    let b = c.box(w=Px(100.0), h=Px(50.0), bg=natural_mark, id~, fn() {  })
    c.semantics(b, Button, id~, label="old block")
  }
  let t = if how > 0 {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
    set_view_app(fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(400.0))) |> ignore
        if how == 1 {
          col.box(fn(top) { top.height(Is(Some(10.4))) |> ignore }) |> ignore
          old(col, natural=true, fn(c) { block(c) }).width(Is(Some(240.0))) |> ignore
        } else {
          col.box(fn(moved) {
            moved.offset(Is((0.0, 10.4))) |> ignore
            old(moved, natural=true, fn(c) { block(c) }).width(Is(Some(240.0))) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    t
  } else {
    Tester::new(
      fn(c) {
        c.box(w=Px(400.0), fn() {
          c.box(w=Px(240.0), h=Px(10.4), fn() {  }) |> ignore
          block(c)
        })
        |> ignore
      },
      w=400.0,
      h=300.0,
      platform=0,
    )
  }
  t.frame()
  t.clock_frame()
  let f = fn(r : (Double, Double, Double, Double)) {
    let g = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
    (g(r.0), g(r.1), g(r.2), g(r.3))
  }
  let drawn = t.drawn_rects().filter(fn(r) { r.4 == natural_mark }).map(fn(r) { f((r.0, r.1, r.2, r.3)) })
  let read = f(t.query(Button, label="old block").unwrap().rect)
  t.tap(50.0, 10.35)
  t.draw()
  let over = pressed.val
  t.tap(50.0, 10.45)
  t.draw()
  (drawn.get(0).unwrap_or((-1.0, -1.0, -1.0, -1.0)), read, over, pressed.val - over)
}

///|
test "old natural: laid out under a node 10.4 tall, or in one moved down 10.4 (a place off the pixels): drawn, read out and pressed there, as the old frame's own one under the other is, not its top moved onto the pixels" {
  let own = off_pixels_block(0)
  assert_eq(
    (own, off_pixels_block(1), off_pixels_block(2)),
    (((0.0, 10.4, 100.0, 50.0), (0.0, 10.4, 100.0, 50.0), 0, 1), own, own),
  )
}

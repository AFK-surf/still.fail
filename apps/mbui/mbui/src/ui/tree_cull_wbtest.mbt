// An old view in the window's tree painted as the window shows it: what of it lies outside the window not painted
// (no glyph of its words asked of the host, none drawn), as the old frame paints what lies outside it; its targets
// found whole.

///|
/// An old view 400 by 200 in a window 400 wide beside a box of the tree's own (so that it is not the whole window),
/// the old view placed by the tree as `at` says, what it holds placed in it as `inner` says: words (where `words`) and
/// a button, what was clicked kept in `clicks`. Drawn.
fn culled_tester(
  at : @signals.Signal[Double],
  inner : @signals.Signal[Double],
  words : Bool,
  clicks : Ref[Int],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      // (a box of the tree's own: the old view no more the whole window)
      b.box(fn(g) { g.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).ground(Is(0x3366CCFFL)) |> ignore })
      |> ignore
      old(b, fn(c) {
        c.box(w=Px(400.0), h=Px(200.0), ml=inner.get(), fn() {
          if words {
            c.text("far words", wrap=false) |> ignore
          }
          let id = c.id("go")
          if c.clicked(id) {
            clicks.val = clicks.val + 1
          }
          c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
        })
        |> ignore
      })
      .over(Is(true))
      .width(Is(Some(400.0)))
      .height(Is(Some(200.0)))
      .offset(By(fn() { (at.get(), 0.0) }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// How many glyphs the host was asked to make so far (the text cache's, a Tester's own from its start).
fn glyphs_asked() -> Int {
  text_cache.glyphs.length()
}

///|
/// How many glyphs the last frame drew.
fn glyphs_drawn() -> Int {
  let c = g()
  let mut n = 0
  for k in 0..<c.ninst {
    let kind = c.inst[k * inst_size + 5]
    if kind == 1.0 || kind == 3.0 || kind == 7.0 {
      n += 1
    }
  }
  n
}

///|
/// The glyphs asked of the host with the old view placed `at` across by the tree and what it holds `inner` across in
/// it, with its words and without them; and whether it was the whole window.
fn culled_asked(at : Double, inner : Double) -> (Int, Int, Bool) {
  let n = fn(words : Bool) {
    culled_tester(
      @signals.signal(at, same=fn(a, b) { a == b }),
      @signals.signal(inner, same=fn(a, b) { a == b }),
      words,
      Ref(0),
    )
    |> ignore
    glyphs_asked()
  }
  let drawn = n(true)
  let whole = old_whole.val
  (drawn, n(false), whole)
}

///|
test "an old view in the window's tree, it or what it holds outside the window: no glyph of its words asked of the host; in it, asked" {
  let (drawn, without, whole) = culled_asked(0.0, 0.0)
  assert_false(whole, msg="not the whole window")
  assert_true(drawn > without, msg="in the window: \{drawn} with its words, \{without} without")
  assert_eq(culled_asked(500.0, 0.0), (without, without, false), msg="the old view past the right edge")
  assert_eq(culled_asked(-500.0, 0.0), (without, without, false), msg="the old view past the left edge")
  assert_eq(culled_asked(0.0, 500.0), (without, without, false), msg="what it holds past the right edge")
}

///|
test "an old view in the window's tree moved by the tree out past the right edge, half in, out past the left, back: its words drawn only as they show; back with no frame drawn, its button pressed" {
  let at = @signals.signal(500.0, same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let t = culled_tester(at, @signals.signal(0.0, same=fn(a, b) { a == b }), true, clicks)
  assert_false(old_whole.val, msg="not the whole window")
  assert_eq(glyphs_drawn(), 0, msg="out past the right edge")
  at.set(200.0)
  t.draw()
  assert_true(glyphs_drawn() > 0, msg="half in")
  at.set(-500.0)
  t.draw()
  assert_eq(glyphs_drawn(), 0, msg="out past the left edge")
  at.set(0.0)
  // (no frame drawn before the press: where the tree has it as the press comes; the button below its words)
  t.press_at(40.0, 40.0)
  t.release(40.0, 40.0)
  t.draw()
  assert_eq(clicks.val, 1, msg="its button pressed as it is back")
  assert_true(glyphs_drawn() > 0, msg="drawn back in the window")
}

///|
/// Words of the tree's own 60 wide, many lines, placed `dy` down in a window 400 by `h`: the tester, and where they are.
fn tall_words(dy : Double, h? : Double = 200.0) -> (Tester, @signals.Signal[Double]) {
  let at = @signals.signal(dy, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h~)
  t.check_looks(false)
  let words = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen"
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(h))) |> ignore
      b.box(fn(w) {
        w.over(Is(true)).width(Is(Some(60.0))).words(Is(words)).offset(By(fn() { (0.0, at.get()) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, at)
}

///|
/// Where the last frame drew glyphs whose tops are within the first 200 down: (x, y), in order.
fn glyphs_in_top() -> Array[(Double, Double)] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5]
    if (kind == 1.0 || kind == 3.0 || kind == 7.0) && c.inst[b + 1] >= 0.0 && c.inst[b + 1] < 200.0 {
      out.push((c.inst[b], c.inst[b + 1]))
    }
  }
  out.sort()
  out
}

///|
test "words of the tree's own taller than the window, first drawn with their foot below it, then moved up alone: made once, whole; what shows of them as words drawn in a window tall enough for all show there" {
  let (t, at) = tall_words(100.0)
  let made = view_painted().made
  at.set(-200.0)
  t.draw()
  assert_eq(view_painted().made, made, msg="made once: none made again as they move")
  let moved = glyphs_in_top()
  // (all of them laid out in a window tall enough, moved so, what is within the first 200 of it)
  tall_words(-200.0, h=600.0) |> ignore
  let whole = glyphs_in_top()
  assert_true(whole.length() > 0, msg="some of them within it")
  assert_eq(moved, whole, msg="what shows of them, where")
}

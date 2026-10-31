// A node's words in pieces each set its own way (View::words_runs): laid out, measured and drawn as an old view's
// paragraph in the same pieces is (Ctx::rich), at the system's size of words, in the theme's digits.

///|
/// The same words in pieces drawn by an old view (Ctx::rich) at (0, 0) and by a node 200 down, each `w` wide at most,
/// both in `theme`; how wide and tall the node is laid out.
fn runs_pair(pieces : Array[(String, Int, Int64)], w : Double, theme : Theme) -> (Tester, () -> (Double, Double)) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  t.check_looks(false)
  t.ctx().set_theme(theme)
  let id : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.width(Is(Some(w))).height(Is(Some(200.0))) |> ignore
      old(h, fn(c) {
        c.box(w=Px(w), fn() {
          c.rich(pieces.map(fn(p) { span(p.0, weight=p.1, color=p.2) }), size=15.0, line=22.0, color=0x333333FFL)
          |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b.width(Is(Some(w))).lines_up(Is(Some(Start))) |> ignore
      b.box(fn(n) {
        id.val = Some(n.id())
        n
        .words_runs(Is(pieces.map(fn(p) { @view.words_run(p.0, weight=p.1, ink=p.2) })), ink=0x333333FFL, look={
          size: 15.0,
          weight: 400,
          line: 22.0,
          wrap: true,
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = view_app.val.unwrap()
  (t, fn() {
    let d = tree.drawn_of(id.val.unwrap()).unwrap()
    (d.w, d.h)
  })
}

///|
/// The glyphs drawn above 200 and below it, those below moved up by 200: (x, y, colour).
fn runs_drawn(t : Tester) -> (Array[(Double, Double, Int64)], Array[(Double, Double, Int64)]) {
  let old = t.drawn_glyphs().filter(fn(g) { g.1 < 200.0 })
  let new = t.drawn_glyphs().filter(fn(g) { g.1 >= 200.0 }).map(fn(g) { (g.0, g.1 - 200.0, g.2) })
  (old, new)
}

///|
test "words in pieces on a node: each piece in its weight and ink (else the words' and the node's), drawn where an old view draws the same paragraph; wrapped as it wraps; the words read whole" {
  let pieces = [("正在读取 ", 0, 0L), ("1.2 MB", 600, 0x111111FFL), (" / 3.4 MB", 0, 0L)]
  let (t, laid) = runs_pair(pieces, 300.0, { ..Theme::light(), tabular: true })
  let (old, new) = runs_drawn(t)
  assert_true(old.length() > 10, msg="the old one drawn: \{old.length()}")
  assert_eq(new, old)
  assert_true(new.any(fn(g) { g.2 == 0x111111FFL }) && new.any(fn(g) { g.2 == 0x333333FFL }), msg="each piece its ink")
  let (w, h) = laid()
  assert_true(w > 0.0 && w < 300.0 && h == 22.0, msg="one line, as wide as it is: \{w} by \{h}")
  assert_true(t.find("正在读取 1.2 MB / 3.4 MB") is Some(_), msg="read whole")
  // (narrower than it is: wrapped where the old one wraps)
  let (t, laid) = runs_pair(pieces, 80.0, Theme::light())
  let (old, new) = runs_drawn(t)
  assert_eq(new, old, msg="wrapped")
  assert_true(laid().1 > 22.0, msg="more than a line: \{laid()}")
}

///|
/// A node's words, `words` plain (`pieces` None) or in pieces (each its weight and ink), as made in a window 300 by 200
/// whose tree is drawn in a theme with digits all one width while `tabular` says (told by the app as it makes its tree,
/// set_tree_theme), the digits set so 0.5 em wider, where `at` puts it (its offset), `w` wide at most; its words and how
/// they are set the same throughout. How big it is as drawn, and as laid out now (no frame: View::laid_size).
fn shaped_words(
  words : String,
  pieces : Array[(String, Int, Int64)]?,
  tabular : @signals.Signal[Bool],
  at : @signals.Signal[Double],
  w? : Double = 280.0,
  face? : Bool = false,
) -> (Tester, () -> (Double, Double), () -> (Double, Double)) {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  t.check_looks(false)
  t.tabular_wider(0.5)
  t.ui_face_wider(0.1)
  let node : Ref[@view.View?] = Ref(None)
  let look : @view.WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: true }
  set_view_app(fn(root) {
    set_tree_theme(fn() { { ..Theme::light(), tabular: tabular.get() } })
    // (the app's words' face given before any words are made, `face`)
    if face {
      ignore(face_add(@hostapi.face_ui, "/fonts/ui.ttf"))
    }
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(n) {
      node.val = Some(n)
      n.max_width(Is(Some(w))).offset(By(fn() { (0.0, at.get()) })) |> ignore
      match pieces {
        None => n.words(Is(words), ink=0x333333FFL, look~) |> ignore
        Some(ps) =>
          n.words_runs(Is(ps.map(fn(p) { @view.words_run(p.0, weight=p.1, ink=p.2) })), ink=0x333333FFL, look~)
          |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  let tree = view_app.val.unwrap()
  (
    t,
    fn() {
      let d = tree.drawn_of(node.val.unwrap().id()).unwrap()
      (d.w, d.h)
    },
    fn() { node.val.unwrap().laid_size() },
  )
}

///|
test "a node's words shaped as the tree's theme says, the app's told as it makes its tree: its digits all one width or not, as that alone changes, laid out so at once (no frame between), drawn so in the first frame after, plain words and words in pieces; as if made so" {
  for pieces in [None, Some([("12 ", 0, 0L), ("345", 600, 0L)])] {
    let what = if pieces is None { "plain" } else { "in pieces" }
    let tabular = @signals.signal(false, same=fn(a, b) { a == b })
    let at = @signals.signal(0.0, same=fn(a, b) { a == b })
    let (t, drawn, laid) = shaped_words("12 345", pieces, tabular, at)
    let (narrow, _) = drawn()
    let glyphs_narrow = t.drawn_glyphs()
    tabular.set(true)
    let (wide, _) = laid()
    assert_true(wide > narrow, msg="\{what}: digits all one width, laid out wider at once, no frame: \{narrow} then \{wide}")
    t.draw()
    assert_eq(drawn().0, wide, msg="\{what}: drawn as laid out")
    let glyphs_wide = t.drawn_glyphs()
    // (as one made in that theme from the start)
    let (fresh, fresh_drawn, _) = shaped_words("12 345", pieces, @signals.signal(true), @signals.signal(0.0))
    assert_eq(fresh_drawn().0, wide, msg="\{what}: as wide as one made so")
    assert_eq(fresh.drawn_glyphs(), glyphs_wide, msg="\{what}: drawn as one made so")
    // (back, and there and back with no frame between: as it is told last)
    let (t, drawn, laid) = shaped_words("12 345", pieces, tabular, at)
    tabular.set(false)
    assert_eq(laid().0, narrow, msg="\{what}: back at once")
    tabular.set(true)
    assert_eq(laid().0, wide, msg="\{what}: wide again at once")
    tabular.set(false)
    t.draw()
    assert_eq(drawn().0, narrow, msg="\{what}: drawn back")
    assert_eq(t.drawn_glyphs(), glyphs_narrow, msg="\{what}: its glyphs back")
  }
}

///|
test "a node's words made whole, longer than the window is tall: moved so their last line comes in, the same content composed there (not made again), its last line seen whole, plain words and words in pieces (its last piece in its own ink)" {
  let long = StringBuilder()
  for i in 0..<40 {
    long.write_string("w\{i} ")
  }
  let long = long.to_string()
  let red = 0xCC0000FFL
  for pieces in [None, Some([(long, 0, 0L), ("end", 0, red)])] {
    let what = if pieces is None { "plain" } else { "in pieces" }
    let tabular = @signals.signal(false, same=fn(a, b) { a == b })
    let at = @signals.signal(0.0, same=fn(a, b) { a == b })
    let (t, drawn, _) = shaped_words(long + "end", pieces, tabular, at, w=40.0)
    let (_, h) = drawn()
    assert_true(h > 600.0, msg="\{what}: far taller than the window: \{h}")
    // (its last line, "end", on a line of its own, seen nowhere yet)
    let last_line = fn() { t.glyphs_shown().filter(fn(g) { g.1 >= 200.0 - 22.0 && g.3 <= 200.0 + 0.5 }) }
    let made = view_paint_work.made
    at.set(200.0 - h)
    t.draw()
    assert_eq(view_paint_work.made, made, msg="\{what}: moved, not made again")
    assert_eq(last_line().length(), 3, msg="\{what}: its last line seen whole, its three glyphs: \{last_line()}")
    if pieces is Some(_) {
      let inked = t.drawn_glyphs().filter(fn(g) { g.2 == red && g.1 >= 200.0 - 22.0 && g.1 < 200.0 })
      assert_eq(inked.length(), 3, msg="\{what}: the last piece in its ink, there")
    }
  }
}

///|
test "a node's words measured and drawn again in the app's words' face as it is given, at once (no frame between), and back as it goes: plain words and words in pieces, as wide as one made in it" {
  for pieces in [None, Some([("界面", 0, 0L), ("草图.png", 600, 0L)])] {
    let what = if pieces is None { "plain" } else { "in pieces" }
    let (t, drawn, laid) = shaped_words("界面草图.png", pieces, @signals.signal(false), @signals.signal(0.0))
    let (w0, _) = drawn()
    assert_true(face_add(@hostapi.face_ui, "/fonts/ui.ttf"), msg="given")
    let (w1, _) = laid()
    assert_true(w1 > w0 + 1.0, msg="\{what}: in it at once, no frame: \{w0} then \{w1}")
    t.draw()
    assert_eq(drawn().0, w1, msg="\{what}: drawn so")
    let glyphs = t.drawn_glyphs()
    face_clear(@hostapi.face_ui)
    assert_eq(laid().0, w0, msg="\{what}: its face gone, back at once")
    // (as one made in it from the start)
    let (fresh, fresh_drawn, _) = shaped_words(
      "界面草图.png",
      pieces,
      @signals.signal(false),
      @signals.signal(0.0),
      face=true,
    )
    assert_eq(fresh_drawn().0, w1, msg="\{what}: as wide as one made in it")
    assert_eq(fresh.drawn_glyphs(), glyphs, msg="\{what}: drawn as one made in it")
    face_clear(@hostapi.face_ui)
  }
}

///|
/// Where in the atlas each glyph drawn at or below `y0` is drawn from (its instance's u, v), in the order drawn.
fn glyphs_from(y0 : Double) -> Array[(Double, Double)] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 && c.inst[b + 1] >= y0 {
      out.push((c.inst[b + 12], c.inst[b + 13]))
    }
  }
  out
}

///|
test "a node's words made once, drawn frame after frame while an old view draws more glyphs than the atlas holds: its content composed again, not made again, its glyphs kept where they are in the atlas, drawn from where it has them" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  // (each glyph 500 pixels a side at 2 a point: one to a plot, sixteen plots hold 16)
  t.glyph_box(250.0, 250.0)
  let round = @signals.signal(0, same=fn(a, b) { a == b })
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(400.0))).height(Is(Some(100.0))) |> ignore
      // (eight new glyphs a frame)
      old(h, fn(c) {
        let r = round.get()
        let sb = StringBuilder()
        for i in 0..<8 {
          sb.write_char((0x4E00 + r * 8 + i).unsafe_to_char())
        }
        c.text(sb.to_string(), size=15.0, wrap=false) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(n) {
      n.words(Is("AB"), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: false }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let made = view_paint_work.made
  for r in 1..=16 {
    round.set(r)
    t.draw()
    assert_eq(view_paint_work.made, made, msg="its content made once, composed again")
    // (each of its glyphs drawn from where the atlas has that glyph now)
    let want = ['A', 'B'].map(fn(ch) {
      match text_cache.glyphs.get(ch.to_int()) {
        Some(gl) => (gl.u, gl.v)
        None => (-1.0, -1.0)
      }
    })
    assert_eq(glyphs_from(100.0), want, msg="after \{r * 8} more glyphs")
  }
}

///|
/// Each glyph drawn at or below `y0` (its instance's u, v) and where the atlas has the glyph of each of `words`' letters
/// now (-1, -1: nowhere), in the order drawn: what is drawn and what it should be drawn from.
fn drawn_and_held(y0 : Double, words : String) -> (Array[(Double, Double)], Array[(Double, Double)]) {
  let want = []
  for ch in words {
    match text_cache.glyphs.get(ch.to_int()) {
      Some(gl) if gl.gw > 0.0 => want.push((gl.u, gl.v))
      _ => want.push((-1.0, -1.0))
    }
  }
  (glyphs_from(y0), want)
}

///|
/// `n` letters from `first` on, each its own glyph.
fn letters(first : Int, n : Int) -> String {
  let sb = StringBuilder()
  for i in 0..<n {
    sb.write_char((first + i).unsafe_to_char())
  }
  sb.to_string()
}

///|
test "a node's words hidden (what holds them faded out) hold no room in the atlas: another node's words, as many as fill it, drawn whole; the first shown again, drawn whole too" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  // (each glyph 240 pixels a side at 2 a point: four to a plot, sixteen plots hold 64)
  t.glyph_box(120.0, 120.0)
  let first_shown = @signals.signal(true, same=fn(a, b) { a == b })
  let second_there = @signals.signal(false, same=fn(a, b) { a == b })
  let (one, two) = (letters(0x4E00, 40), letters(0x5000, 40))
  let look : @view.WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: false }
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.alpha(By(fn() { if first_shown.get() { 1.0 } else { 0.0 } })) |> ignore
      h.box(fn(n) { n.offset(Is((0.0, 100.0))).words(Is(one), ink=0x333333FFL, look~) |> ignore }) |> ignore
    })
    |> ignore
    root.show(fn() { second_there.get() }, fn(b) {
      b.offset(Is((0.0, 200.0))).words(Is(two), ink=0x333333FFL, look~) |> ignore
    })
  })
  t.draw()
  let (drawn, want) = drawn_and_held(100.0, one)
  assert_eq(drawn, want, msg="the first whole")
  first_shown.set(false)
  second_there.set(true)
  t.draw()
  let (drawn, want) = drawn_and_held(200.0, two)
  assert_true(!want.contains((-1.0, -1.0)), msg="the second's glyphs each in the atlas: \{want}")
  assert_eq(drawn, want, msg="the second whole, drawn from them")
  second_there.set(false)
  first_shown.set(true)
  t.draw()
  let (drawn, want) = drawn_and_held(100.0, one)
  assert_true(!want.contains((-1.0, -1.0)), msg="the first shown again: its glyphs each in the atlas")
  assert_eq(drawn, want, msg="the first shown again, whole")
}

///|
test "a node's words made as the atlas has no room for them this frame (an old view's words fill it): drawn whole in the first frame there is room, their words and look the same; the frame after composed again, not made again" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  // (each glyph 240 pixels a side at 2 a point: four to a plot, sixteen plots hold 64)
  t.glyph_box(120.0, 120.0)
  // (which 64 new letters an old view draws, as one paints them anew in a frame: -1 none)
  let crowd = @signals.signal(0, same=fn(a, b) { a == b })
  let there = @signals.signal(false, same=fn(a, b) { a == b })
  let word = letters(0x6000, 4)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(400.0))).height(Is(Some(100.0))) |> ignore
      // (the atlas filled by an old view's words painted in this frame: 64 glyphs on lines of their own, none cut short,
      // every plot drawn from in it)
      old(h, fn(c) {
        let k = crowd.get()
        if k >= 0 {
          c.text(letters(0x4E00 + k * 64, 64), size=15.0, wrap=true) |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { there.get() }, fn(n) {
      n.offset(Is((0.0, 100.0))).words(Is(word), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: false }) |> ignore
    })
  })
  t.draw()
  // (the node made in a frame the old view paints 64 other letters in: every plot drawn from, none for it)
  crowd.set(1)
  there.set(true)
  t.draw()
  let (_, want) = drawn_and_held(100.0, word)
  assert_true(want.contains((-1.0, -1.0)), msg="no room for some of it as it is made: \{want}")
  // (the old view's words gone: room again; the node's words and look the same)
  crowd.set(-1)
  t.draw()
  let (drawn, want) = drawn_and_held(100.0, word)
  assert_true(!want.contains((-1.0, -1.0)), msg="room again, the first frame: its glyphs each in the atlas: \{want}")
  assert_eq(drawn, want, msg="drawn whole the first frame there is room")
  // (the frame after: the same, its content composed again, not made again)
  let made = view_paint_work.made
  t.draw()
  let (drawn_after, want_after) = drawn_and_held(100.0, word)
  assert_eq((drawn_after, want_after), (drawn, want), msg="the frame after: the same")
  assert_eq(view_paint_work.made, made, msg="the frame after: not made again")
}

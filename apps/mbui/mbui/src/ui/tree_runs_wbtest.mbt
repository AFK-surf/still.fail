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

///|
test "the pointer within a node under an old view's layer over all of it: within as where it is says, the layer opened and closed over a pointer that stays, moved under it, never told otherwise; what it points at, its shape and the press the layer's; out of the window, or a finger, not within as it is told" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let told : Array[Bool] = []
  let band_id : Ref[@view.NodeId?] = Ref(None)
  let layer_pressed = Ref(false)
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(band) {
      band_id.val = Some(band.id())
      band.width(Is(Some(400.0))).height(Is(Some(40.0))).on_press(fn() {  }).cursor(Is(Some(ResizeY))) |> ignore
      // (the old view over it takes presses only where it draws: old_takes_own)
      band.reacts(fn() { band.pointer_within() }, fn(w) { told.push(w) })
    })
    |> ignore
    old(root, fn(c) {
      if open.get() {
        c.overlay("over all", fn() {
          let id = c.id("layer")
          c.box(w=Px(400.0), h=Px(300.0), id~, bg=0x0000FF40L, fn() {  }) |> ignore
          c.cursor(id, Crosshair)
          if c.pressed(id) {
            layer_pressed.val = true
          }
        })
        |> ignore
      }
    }).over(Is(true))
    |> old_takes_own
    |> ignore
  })
  t.draw()
  t.move(20.0, 20.0)
  let tree = view_app.val.unwrap()
  assert_true(told.last() == Some(true), msg="within, nothing over it: \{told}")
  assert_true(tree.pointed_now() == band_id.val, msg="pointed at, nothing over it")
  assert_eq(t.cursor(), ResizeY, msg="its shape, nothing over it")
  // (the layer opened over the pointer that stays, the frames after it; moved under it; closed: never told otherwise)
  let from = told.length()
  open.set(true)
  t.draw()
  t.draw()
  assert_true(tree.pointed_now() is None, msg="what it points at the layer's")
  assert_eq(t.cursor(), Crosshair, msg="the layer's shape")
  t.move(30.0, 25.0)
  t.draw()
  t.touch(0, 30.0, 25.0)
  t.draw()
  assert_true(layer_pressed.val, msg="the press the layer's")
  t.touch(2, 30.0, 25.0)
  t.draw()
  open.set(false)
  t.draw()
  t.draw()
  assert_eq(t.cursor(), ResizeY, msg="its shape again, the layer gone")
  assert_true(!told[from:].iter().any(fn(w) { !w }), msg="never told it is not within: \{told[from:]}")
  assert_true(@signals.untracked(fn() { told.last() }) == Some(true), msg="within throughout")
  // (out of the window, as the host tells it, no frame drawn: not within then; the frame after the same)
  on_pointer(7, -1.0, -1.0, 0)
  assert_true(told.last() == Some(false), msg="out of the window: not within, as it is told: \{told}")
  t.draw()
  assert_true(told.last() == Some(false), msg="out of the window: the frame after the same")
  // (back in, then a finger down, no frame drawn: no pointer, not within then; the frame after the same)
  t.move(20.0, 20.0)
  t.draw()
  assert_true(told.last() == Some(true), msg="back in: within")
  t.touch_raw(0, 1, 200.0, 200.0, t.time())
  assert_true(told.last() == Some(false), msg="a finger down: no pointer, not within, as it is told: \{told}")
  t.touch_raw(2, 1, 200.0, 200.0, t.time())
  t.draw()
  assert_true(told.last() == Some(false), msg="a finger: the frame after the same")
}

///|
/// A window 400 by 300 (a mouse's), its top row 44 high that moves the window (`node`: a node of the tree's,
/// View::moves_window, a button of its own at its start; else an old view's, Ctx::window_drag, the same button), under
/// it a button with the keyboard's focus (Tab): the primary button pressed on the row's blank, then the secondary
/// there, then the primary on its button. How many times the window was moved after each, whether the focus stayed
/// after each, how many times the row's button was pressed at the end.
fn window_row(node : Bool) -> (Array[Int], Array[Bool], Int) raise {
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    if node {
      root.box(fn(top) {
        top.height(Is(Some(44.0))).row(Is(true)).moves_window(Is(true)) |> ignore
        top.box(fn(k) { k.width(Is(Some(40.0))).on_press(fn() { pressed.val += 1 }) |> ignore }) |> ignore
      })
      |> ignore
    }
    old(root, fn(c) {
      if !node {
        let top = c.id("top")
        let key = c.id("key")
        c.window_drag(top)
        if c.clicked(key) {
          pressed.val += 1
        }
        c.box(id=top, w=Fill(1.0), h=Px(44.0), fn() { c.box(id=key, w=Px(40.0), h=Px(44.0), fn() {  }) |> ignore })
        |> ignore
      }
      // (what holds the keyboard's focus: a button of its own, not a field, which a press elsewhere keeps it in)
      let field = c.id("field")
      let n = c.box(w=Px(80.0), h=Px(40.0), id=field, fn() {  })
      c.focusable(field, node=n)
      c.semantics(n, Button, id=field, label="field")
    }).grow(Is(1.0))
    |> ignore
  })
  t.draw()
  t.tab()
  let field = t.ctx().focused_id()
  assert_true(field != 0 && field == t.get(Button, label="field").id, msg="node \{node}: the button focused")
  let drags : Array[Int] = []
  let kept : Array[Bool] = []
  for press in [(200.0, 20.0, 0), (200.0, 20.0, 2), (20.0, 20.0, 0)] {
    let (x, y, button) = press
    on_pointer(0, x, y, button)
    on_pointer(2, x, y, button)
    t.draw()
    drags.push(t.window_drags())
    kept.push(t.ctx().focused_id() == field)
  }
  (drags, kept, pressed.val)
}

///|
test "a row of the tree's that moves the window, as the old view's top row does: the primary button on its blank moves the window, the secondary moves nothing; the keyboard's focus kept by both; its button pressed, not moved by" {
  let old_row = window_row(false)
  let node_row = window_row(true)
  assert_eq(old_row.0, [1, 1, 1], msg="the old view's: moved by the primary button on its blank alone")
  assert_eq(node_row.0, old_row.0, msg="the tree's: moved as the old view's is")
  assert_eq(node_row.1, old_row.1, msg="the focus as the old view's leaves it")
  assert_eq(node_row.1[0:2].to_array(), [true, true], msg="the focus kept by a press on the blank, either button")
  assert_eq(node_row.2, old_row.2, msg="its button pressed as the old view's is")
}

///|
test "a node's words in a line shorter than their font, measured again as lines come to be set as a browser sets them and back (set_web_lines), the same node, no frame between: as tall as such words are laid out then, as an old view's are" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  t.check_looks(false)
  set_web_lines(false)
  // (a font taller than its line: 20 in lines of 14)
  let look : @view.WordsLook = { size: 20.0, weight: 400, line: 14.0, wrap: false }
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    node.val = Some(root.box(fn(n) { n.words(Is("整理发布清单"), ink=0x333333FFL, look~) |> ignore }))
  })
  t.draw()
  let n = node.val.unwrap()
  // (as an old view's words are laid out now, the lines as they are set now)
  let laid = fn() { layout_text("整理发布清单", 20.0, 400, 1.0e9, false, line=14.0).h }
  let android = laid()
  assert_eq(n.laid_size().1, android, msg="Android's lines: as tall as such words are")
  set_web_lines(true)
  let web = laid()
  let now = n.laid_size().1
  set_web_lines(false)
  let back = n.laid_size().1
  assert_true(web != android, msg="the two ways differ here: \{android} and \{web}")
  assert_eq(now, web, msg="a browser's lines: measured again at once")
  assert_eq(back, android, msg="Android's again: measured again at once")
}

///|
test "a node kept no narrower than what it holds (View::keeps_held), sharing its row alike with one beside it: as wide as its words need where they need more than its share, the one beside giving way, at once as its words or their face change (no frame between, the same nodes); its share again as they need less" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  t.check_looks(false)
  t.ui_face_wider(0.1)
  let words = @signals.signal("界面草图", same=fn(a, b) { a == b })
  let parts : Ref[(@view.View?, @view.View?, @view.View?)] = Ref((None, None, None))
  let look : @view.WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: false }
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(300.0))) |> ignore
      let a = row.box(fn(a) { a.basis(Is(Some(0.0))).grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore })
      let mut held : @view.View? = None
      let b = row.box(fn(b) {
        b.basis(Is(Some(0.0))).grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).keeps_held(Is(true)) |> ignore
        held = Some(b.box(fn(w) { w.words(By(fn() { words.get() }), ink=0x333333FFL, look~) |> ignore }))
      })
      parts.val = (Some(a), Some(b), held)
    })
    |> ignore
  })
  t.draw()
  let (a, b, held) = (parts.val.0.unwrap(), parts.val.1.unwrap(), parts.val.2.unwrap())
  // (as laid out now, no frame drawn: the one beside, it, its words)
  let now = fn() { (a.laid_size().0, b.laid_size().0, held.laid_size().0) }
  let alike = fn(at : String) raise {
    let (wa, wb, ww) = now()
    assert_true((wb - dmax(150.0, ww)).abs() < 0.01 && (wa + wb - 300.0).abs() < 0.01, msg="\{at}: \{(wa, wb, ww)}")
  }
  alike("short words: each its share")
  assert_eq(b.laid_size().0, 150.0, msg="short words: its share")
  words.set("界面草图界面草图界面草图界面草图")
  alike("longer words: as wide as they need")
  let longer = b.laid_size().0
  assert_true(longer > 150.0, msg="longer words: wider than its share: \{longer}")
  assert_true(face_add(@hostapi.face_ui, "/fonts/ui.ttf"), msg="given")
  alike("their face wider")
  assert_true(b.laid_size().0 > longer + 1.0, msg="their face wider: wider still: \{now()}")
  face_clear(@hostapi.face_ui)
  alike("their face gone")
  assert_eq(b.laid_size().0, longer, msg="their face gone: as before")
  words.set("界面草图")
  alike("short again")
  assert_eq(b.laid_size().0, 150.0, msg="short again: its share")
}

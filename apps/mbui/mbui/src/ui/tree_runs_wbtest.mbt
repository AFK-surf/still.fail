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
) -> (Tester, () -> (Double, Double), () -> (Double, Double)) {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  t.check_looks(false)
  t.tabular_wider(0.5)
  let node : Ref[@view.View?] = Ref(None)
  let look : @view.WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: true }
  set_view_app(fn(root) {
    set_tree_theme(fn() { { ..Theme::light(), tabular: tabular.get() } })
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

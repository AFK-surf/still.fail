// A node of the window's tree's words, each line in the middle of its width (View::words_centered): drawn as an old
// view's centred words are (Ctx::text's `center`), a line said and a line wrapped alike; the same words not centred
// drawn from the start; centred and not as a signal says, drawn again as it changes, and as the node is made wider.

///|
/// Words of two lines said, the second long enough to wrap in 200.
let centred_words : String = "Reading your workspaces\nstill.fail's core waits on the station that holds them, a while now"

///|
/// The glyphs drawn in the last frame, their places, from the left and top of the first (where the words start).
fn glyphs_from_first(t : Tester) -> Array[(Double, Double)] {
  let gs = t.drawn_glyphs()
  if gs.is_empty() {
    return []
  }
  // (the box's left: the frame's origin in each of these windows)
  gs.map(fn(g) { (g.0, g.1) })
}

///|
/// The words centred in a box 200 wide at the window's top left, as an old view draws them: the glyphs' places.
fn old_centred() -> Array[(Double, Double)] {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(200.0), fn() { c.text(centred_words, size=13.0, line=18.0, center=true) |> ignore })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  glyphs_from_first(t)
}

///|
/// The words in a node of the tree 200 wide (`width` as it says) at the window's top left, centred as `center` says.
fn tree_words(center : @signals.Signal[Bool], width : @signals.Signal[Double]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .width(By(fn() { Some(width.get()) }))
      .words(Is(centred_words), look={ size: 13.0, weight: 400, line: 18.0, wrap: true })
      .words_centered(By(fn() { center.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a node's words centred, a line said and one wrapped, drawn where an old view draws its centred words; not centred, from the start; told otherwise, drawn again so" {
  let old = old_centred()
  let center = @signals.signal(true, same=fn(a, b) { a == b })
  let width = @signals.signal(200.0, same=fn(a, b) { a == b })
  let t = tree_words(center, width)
  let centred = glyphs_from_first(t)
  center.set(false)
  t.draw()
  let plain = glyphs_from_first(t)
  center.set(true)
  t.draw()
  let again = glyphs_from_first(t)
  // (four lines: one said, one wrapped in three)
  let lines = centred.map(fn(g) { g.1 }).fold(init=[], fn(ys : Array[Double], y) { if ys.contains(y) { ys } else { ys + [y] } })
  assert_eq(
    (centred == old, plain != centred, plain.map(fn(g) { g.0 }).fold(init=1.0e9, fn(m, x) { dmin(m, x) }) < 2.0, again == centred, lines.length()),
    (true, true, true, true, 4),
    msg="old \{old.length()} glyphs, the tree's \{centred.length()}; lines \{lines}",
  )
}

///|
test "a node's centred words, the node made wider: each line in the middle of its new width" {
  let center = @signals.signal(true, same=fn(a, b) { a == b })
  let width = @signals.signal(200.0, same=fn(a, b) { a == b })
  let t = tree_words(center, width)
  let narrow = glyphs_from_first(t)
  width.set(300.0)
  t.draw()
  let wide = glyphs_from_first(t)
  // (the first line's first glyph 50 further in: half of what the 100 more leaves of it)
  assert_true(
    narrow.length() > 0 && wide.length() > 0 && (wide[0].0 - narrow[0].0 - 50.0).abs() < 1.0,
    msg="\{narrow.length()} \{wide.length()}",
  )
}

// Words of a TextStyle on a node of the window's tree (style_words, style_ink) set as an old view's words of the same
// style are (Ctx::text): each glyph where it is there, in its ink, at the system's size of words 1 and 2, wrapped in the
// same width over lines as high, in one piece and in pieces (View::words_runs) alike: a size and a line said, none said
// (the theme's share of the size as drawn), a leading of the font's own, letters spaced by a share of their size and by
// so many points.

///|
let styled_words : String = "Words set alike in either, wrapped over lines"

///|
/// An old view's words of `style` in a box 151 wide at the system's size of words `scale`: the glyphs drawn, and the
/// sizes of words the census counts of them (Tester::census).
fn old_styled(style : TextStyle, scale : Double) -> (Array[(Double, Double, Int64)], Array[String]) {
  let t = Tester::new(
    fn(c) { c.box(w=Px(151.0), fn() { c.text(styled_words, style~) |> ignore }) |> ignore },
    w=400.0,
    h=600.0,
  )
  t.set_font_scale(scale)
  t.draw()
  (t.drawn_glyphs(), t.census().text)
}

///|
/// The same in a node of the tree's (`runs`: in two pieces, their weight and ink the words' own).
fn tree_styled(style : TextStyle, scale : Double, runs? : Bool = false) -> (Array[(Double, Double, Int64)], Array[String]) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=600.0)
  t.set_font_scale(scale)
  set_view_app(fn(root) {
    root.box(fn(at) {
      at.lines_up(Is(Some(Start))) |> ignore
      at.box(fn(b) {
        b.width(Is(Some(151.0))) |> ignore
        if runs {
          b.words_runs(Is([@view.words_run("Words set "), @view.words_run("alike in either, wrapped over lines")]), look=style_words(style))
          .ink(By(fn() { style_ink(style) }))
          |> ignore
        } else {
          b.words(Is(styled_words)).words_look(By(fn() { style_words(style) })).ink(By(fn() { style_ink(style) })) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t.drawn_glyphs(), t.census().text)
}

///|
fn styled_alike(style : TextStyle, scale : Double, runs? : Bool = false) -> Unit raise Error {
  let (old, old_counted) = old_styled(style, scale)
  let (new, new_counted) = tree_styled(style, scale, runs~)
  // (counted by the census as the same size of words, line and spacing)
  assert_eq(new_counted, old_counted, msg="counted at \{scale}")
  let lines = old.map(fn(g) { g.1 }).fold(init=[], fn(a, y) { if a.contains(y) { a } else { a + [y] } })
  assert_true(lines.length() > 1, msg="wrapped over one line only: \{Repr(lines)}")
  assert_true(
    old.length() == new.length() &&
    old.iter().zip(new.iter()).all(fn(p) { (p.0.0 - p.1.0).abs() <= 1.0e-6 && (p.0.1 - p.1.1).abs() <= 1.0e-6 && p.0.2 == p.1.2 }),
    msg="old \{Repr(old[:4])}\nnode \{Repr(new[:4])}",
  )
}

///|
let styles_compared : Array[TextStyle] = [
  text_style(size=Title, color=Muted),
  text_style(color=Link),
  text_style(size=Meta, leading=Font),
  text_style(size=Display, weight=Bold, tracking=Tight),
  text_style(size=Body, tracking=Exact(3.0)),
  text_style(size=Ui, leading=L7, tracking=Exact(-0.6)),
]

///|
test "a style's words on a node set as an old view's, at the system's size of words 1" {
  for s in styles_compared {
    styled_alike(s, 1.0)
  }
}

///|
test "a style's words on a node set as an old view's, at the system's size of words 2" {
  for s in styles_compared {
    styled_alike(s, 2.0)
  }
}

///|
test "a style's words in pieces on a node set as an old view's in one piece, at the system's size of words 1 and 2" {
  for s in styles_compared {
    styled_alike(s, 1.0, runs=true)
    styled_alike(s, 2.0, runs=true)
  }
}

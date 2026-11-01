// A node's words, and its words in pieces (View::words, View::words_runs), in a box a hair narrower than three of them:
// wrapped where an old view's are (Ctx::text, Ctx::rich), each glyph where its glyph is, as tall: two to a line, not
// three (what is measured and what is drawn wrapped in the same width).

///|
let edge_words : String = "一二三四五六"

///|
/// How wide the box is: three of edge_words' glyphs at 16 less a quarter of a point.
fn edge_width() -> Double {
  layout_text("一二三", 16.0, 400, 1.0e9, false, line=20.0).w - 0.25
}

///|
/// Edge words in a box edge_width wide at the window's top left: an old view's or a node's, its words whole or in a
/// piece (`runs`). The glyphs drawn (where) and how many lines they come to.
fn edge_drawn(node : Bool, runs : Bool) -> (Array[(Double, Double)], Int, Double, Double) {
  // (measured once the Tester's host is there to measure them: its text)
  let width = Ref(0.0)
  let t = Tester::new(
    fn(c) {
      if !node {
        c.box(w=Px(width.val), align=AStart, fn() {
          if runs {
            c.rich([span(edge_words)], size=16.0, line=20.0, wrap=true, color=0x000000FFL) |> ignore
          } else {
            // (as wide as its box, as the node's words are: none of it laid out as narrow as a glyph)
            c.text(edge_words, size=16.0, line=20.0, wrap=true, color=0x000000FFL, w=Pct(100.0)) |> ignore
          }
        })
        |> ignore
      }
    },
    w=400.0,
    h=300.0,
  )
  // (three glyphs' own width as this Tester's host measures them, and the box a quarter of a point less)
  let natural = layout_text("一二三", 16.0, 400, 1.0e9, false, line=20.0).w
  width.val = edge_width()
  let w = width.val
  if node {
    set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(b) {
        b.width(Is(Some(w))) |> ignore
        let look : @view.WordsLook = { size: 16.0, weight: 400, line: 20.0, wrap: true }
        if runs {
          b.words_runs(Is([@view.words_run(edge_words)]), look~) |> ignore
        } else {
          b.words(Is(edge_words), look~) |> ignore
        }
      })
      |> ignore
    })
  }
  t.draw()
  let glyphs = t.drawn_glyphs().map(fn(g) { (g.0, g.1) })
  let lines = glyphs.fold(init=[], fn(ys : Array[Double], g) { if ys.contains(g.1) { ys } else { ys + [g.1] } }).length()
  (glyphs, lines, w, natural)
}

///|
test "a node's words in a box a hair narrower than three of them: wrapped two to a line where an old view's are, each glyph where its glyph is" {
  let (old, new) = (edge_drawn(false, false), edge_drawn(true, false))
  // (the same box both sides, three glyphs' width less a quarter of a point, more than two)
  let premise = old.2 == new.2 && old.3 == new.3 && old.2 == old.3 - 0.25 && old.3 > 0.0
  assert_eq((premise, old.1, old.0 == new.0, new.1), (true, 3, true, 3), msg="old \{old}\nnode \{new}")
}

///|
test "a node's words in pieces in a box a hair narrower than three of them: wrapped two to a line where an old view's paragraph is, each glyph where its glyph is" {
  let (old, new) = (edge_drawn(false, true), edge_drawn(true, true))
  // (the same box both sides, three glyphs' width less a quarter of a point, more than two)
  let premise = old.2 == new.2 && old.3 == new.3 && old.2 == old.3 - 0.25 && old.3 > 0.0
  assert_eq((premise, old.1, old.0 == new.0, new.1), (true, 3, true, 3), msg="old \{old}\nnode \{new}")
}

// Words in a node of the window's tree drawn bigger or smaller (View::scale): each glyph set on the pixels where it
// would be were nothing grown or shrunk, then drawn as big as it is about the node's point, as an old view's words are
// painted where they are laid out and then its look's scale (Ctx::look); nested in another drawn smaller and moved,
// alike; not grown or shrunk, as ever.

///|
let scaled_words : String = "Some words, set on the pixels"

///|
/// The words in a box 301 wide at (`x`, 10), drawn `inner` as big about its middle, in one drawn `outer` as big about
/// its top left and moved 7 down (an old view's boxes, their looks): the glyphs drawn.
fn old_scaled(x : Double, inner : Double, outer : Double) -> Array[(Double, Double, Int64)] {
  let t = Tester::new(
    fn(c) {
      let o = c.box(left=x, top=10.0, fn() {
        let b = c.box(w=Px(301.0), fn() { c.text(scaled_words, size=13.0, line=18.0) |> ignore })
        c.look(b, look(scale=inner))
      })
      c.look(o, look(scale=outer, ox=0.0, oy=0.0, dy=7.0))
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  t.drawn_glyphs()
}

///|
/// The same in nodes of the tree.
fn tree_scaled(x : Double, inner : Double, outer : Double) -> Array[(Double, Double, Int64)] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(at) {
      at.padding(Is((x, 10.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      at.box(fn(o) {
        o.scale(Is(outer), about=At(0.0, 0.0)).offset(Is((0.0, 7.0))) |> ignore
        o.box(fn(b) {
          b
          .width(Is(Some(301.0)))
          .scale(Is(inner))
          .words(Is(scaled_words), look={ size: 13.0, weight: 400, line: 18.0, wrap: true })
          .ink(By(fn() { tree_theme().color(Fg) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_glyphs()
}

///|
fn glyphs_alike(a : Array[(Double, Double, Int64)], b : Array[(Double, Double, Int64)]) -> Bool {
  a.length() == b.length() &&
  a.iter().zip(b.iter()).all(fn(p) { (p.0.0 - p.1.0).abs() <= 1.0e-9 && (p.0.1 - p.1.1).abs() <= 1.0e-9 && p.0.2 == p.1.2 })
}

///|
test "words in a node drawn half as big, its middle a quarter pixel off the pixels: each glyph where an old view's words drawn half as big are" {
  let old = old_scaled(0.0, 0.5, 1.0)
  let new = tree_scaled(0.0, 0.5, 1.0)
  assert_true(old.length() > 0 && glyphs_alike(old, new), msg="old \{old[:3]}\nnode \{new[:3]}")
}

///|
test "words in a node drawn 0.7 as big in one drawn 0.6 as big and moved: each glyph where an old view's are so" {
  let old = old_scaled(3.3, 0.7, 0.6)
  let new = tree_scaled(3.3, 0.7, 0.6)
  assert_true(old.length() > 0 && glyphs_alike(old, new), msg="old \{old[:3]}\nnode \{new[:3]}")
}

///|
test "words in a node not grown or shrunk: where an old view's are" {
  let old = old_scaled(3.3, 1.0, 1.0)
  let new = tree_scaled(3.3, 1.0, 1.0)
  assert_true(old.length() > 0 && glyphs_alike(old, new), msg="old \{old[:3]}\nnode \{new[:3]}")
}

///|
/// Words in a box 301.3 wide at (3.3, 10.7) drawn half as big about its middle, in one drawn twice as big about its top
/// left: as big as laid out, drawn off by what the two points leave. An old view's boxes or the tree's nodes; the glyphs.
fn back_to_size(node : Bool) -> Array[(Double, Double, Int64)] {
  let t = Tester::new(
    fn(c) {
      if !node {
        let o = c.box(left=3.3, top=10.7, fn() {
          let b = c.box(w=Px(301.3), fn() { c.text(scaled_words, size=13.0, line=18.0) |> ignore })
          c.look(b, look(scale=0.5))
        })
        c.look(o, look(scale=2.0, ox=0.0, oy=0.0))
      }
    },
    w=800.0,
    h=300.0,
  )
  if node {
    set_view_app(fn(root) {
      root.box(fn(at) {
        at.padding(Is((3.3, 10.7, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
        at.box(fn(o) {
          o.scale(Is(2.0), about=At(0.0, 0.0)) |> ignore
          o.box(fn(b) {
            b
            .width(Is(Some(301.3)))
            .scale(Is(0.5))
            .words(Is(scaled_words), look={ size: 13.0, weight: 400, line: 18.0, wrap: true })
            .ink(By(fn() { tree_theme().color(Fg) }))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.drawn_glyphs()
}

///|
test "words in a node drawn half as big in one drawn twice as big, its point and place a fraction of a pixel: each glyph where an old view's are so" {
  let old = back_to_size(false)
  let new = back_to_size(true)
  assert_true(old.length() > 0 && glyphs_alike(old, new), msg="old \{old[:3]}\nnode \{new[:3]}")
}

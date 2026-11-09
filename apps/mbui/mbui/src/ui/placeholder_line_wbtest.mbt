// A field's placeholder stands where the same words typed into it stand: laid out on the line its words are laid out
// on (FieldBox's line_h: the line asked for with the system's size of words applied, else the theme's share of its size),
// not on the line as it was asked for; in an old view's editor and in a field of the window's tree, a line asked for
// or none, trimmed or not, at the system's size of words 1, 1.3 and 2.

///|
/// Where the glyphs of a field 15 big (on lines `line` apart, 0 none said; `trim`) are drawn, its words `text` ("": its
/// placeholder 按空格输入 shown), in an old view's editor or a field of the tree's (`tree`), the system's size of words
/// `fs`: each glyph's (x, y), in drawing order.
fn placed_glyphs(tree : Bool, line : Double, trim : Bool, text : String, fs : Double) -> Array[(Double, Double)] {
  let f = Field::new(text~)
  let t = Tester::new(
    fn(c) {
      if !tree {
        c.editor("f", field=f, placeholder="按空格输入", font_size=15.0, line~, trim~, max_lines=1, plain=true) |> ignore
      }
    },
    w=300.0,
    h=200.0,
    platform=0,
  )
  if tree {
    set_view_app(fn(root) {
      field(root, f, placeholder="按空格输入", font_size=15.0, line~, trim~, max_lines=1) |> ignore
    })
  }
  t.set_font_scale(fs)
  t.draw()
  t.draw()
  t.drawn_glyphs().map(fn(g) { (g.0, g.1) })
}

///|
test "a field's placeholder where the same words typed into it are, in an old view's editor and a field of the tree's, its line said or not, trimmed or not, at the system's size of words 1, 1.3 and 2" {
  for tree in [false, true] {
    for way in [(24.75, false), (24.75, true), (0.0, false)] {
      let (line, trim) = way
      for fs in [1.0, 1.3, 2.0] {
        let hint = placed_glyphs(tree, line, trim, "", fs)
        let typed = placed_glyphs(tree, line, trim, "按空格输入", fs)
        let said = "tree \{tree}, line \{line}, trim \{trim}, at \{fs}"
        assert_true(hint.length() == 5, msg="\{said}: its placeholder's glyphs \{hint}")
        assert_eq(hint, typed, msg="\{said}: its placeholder \{hint}, its words \{typed}")
      }
    }
  }
}

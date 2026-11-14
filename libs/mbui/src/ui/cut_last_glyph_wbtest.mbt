// What the last glyph drawn of one line cut short is, by its key in the atlas (glyph_keys): an old view's words in a box
// too narrow for them, and a node of the tree's held to that width (Tree::capped_applied's): the same glyph, the
// ellipsis's, not the arrow the words end in.

///|
/// The key of the glyph drawn last (rightmost) in the frame just drawn; and of each glyph drawn.
fn last_glyph_key() -> (Int, Array[Int]) {
  let c = g()
  let keys = glyph_keys()
  let mut last = -1
  let mut x = -1.0e9
  let all = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 {
      let key = keys.get("\{c.inst[b + 12]} \{c.inst[b + 13]}").unwrap_or(-1)
      all.push(key)
      if c.inst[b] > x {
        x = c.inst[b]
        last = key
      }
    }
  }
  (last, all)
}

///|
/// `words` on one line at 25, in a box `w` wide: an old view's (`tree` false) or a node of the tree's in a column that
/// wide. The key of its last glyph drawn, and of all.
fn cut_drawn(tree : Bool, words : String, w : Double) -> (Int, Array[Int]) {
  if tree {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
    set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(col) {
        col.width(Is(Some(w))).lines_up(Is(Some(Start))) |> ignore
        col.box(fn(t) {
          t.words(Is(words), look={ size: 25.0, weight: 400, line: 30.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
  } else {
    let t = Tester::new(
      fn(c) { c.box(w=Px(w), fn() { c.text(words, size=25.0, line=30.0, wrap=false) |> ignore }) |> ignore },
      w=400.0,
      h=200.0,
    )
    t.draw()
  }
  last_glyph_key()
}

///|
test "one line cut short in a box too narrow for it: its last glyph the ellipsis's, an old view's and a node's held to its column alike" {
  let (ellipsis, _) = cut_drawn(false, "…", 400.0)
  let (arrow, _) = cut_drawn(false, "→", 400.0)
  let (old_last, old_all) = cut_drawn(false, "查看价目表 →", 140.0)
  let (new_last, new_all) = cut_drawn(true, "查看价目表 →", 140.0)
  assert_true(ellipsis >= 0 && arrow >= 0 && ellipsis != arrow, msg="the ellipsis \{ellipsis}, the arrow \{arrow}")
  assert_eq((old_last, new_last), (ellipsis, ellipsis), msg="old \{Repr(old_all)}, new \{Repr(new_all)}")
  assert_eq(new_all, old_all)
}

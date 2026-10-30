///|
/// Words, and over them (a layer) other words in the same place, with a ground of `ground` between (0: none).
fn words_laid_over(ground : Int64) -> (Ctx) -> Unit {
  fn(c) {
    c.box(fn() {
      c.text("under these", wrap=false) |> ignore
      c.layer(fn() {
        c.box(bg=ground, fn() { c.text("over those", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "words over words: one node's words drawn over another's, both seen, are found, each pair once" {
  let t = Tester::new(words_laid_over(0L), w=300.0, h=200.0, words_over_held=false)
  t.draw()
  let faults = g().words_over_faults()
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].0, "under these")
  assert_eq(faults[0].1, "over those")
}

///|
test "words over words: what a whole ground hides is not seen, nor a ground faded in part over it" {
  let t = Tester::new(words_laid_over(0xFFFFFFFFL), w=300.0, h=200.0, words_over_held=false)
  t.draw()
  assert_eq(g().words_over_faults().length(), 0)
  // (a ground half there hides nothing: both are seen)
  let t = Tester::new(words_laid_over(0xFFFFFF80L), w=300.0, h=200.0, words_over_held=false)
  t.draw()
  assert_eq(g().words_over_faults().length(), 1)
}

///|
/// The window's tree with words of its own at its top left, and over them (`over`: "tree", a node of the tree's; "old",
/// an old view's) other words in the same place.
fn tree_words_laid_over(over : String) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, words_over_held=false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(w) { w.width(Is(Some(200.0))).words(Is("under these")) |> ignore }) |> ignore
    })
    |> ignore
    if over == "tree" {
      root.box(fn(b) {
        b.over(Is(true)) |> ignore
        b.box(fn(w) { w.width(Is(Some(200.0))).words(Is("over those")) |> ignore }) |> ignore
      })
      |> ignore
    } else {
      old(root, fn(c) { c.text("over those", wrap=false) |> ignore }).over(Is(true)) |> ignore
    }
  })
  t.draw()
  t
}

///|
test "words over words in the window's tree: a node's over another's found, as made and as kept drawn again; an old view's over a node's too" {
  let t = tree_words_laid_over("tree")
  let made = g().words_over_faults().map(fn(f) { (f.0, f.1) })
  // (drawn again, the nodes' instances as kept)
  t.frame_at(t.time() + 16.0)
  let kept = g().words_over_faults().map(fn(f) { (f.0, f.1) })
  let _ = tree_words_laid_over("old")
  let mixed = g().words_over_faults().map(fn(f) { (f.0, f.1) })
  assert_eq((made, kept, mixed), ([("under these", "over those")], [("under these", "over those")], [("under these", "over those")]))
}

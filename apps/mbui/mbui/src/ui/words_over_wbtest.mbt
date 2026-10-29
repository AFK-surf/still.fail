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

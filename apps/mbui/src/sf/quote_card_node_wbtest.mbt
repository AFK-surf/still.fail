// A quote's card in a message as nodes (quote_card_node) where what holds it has its words picked with the mouse (a
// message's list: @ui.words_picked): dragged over from the words before it to the words after it, what is picked.

///|
/// A page 360 wide whose words are picked with the mouse (@ui.words_picked): words in pieces, a quote's card leading
/// to its message, words in pieces; dragged over from the first's start to the last's end. What is picked then (what
/// ⌘C copies), and the quote's words as its card says them.
fn quote_dragged_over() -> (String, String) {
  let tr = @ui.Tester::new(
    fn(c) { begin(c) |> ignore },
    tree=fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      let tips = TipLayer::new(fn() { Some(root) })
      root.box(fn(page) {
        page.width(Is(Some(360.0))).padding(Is((16.0, 40.0, 16.0, 0.0))) |> ignore
        @ui.words_picked(page)
        page.box(fn(n) { n.words_runs(Is([@ui.span("正文在前")])) |> ignore }) |> ignore
        quote_card_node(
          page,
          tips,
          fn() { "Ana" },
          fn() { "先把签名核对一遍" },
          fn() { "person" },
          fn() { "" },
          fn() { true },
          fn() {  },
        )
        |> ignore
        page.box(fn(n) { n.words_runs(Is([@ui.span("正文在后")])) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  tr.run_for(@ui.move_most_ms)
  let at = fn(s : String) {
    match tr.words().iter().find_first(fn(w) { w.0 == s }) {
      Some(w) => w
      None => @halt.saying("\{s} not drawn: \{Repr(tr.words())}")
    }
  }
  let first = at("正文在前")
  let last = at("正文在后")
  tr.drag(first.1 + 1.0, first.2 + first.4 / 2.0, last.1 + last.3 - 1.0, last.2 + last.4 / 2.0)
  tr.run_for(@ui.move_most_ms)
  (tr.ctx().selected_text(), t("web-main.quote.author", args=[("author", "Ana")]) + "先把签名核对一遍")
}

///|
test "dragged over from the words before a quote's card to the words after it, what is picked holds those two alone, as the old card's words were none of what is picked" {
  let (picked, quoted) = quote_dragged_over()
  // (the card lends a picker that picks none: mbui's ui keeps the words of what is so lent out of what is picked)
  assert_eq(picked, "正文在前\n正文在后", msg=quoted)
}

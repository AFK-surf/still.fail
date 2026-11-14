// A tip saying words its control shows itself (tip_node's `repeats`): shown only where they show cut short there as it
// would show (View::words_cut_now), as the old tip's (Ctx::shows_cut); a file's card's name so, as the old card's.

///|
/// A window 400 by 200, a mouse's: a button `w` wide holding `words` on one line cut short where it has not the room,
/// its tip saying them (`repeats` as said), the pointer rested on it a tip's while from when the hover ground came: the
/// tips shown then, and how many times the window's tree was laid out over that while.
fn repeats_tip(words : String, w : Double, repeats : Bool) -> (Array[String], Int) raise {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(b) {
      b.row(Is(true)).width(Is(Some(w))).height(Is(Some(32.0))) |> ignore
      presses_node(b, fn() {  })
      b.says(Is(Some(@view.said(Button, label="按钮")))) |> ignore
      b.box(fn(n) { n.cuts(Is(true)).words(Is(words)).words_look(Is({ ..@view.words_plain, wrap: false })) |> ignore })
      |> ignore
      tip_node(tips, b, fn() { words }, repeats~) |> ignore
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  let k = t.get(Button, label="按钮")
  t.move_to(k.rect.0 + 10.0, k.rect.1 + 10.0)
  let laid = fn() { @ui.view_tree().unwrap().work().computes }
  let before = laid()
  t.run_for(tip_delay_ms + tip_settled_ms)
  let shown = t.semantics().filter(fn(s) { s.role == Tooltip }).map(fn(s) { s.label })
  (shown, laid() - before)
}

///|
test "a tip saying what its control shows: shown where that shows cut short as it would show, none where it shows whole; read so, nothing laid out more than its showing lays out" {
  let words = "一段说得很长很长的按钮上的字"
  let (whole, whole_laid) = repeats_tip(words, 390.0, true)
  let (cut, cut_laid) = repeats_tip(words, 80.0, true)
  let (cut_said, cut_said_laid) = repeats_tip(words, 80.0, false)
  assert_eq((whole, cut, cut_said), ([], [words], [words]))
  // (read at the moment it would show: the same layouts as the tip that reads nothing; whole, its own showing's none)
  assert_eq(cut_laid, cut_said_laid, msg="cut: \{cut_laid} reading, \{cut_said_laid} not")
  assert_eq(whole_laid, 0, msg="whole: none shown, nothing laid out to read it")
}

///|
test "a file's card's name cut short is said so as the old card's is (Ctx::shows_cut), in a column too narrow for it; with the room, not" {
  let name = "季度报告.pdf"
  for w in [400.0, 100.0] {
    // (the old card's)
    let old = Ref(false)
    let o = @ui.Tester::new(fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(w=Px(w), fn() { file_card(c, "file", name, 12345.0, open=true) }) |> ignore
        old.val = c.shows_cut(c.id("file"))
      })
    })
    o.draw()
    o.frame()
    let old_cut = old.val
    // (the card's nodes)
    let card : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(_c) {  }, w=480.0, h=200.0, platform=0)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.lines_up(Is(Some(Start))) |> ignore
      let tips = TipLayer::new(fn() { None })
      root.box(fn(col) {
        col.width(Is(Some(w))) |> ignore
        card.val = Some(
          file_card_node(col, tips, fn() { name }, fn() { file_size(12345.0) }, fn() { false }, fn() { false }, fn() {
            false
          }, fn() { "" }, fn() { "" }, fn(_) {  }),
        )
      })
      |> ignore
    })
    t.draw()
    assert_eq((w, old_cut, card.val.unwrap().words_cut_now()), (w, w < 200.0, w < 200.0))
  }
}

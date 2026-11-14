// Rows together in a panel's body (group's in_panel way: a card of the panel's) as nodes (group_node) beside the old
// one (group), each given the same rows (two that turn something on or off), the last of what a dialog holds
// (panel_card_last, panel_card_last_node): on every screen a panel is drawn on, everything drawn and every word where
// the old one's is and as big.

///|
/// What a panel holding rows together on a card draws at rest, every rectangle and every word (each where and how big,
/// to a thousandth of a point), in order: the old panel's (`old`), else the node panel's, on a window `at`, opened by
/// its 打开 (`pressed`: a sheet a press opened, a small panel beside it) or by nothing (a sheet, a dialog in the middle
/// of the window). Closed after, gone.
fn group_panel_drawn(at : (Int, Double, Double), pressed : Bool, old : Bool) -> Array[String] raise {
  let open = fn(from : Anchor) {
    let from = if pressed { from } else { Unanchored }
    if old {
      panel("一组", from~, fn(c, _) {
        c.box(style=panel_words_in(), fn() { c.text("它说的话", style=secondary) |> ignore }) |> ignore
        c.box(style=group_panel_block.then(panel_card_last()), fn() {
          group(c, fn() {
            switch_row(c, "group-panel/a", "第一个开关", false) |> ignore
            switch_row(c, "group-panel/b", "第二个开关", true) |> ignore
          })
        })
        |> ignore
      })
    } else {
      panel_nodes("一组", from~, fn(v, _) {
        v.box(fn(b) {
          style_node(b, fn() { panel_words_in_node(b) })
          words_node(b, fn() { "它说的话" }, fn() { secondary }) |> ignore
        })
        |> ignore
        v.box(fn(b) {
          style_node(b, fn() { group_panel_block.then(panel_card_last_node(b)) })
          group_node(b, fn(g) {
            switch_row_node(g, fn() { "第一个开关" }, fn() { false }, fn(_) {  })
            switch_row_node(g, fn() { "第二个开关" }, fn() { true }, fn(_) {  })
          })
        })
        |> ignore
      })
    }
  }
  presenters_reset()
  let (platform, w, h) = at
  let t = @ui.Tester::new(
    fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
    tree=presented_tree(presenting_view(open)),
    w~,
    h~,
    platform~,
  )
  t.check_looks(false)
  t.draw()
  t.tap_text("打开")
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let drawn = t.drawn_rects().map(fn(r) { "rect \{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)} \{r.4}" })
  let words = t.words().map(fn(w) { "words \{w.0}@\{k(w.1)},\{k(w.2)} \{k(w.3)}x\{k(w.4)} a\{w.5}" })
  // (the old view's words and the tree's are told in their own orders)
  words.sort()
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  drawn + words
}

///|
/// The block the rows stand in: 14 over it (composer_ref's ref_block).
// kept across runs: a value (no field of it changes)
let group_panel_block : @ui.Style = @ui.css("w=Full gap=S2 pt=S3_5")

///|
test "rows together in a panel's body as nodes where the old ones stand: a sheet opened by nothing and by a press, with a finger and with a mouse, a small panel beside what opened it, a dialog in the middle of the window" {
  for screen in [
    ("sheet opened by nothing", phone, false),
    ("sheet opened by a press", phone, true),
    ("sheet opened by a press, with a mouse", (0, 390.0, 844.0), true),
    ("small panel", (0, 800.0, 600.0), true),
    ("dialog", (0, 800.0, 600.0), false),
  ] {
    let (about, at, pressed) = screen
    let old = group_panel_drawn(at, pressed, true)
    let new = group_panel_drawn(at, pressed, false)
    let differs : Array[String] = []
    for i in 0..<(if old.length() > new.length() { old.length() } else { new.length() }) {
      let o = old.get(i).unwrap_or("-")
      let n = new.get(i).unwrap_or("-")
      if o != n {
        differs.push("\{about}: line \{i}:\n  old \{o}\n  new \{n}")
      }
    }
    if !differs.is_empty() {
      fail(differs.join("\n"))
    }
  }
}

// Rows that go somewhere on a group's card in a panel's body: the old ones (link_row in group) beside the node ones
// (link_row_node in group_node), given the same rows, one with a mark before its words (a 20 icon, made by the page)
// and one with none, on every screen a panel is drawn on: everything drawn and every word where the old one's is and
// as high (a row's title's box as wide as its words where the old one's is as wide as its line: its glyphs where they
// were).

///|
/// What a panel holding two rows that go somewhere on a group's card draws at rest, every rectangle (where and how big,
/// to a thousandth of a point) and every word (where and how high), in order: the old panel's (`old`), else the node
/// panel's, on a window `at`, opened by its 打开 (`pressed`) or by nothing. Closed after, gone.
fn link_card_drawn(at : (Int, Double, Double), pressed : Bool, old : Bool) -> Array[String] raise {
  let open = fn(from : Anchor) {
    let from = if pressed { from } else { Unanchored }
    if old {
      panel("一组", from~, fn(c, _) {
        c.box(style=panel_words_in(), fn() { c.text("它说的话", style=secondary) |> ignore }) |> ignore
        c.box(style=group_panel_block.then(panel_card_last()), fn() {
          group(c, fn() {
            link_row(c, "link-card/a", "上传图片", chevron=false, lead=fn() {
              icon(c, "image-upload", size=20.0, color=theme().p.text) |> ignore
            })
            |> ignore
            link_row(c, "link-card/b", "不带图标", chevron=false) |> ignore
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
            link_row_node(g, fn() { "上传图片" }, fn() {  }, chevron=false, lead=LeadMade(fn(l) {
              icon_node(l, "image-upload", 20.0, By(fn() { theme().p.text })) |> ignore
            }))
            link_row_node(g, fn() { "不带图标" }, fn() {  }, chevron=false)
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
  let words = t.words().map(fn(w) { "words \{w.0}@\{k(w.1)},\{k(w.2)} h\{k(w.4)} a\{w.5}" })
  // (the old view's words and the tree's are told in their own orders)
  words.sort()
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  drawn + words
}

///|
test "rows that go somewhere, with a mark before their words and with none, on a group's card in a panel's body as nodes where the old ones stand: a sheet opened by nothing and by a press, a small panel beside what opened it, a dialog in the middle of the window" {
  for screen in [
    ("sheet opened by nothing", phone, false),
    ("sheet opened by a press", phone, true),
    ("sheet opened by a press, with a mouse", (0, 390.0, 844.0), true),
    ("small panel", (0, 800.0, 600.0), true),
    ("dialog", (0, 800.0, 600.0), false),
  ] {
    let (about, at, pressed) = screen
    let old = link_card_drawn(at, pressed, true)
    let new = link_card_drawn(at, pressed, false)
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

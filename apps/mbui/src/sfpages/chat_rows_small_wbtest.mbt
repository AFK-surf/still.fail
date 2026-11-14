// What a chat's list holds besides its messages, as the old view draws it out of a list (chat_rows.mbt): the newer page
// coming, the older one failed, a chat with nothing yet, the line over what is new. Their node-made rows are held to
// the same in message_small_rows_node_wbtest.mbt.

///|
/// The old rows `build` makes in a column `w` wide, at rest.
fn chat_rows_small_old(w : Double, build : (@ui.Ctx) -> Unit) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { c.box(style=@ui.style(w=Fixed(w)), fn() { build(c) }) |> ignore })
    },
    w=w + 40.0,
    h=400.0,
    platform=0,
  )
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "the old small rows: the line over what is new between its rules, a page coming its spinner in the middle, why the older failed wrapping in its column, an empty chat's words in the middle" {
  for w in [760.0, 390.0] {
    let at = "width \{w}"
    // the line over what is new: its words in the middle, a rule each side of them on their middle
    let t = chat_rows_small_old(w, fn(c) { unread_line(c) })
    let said = @sf.t("web-main.chat.unreadLine")
    let (x, y, ww, h) = t.rect_of(said).unwrap()
    let rules = t.drawn_rects().filter(fn(r) { r.3 <= 1.0 && r.2 > 0.0 })
    assert_eq(rules.length(), 2, msg=at)
    assert_true(rules[0].0 + rules[0].2 <= x && rules[1].0 >= x + ww, msg=at)
    assert_true((rules[0].1 - (y + h / 2.0)).abs() <= 1.0, msg=at)
    assert_true(((x + ww / 2.0) - w / 2.0).abs() <= 1.0, msg=at)
    // a page coming, older or newer: a spinner in the middle of the column
    for older in [true, false] {
      let t = chat_rows_small_old(w, fn(c) { pages_coming(c, older) })
      let lines = t.drawn_lines()
      assert_true(lines.length() > 0, msg=at)
      let xs = lines.map(fn(l) { l.0 })
      let lo = xs.fold(init=@double.infinity, fn(a, b) { if b < a { b } else { a } })
      let hi = xs.fold(init=-@double.infinity, fn(a, b) { if b > a { b } else { a } })
      assert_true(((lo + hi) / 2.0 - w / 2.0).abs() <= 1.0, msg="\{at}, older \{older}")
    }
    // the older page failed: why, as the core says it, wrapped in the column
    let why = "网络断开了，稍后会再试一次，这一句话写得长一些好让它在窄的时候换行，再长一些，再长一些，再长一些"
    let t = chat_rows_small_old(w, fn(c) { older_failed(c, why) })
    let said = @sf.t("web-main.chat.olderFailed", args=[("why", why)])
    let (x, _, ww, _) = t.rect_of(said).unwrap()
    assert_true(x >= 0.0 && x + ww <= w, msg=at)
    // nothing yet: its words in the middle
    let t = chat_rows_small_old(w, fn(c) { chat_empty(c) })
    let (x, _, ww, _) = t.rect_of(@sf.t("web-main.chat.empty")).unwrap()
    assert_true(((x + ww / 2.0) - w / 2.0).abs() <= 1.0, msg=at)
  }
}

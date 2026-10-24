// The changelog's changes (more_pages.mbt change_item, Changelog.css.ts mKind): a line's kind on a label inline before
// its words, which wrap under it, the label as high as its own line however many lines the words take.

///|
test "changelog: a change's kind on a label before its words, which wrap under it; the label one line high" {
  let words = "对话列表偶尔把同一行显示两次，滑到底再滑回来也不会消失"
  let e : Json = {
    "versionName": "0.1.1288",
    "note": "",
    "lines": [{ "kind": "fix", "label": "修复", "text": Json::string(words) }],
  }
  let t = @ui.Tester::new(fn(c) {
    c.box(align=AStart, fn() { c.box(w=Px(260.0), fn() { change_item(c, Some(e)) }) |> ignore }) |> ignore
  })
  t.draw()
  let labels = t.drawn_rects().filter(fn(r) { r.4 == @sf.theme().p.chip })
  assert_eq(labels.length(), 1)
  let (lx, _, _, lh, _) = labels[0]
  assert_true((lh - 19.0).abs() < 0.001)
  // the words wrap, their second line starting where the label does
  let rs = t.run_rects(words)
  assert_true(rs.length() >= 2)
  assert_true((rs[1].0 - lx).abs() < 0.001)
}

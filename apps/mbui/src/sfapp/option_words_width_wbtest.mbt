// An option's long label and detail on a narrow chat stay within the row's content, leaving its end inset.

///|
test "a chat option's long label and detail wrap before the end of the card's content" {
  new_run()
  let src = @sffixture.said_longest_source(fixture("chat"))
  open_fixture_over("chat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let label = @sffixture.said_longest("一起换")
  let detail = @sffixture.said_longest("把首页和聊天页的截图都更新")
  // Bring the option into view without relying on a particular list offset or other messages' heights.
  for _ in 0..<8 {
    if t.semantics().iter().any(fn(s) { s.role == Button && s.label == label }) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
    t.run_for(@ui.move_most_ms)
  }
  let rows = t.semantics().filter(fn(s) { s.role == Button && s.label == label })
  assert_false(rows.is_empty(), msg="the option is visible")
  let (x, _, w, _) = rows[0].rect
  // The row ends 12 points before its card's inside edge, as on the previous chat page.
  let end = x + w - 12.0
  for words in [label, detail] {
    let drawn = t.words().filter(fn(d) { d.0 == words && d.5 > 0.99 })
    assert_false(drawn.is_empty(), msg="the option's words are drawn: \{words}")
    for d in drawn {
      assert_true(d.1 + d.3 <= end + 0.5,
        msg="the option's words leave the row's end inset: \{d.1 + d.3} > \{end}: \{words}")
    }
  }
}

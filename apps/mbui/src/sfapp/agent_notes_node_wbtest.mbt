// The agent's notes are a live part of its card, with no space of their own when empty.

///|
test "agent notes follow the card and release their room when removed" {
  new_run()
  let card : @signals.Signal[Json?] = @signals.signal(None)
  let mounted = @signals.signal(true)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=240.0, h=300.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.show(fn() { mounted.get() }, fn(body) {
      agent_notes_node(body, fn() { card.get() }, top=10.0)
    })
    root.box(fn(end) {
      end.words(Is("after notes")) |> ignore
    }) |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let end_y = fn() { tree.drawn().filter(fn(d) { d.words == "after notes" })[0].y }
  let empty_y = end_y()
  card.set(Some({ "attention": [
    { "level": "amber", "text": "One" },
    { "level": "red", "text": "One" },
  ] }))
  t.draw()
  let first = tree.drawn().filter(fn(d) { d.words == "One" })
  assert_eq(first.length(), 2, msg="duplicate notes are both shown")
  assert_eq(first[0].ink, @sf.theme().p.warn_ink)
  assert_eq(first[1].ink, @sf.theme().p.red)
  assert_eq(tree.said_order().filter(fn(n) {
    !n.hidden && n.said is Some(s) && s.role == Text && s.label == "One"
  }).length(), 2, msg="both notes are read out as text")
  assert_eq((first[0].x, first[0].y), (@sf.text_in, 10.0))
  assert_eq((first[1].y - first[0].y, end_y() - empty_y), (20.0, 56.0))
  let standard_y = end_y()
  t.set_font_scale(1.5)
  t.draw()
  assert_true(end_y() > standard_y, msg="larger system text has room without clipping")
  t.set_font_scale(1.0)
  t.draw()
  let first_id = first[0].id
  card.set(Some({ "attention": [
    { "level": "red", "text": "Changed" },
    { "level": "amber", "text": "One" },
    { "level": "other", "text": "Third" },
  ] }))
  t.draw()
  let changed = tree.drawn().filter(fn(d) { d.words == "Changed" })
  assert_eq(changed.length(), 1)
  assert_eq((changed[0].id, changed[0].ink), (first_id, @sf.theme().p.red))
  assert_eq(tree.drawn().filter(fn(d) { d.words == "One" })[0].ink, @sf.theme().p.warn_ink)
  assert_eq(tree.drawn().filter(fn(d) { d.words == "Third" })[0].ink, @sf.theme().p.red)
  card.set(Some({ "attention": [
    { "level": "other", "text": "Third" },
    { "level": "amber", "text": "One" },
  ] }))
  t.draw()
  assert_true(tree.drawn().filter(fn(d) { d.words == "Changed" }).is_empty())
  assert_true(tree.drawn().filter(fn(d) { d.words == "Third" })[0].y <
    tree.drawn().filter(fn(d) { d.words == "One" })[0].y)
  @sf.set_dark(Some(true))
  t.draw()
  assert_eq(tree.drawn().filter(fn(d) { d.words == "One" })[0].ink, @sf.theme().p.warn_ink)
  assert_eq(tree.drawn().filter(fn(d) { d.words == "Third" })[0].ink, @sf.theme().p.red)
  card.set(Some({ "attention": [] }))
  t.draw()
  assert_eq(end_y(), empty_y)
  assert_true(tree.drawn().filter(fn(d) { d.words == "Changed" || d.words == "Third" }).is_empty())
  card.set(Some({ "attention": [{ "level": "amber", "text": "Back" }] }))
  t.draw()
  mounted.set(false)
  t.draw()
  assert_eq(end_y(), empty_y)
  card.set(Some({ "attention": [{ "level": "red", "text": "While away" }] }))
  t.draw()
  assert_true(tree.drawn().filter(fn(d) { d.words == "While away" }).is_empty())
  mounted.set(true)
  t.draw()
  assert_eq(tree.drawn().filter(fn(d) { d.words == "While away" }).length(), 1)
}

///|
test "agent notes wrap within their available width" {
  new_run()
  let words = "This note is long enough to wrap across several lines in a narrow card."
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=140.0, h=300.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    agent_notes_node(root, fn() { Some({ "attention": [{ "level": "amber", "text": Json::string(words) }] }) }, top=10.0)
  })
  t.draw()
  let notes = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == words })
  assert_eq(notes.length(), 1)
  assert_true(notes[0].h > 18.0, msg="the complete note wraps instead of being cut")
  assert_true(notes[0].x + notes[0].w <= 140.0 - @sf.text_in)
}

// A reminder in an agent's history: its label stays readable beside a long first line, and its whole text opens below.

///|
test "history reminder keeps its label on one line beside a long note and opens it whole" {
  let first = "This is a new conversation: your earlier one in this session is no longer available."
  let note = first + "\nThe agent can continue here."
  let item : Json = {
    "body": { "kind": "received", "content": { "note": Json::string(note), "tasks": [], "messages": [] } },
  }
  for lang in ["zh", "en"] {
    for case in [(240.0, 0), (360.0, 0), (360.0, 2), (580.0, 0)] {
      let (w, platform) = case
      steps_reset()
      @sf.set_words(@sfbase.fill)
      @sf.set_language(Some(lang))
      let src = @sffixture.fixture("history")
      let t = @ui.Tester::new(
        fn(c) {
          @sf.begin(c) |> ignore
          c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
        },
        tree=fn(root) {
          @ui.set_tree_theme(@sf.ui_theme_now)
          let tips = @sf.TipLayer::new(fn() { Some(root) })
          root.box(fn(v) { item_node(v, src, "ws1/st1", "s-c1", "reminder", Some(item), false, tips) }) |> ignore
        },
        w~,
        h=240.0,
        platform~,
      )
      t.draw()
      // (its words read once its run has begun)
      let title = @sf.t("web-main.history.reminder", args=[("name", "still.fail")])
      let at = "\{lang}, width \{w}, platform \{platform}"
      let (title_x, _, title_w, title_h) = t.rect_of(title).unwrap()
      let (line_x, _, _, line_h) = t.rect_of(first).unwrap()
      assert_true(title_h <= 20.0 && line_h <= 20.0, msg="\{at}: title \{title_h}, preview \{line_h}")
      assert_true(line_x >= title_x + title_w, msg=at)
      assert_true(t.rect_of(note) is None, msg=at)
      t.tap_text(title)
      // (its room opened on its way: reveal_node)
      t.run_for(@ui.move_most_ms)
      assert_true(t.rect_of(note) is Some(_), msg="\{at}: whole reminder did not open")
      assert_true(t.rect_of(title).unwrap().3 <= 20.0, msg=at)
      t.tap_text(title)
      t.run_for(@ui.move_most_ms)
      assert_true(t.rect_of(note) is None, msg="\{at}: reminder did not close")
    }
  }
  steps_reset()
  @sf.set_language(None)
}

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
      let title = @sf.t("web-main.history.reminder", args=[("name", "still.fail")])
      let t = @ui.Tester::new(fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          item_view(c, src, "ws1/st1", "s-c1", "reminder", Some(item), false)
        })
      }, w~, h=240.0, platform~)
      t.draw()
      let at = "\{lang}, width \{w}, platform \{platform}"
      let title_runs = t.text_runs().filter(fn(r) { r.text == title })
      assert_eq(title_runs.length(), 1, msg="\{at}: \{t.text_runs()}")
      let (_, _, _, title_h) = t.rect_of(title).unwrap()
      let (line_x, _, _, line_h) = t.rect_of(first).unwrap()
      assert_true(title_h <= 20.0 && line_h <= 20.0, msg="\{at}: title \{title_h}, preview \{line_h}")
      assert_true(line_x >= title_runs[0].x1, msg=at)
      assert_true(t.rect_of(note) is None, msg=at)
      t.tap_text(title)
      assert_true(t.rect_of(note) is Some(_), msg="\{at}: whole reminder did not open")
      assert_eq(t.text_runs().filter(fn(r) { r.text == title }).length(), 1, msg=at)
      t.tap_text(title)
      assert_true(t.rect_of(note) is None, msg="\{at}: reminder did not close")
    }
  }
  steps_reset()
  @sf.set_language(None)
}

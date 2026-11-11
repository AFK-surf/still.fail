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
      let src = @sffixture.fixture("history")
      // (the language as the device says it: what a test sets before its Tester is put back as the Tester starts)
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
        env=[("MBUI_LOCALE", lang)],
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
}

///|
/// A call's code (its part `kind: code`, as the core reads a call: history.tool) of `code` in a column 16 in from a
/// window 760 wide, drawn by the history's tool_part_node, or by an old view's code_block (`old`): its Tester, drawn.
fn steps_code_tester(old : Bool, code : String) -> @ui.Tester {
  let part : Json = { "kind": "code", "text": Json::string(code), "lang": "sh" }
  let t = if old {
    @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() { c.column(w=Fill(1.0), pad=16.0, fn() { @sf.code_block(c, code, "sh") }) |> ignore })
      },
      w=760.0,
      h=400.0,
    )
  } else {
    @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=760.0, h=400.0, tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.lines_up(Is(None)) |> ignore
      root.box(fn(b) {
        b.padding(Is((16.0, 16.0, 16.0, 16.0))) |> ignore
        tool_part_node(b, Some(part))
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  t
}

///|
/// Where each line of `code` is drawn in `t`, to a hundredth (Tester::run_rects: a rectangle a line).
fn steps_code_lines(t : @ui.Tester, code : String) -> Array[String] {
  code
  .split("\n")
  .to_array()
  .filter(fn(l) { l != "" })
  .map(fn(l) {
    let rects = t.run_rects(l.to_string()).map(fn(r) { "\{(r.0 * 100.0).round() / 100.0},\{(r.1 * 100.0).round() / 100.0} \{(r.2 * 100.0).round() / 100.0}x\{(r.3 * 100.0).round() / 100.0}" })
    "\{l}: \{rects}"
  })
}

///|
test "a call's code of two lines in the history: on two lines, each where an old view's code block draws it, as tall" {
  let code = "moon test --target wasm-gc src/sfpages/history_steps_node_wbtest.mbt\nmoon check"
  steps_reset()
  let old_t = steps_code_tester(true, code)
  let old = steps_code_lines(old_t, code)
  let old_box = old_t.rect_of("moon check")
  let made_t = steps_code_tester(false, code)
  let made = steps_code_lines(made_t, code)
  let made_box = made_t.rect_of("moon check")
  // (each line on a line of its own, the second under the first)
  let ys = fn(t : @ui.Tester) { ["moon test", "moon check"].map(fn(l) { t.run_rects(l).map(fn(r) { r.1 }) }) }
  assert_eq(made, old, msg="each line where an old view's code block draws it:\nmade \{made}\nold  \{old}")
  assert_eq(made_box, old_box, msg="its words as wide and as tall as an old view's: made \{made_box}, old \{old_box}")
  let lines = ys(made_t)
  assert_true(lines[0].length() == 1 && lines[1].length() == 1 && lines[1][0] > lines[0][0], msg="\{lines}")
  steps_reset()
}

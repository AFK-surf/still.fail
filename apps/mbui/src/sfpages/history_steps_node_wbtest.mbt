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
    let rects = t.run_rects(l.to_owned()).map(fn(r) { "\{(r.0 * 100.0).round() / 100.0},\{(r.1 * 100.0).round() / 100.0} \{(r.2 * 100.0).round() / 100.0}x\{(r.3 * 100.0).round() / 100.0}" })
    "\{l}: \{@ui.list_text(rects)}"
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
  assert_eq(made, old, msg="each line where an old view's code block draws it:\nmade \{Repr(made)}\nold  \{Repr(old)}")
  assert_eq(made_box, old_box, msg="its words as wide and as tall as an old view's: made \{Repr(made_box)}, old \{Repr(old_box)}")
  let lines = ys(made_t)
  assert_true(lines[0].length() == 1 && lines[1].length() == 1 && lines[1][0] > lines[0][0], msg="\{Repr(lines)}")
  steps_reset()
}

///|
test "history task keeps its title visible when opened and toggles from its preview line" {
  let title = "后台任务「跑全量测试」已完成"
  let preview = "142 passed (18.4s)"
  let result = "moon test --target wasm-gc\n142 passed (18.4s)"
  let item : Json = {
    "body": {
      "kind": "received",
      "content": {
        "note": "",
        "tasks": [
          {
            "text": Json::string(title),
            "line": Json::string(preview),
            "result": Json::string(result),
            "md": [["p", [Json::string(result)]]],
            "failed": false,
            "agent": false,
          },
        ],
        "messages": [],
      },
    },
  }
  steps_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("history")
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=480.0, h=240.0, tree=fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.box(fn(v) { item_node(v, src, "ws1/st1", "s-c1", "h1", Some(item), false, tips) }) |> ignore
  })
  t.draw()
  assert_true(t.rect_of(title) is Some(_))
  assert_true(t.rect_of(preview) is Some(_))
  assert_true(t.rect_of(result) is None)
  t.tap_text(preview)
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of(title) is Some(_), msg="task title stays visible when expanded")
  assert_true(t.rect_of(result) is Some(_), msg="task result opens when preview is tapped")
  assert_true(t.rect_of(@sf.t("web-main.fold")) is Some(_))
  t.tap_text(@sf.t("web-main.fold"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of(title) is Some(_))
  assert_true(t.rect_of(preview) is Some(_))
  assert_true(t.rect_of(result) is None)
  steps_reset()
}

///|
test "history text expands on its first line and short single-line text omits fold button" {
  let short_words = "先看历史面板这几处样式。"
  let short_item : Json = {
    "body": {
      "kind": "text",
      "content": {
        "text": Json::string(short_words),
        "line": Json::string(short_words),
        "md": [["p", [Json::string(short_words)]]],
        "subagent": false,
      },
    },
  }
  let long_words = "列表只建看得见的行，其余的按估计的高度占位；量过一次的行记住它的高度，滚回来时不再跳。"
  let long_item : Json = {
    "body": {
      "kind": "text",
      "content": {
        "text": Json::string(long_words),
        "line": Json::string(long_words),
        "md": [["p", [Json::string(long_words)]]],
        "subagent": false,
      },
    },
  }
  steps_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("history")
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=420.0, h=300.0, tree=fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.lines_up(Is(None)) |> ignore
    root.box(fn(v) { item_node(v, src, "ws1/st1", "s-c1", "short", Some(short_item), false, tips) }) |> ignore
    root.box(fn(v) { item_node(v, src, "ws1/st1", "s-c1", "long", Some(long_item), false, tips) }) |> ignore
  })
  t.draw()
  let (_, short_y, short_w, _) = t.rect_of(short_words).unwrap()
  let (_, long_y, long_w, long_h) = t.rect_of(long_words).unwrap()
  assert_true(short_w < 300.0 && long_w > short_w, msg="short single-line text fits on one line without truncation")
  assert_true(short_y < long_y && long_h <= 20.0)
  assert_true(t.rect_of(@sf.t("web-main.fold")) is None)
  let collapsed_y = long_y
  t.tap_text(long_words)
  t.run_for(@ui.move_most_ms)
  let (_, expanded_y, _, expanded_h) = t.rect_of(long_words).unwrap()
  let fold_y = t.rect_of(@sf.t("web-main.fold")).unwrap().1
  assert_true(expanded_h > long_h, msg="expanded text wraps across multiple lines: \{expanded_h} vs \{long_h}")
  assert_true((expanded_y - collapsed_y).abs() <= 4.0, msg="expanded text starts on the first line: \{expanded_y} vs \{collapsed_y}")
  assert_true((fold_y - expanded_y).abs() <= 6.0, msg="fold button aligns with the first line: \{fold_y} vs \{expanded_y}")
  steps_reset()
}

///|
test "history group thought hides duplicate first-line preview in summary when expanded" {
  let first = "行高先按估计值占位（摘要）"
  let full = "行高先按估计值占位，滚过一次就记住实测高度。"
  let item : Json = {
    "body": {
      "kind": "group",
      "content": {
        "summary": "读取 1 个文件",
        "failures": 0,
        "pending": 0,
        "rows": [
          {
            "kind": "step",
            "content": { "name": "Read", "said": "", "hint": "src/list.ts", "meta": "40 行", "call": "{}", "failed": false },
          },
          {
            "kind": "thought",
            "content": {
              "first": Json::string(first),
              "text": Json::string(full),
              "md": [["p", [Json::string(full)]]],
              "brief": false,
            },
          },
        ],
      },
    },
  }
  steps_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("history")
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=480.0, h=300.0, tree=fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.lines_up(Is(None)) |> ignore
    root.box(fn(v) { item_node(v, src, "ws1/st1", "s-c1", "g1", Some(item), false, tips) }) |> ignore
  })
  t.draw()
  t.tap_text("读取 1 个文件")
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of(first) is Some(_))
  assert_true(t.rect_of(full) is None)
  t.tap_text(first)
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of(first) is None, msg="summary preview is hidden once full thought is open")
  assert_true(t.rect_of(full) is Some(_))
  steps_reset()
}

///|
test "history tool step renders dispatch card, full-width stacked long fields, and result section header" {
  let msg = "All 4 review findings are valid (`src/sf/markdown.mbt`). Please fix all 4."
  let sum = "Tell verifier all 4 findings are valid, ask to fix all"
  let call_json = "{\"to\":\"a036720bc24844903\",\"message\":\"All 4 review findings are valid (`src/sf/markdown.mbt`). Please fix all 4.\",\"summary\":\"Tell verifier all 4 findings are valid, ask to fix all\"}"
  let res_json = "{\"type\":\"message_sent\",\"recipient\":\"a036720bc24844903\",\"recipient_kind\":\"agent\"}"
  let item : Json = {
    "body": {
      "kind": "group",
      "content": {
        "summary": sum,
        "failures": 0,
        "pending": 0,
        "rows": [
          {
            "kind": "step",
            "content": {
              "name": "SendMessage",
              "said": "",
              "hint": "",
              "meta": "",
              "call": Json::string(call_json),
              "result": Json::string(res_json),
              "failed": false,
            },
          },
        ],
      },
    },
  }
  steps_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("history")
  let ask : Map[String, Json] = {
    "name": Json::string("SendMessage"),
    "call": Json::string(call_json),
    "failed": Json::boolean(false),
    "said": Json::boolean(false),
    "result": Json::string(res_json),
  }
  let tk = "g-send/group/0\u{1}" + Json::object(ask).stringify()
  steps_own.tools[tk] = {
    "call": [
      {
        "kind": "markdown",
        "target": "verifier",
        "targetId": "a036720bc24844903",
        "summary": Json::string(sum),
        "text": Json::string(msg),
        "md": [["p", ["All 4 review findings are valid (", ["code", "src/sf/markdown.mbt"], "). Please fix all 4."]]],
      },
    ],
    "result": [
      {
        "kind": "fields",
        "rows": [
          { "key": "type", "value": "message_sent", "form": "short" },
          { "key": "recipient", "value": "verifier", "form": "short" },
          { "key": "recipient_kind", "value": "agent", "form": "short" },
        ],
      },
    ],
  }
  for case in [(390.0, 2), (900.0, 0)] {
    let (w, platform) = case
    @sf.presenters_reset()
    steps_own.opened["g-send/group"] = true
    steps_own.opened["g-send/group/0"] = true
    let t = @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
      },
      w~,
      h=600.0,
      platform~,
      tree=fn(root) {
        @ui.set_tree_theme(@sf.ui_theme_now)
        let tips = @sf.TipLayer::new(fn() { Some(root) })
        root.lines_up(Is(None)) |> ignore
        steps_box_node(root, steps_row_first, fn(v) {
          item_node(v, src, "ws1/st1", "s-c1", "g-send", Some(item), false, tips)
        })
        @sf.presented_nodes(root)
      },
    )
    t.draw()
    assert_true(t.rect_of("代理") is Some(_), msg="SendMessage shows 代理 badge")
    assert_true(t.rect_of("→ verifier") is Some(_), msg="dispatch card shows resolved target badge")
    assert_true(t.rect_of("返回") is Some(_), msg="result section header is shown")
    assert_true(t.rect_of("message_sent") is Some(_), msg="result fields are shown")
    assert_true(t.rect_of("recipient_kind") is Some(_), msg="recipient_kind is shown")
    assert_eq(t.corner_faults(), [])
    assert_eq(t.lit_all_faults(), [])
    t.tap_text("全屏查看")
    t.run_for(@ui.move_most_ms * 2.0)
    assert_true(t.rect_of("复制") is Some(_), msg="reader drawer shows 复制 button")
    assert_eq(t.corner_faults(), [])
    assert_eq(t.lit_all_faults(), [])
  }
  @sf.presenters_reset()
  steps_reset()
}

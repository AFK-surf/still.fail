// Markdown as nodes on one line (markdown_node's one_line: a notice closed) drawn as an old view's markdown draws it
// so, cut with an ellipsis where the column is narrower; and each paragraph's links told as they are (`on_link_shown`).

///|
/// A reading whose first block is a long paragraph with a link in it, then another.
fn ml_tree() -> Json {
  let s = fn(x : String) { Json::string(x) }
  let p = fn(xs : Array[Json]) { Json::array([s("p"), Json::array(xs)]) }
  Json::array([
    p([
      s("定时任务没有按时跑起来：station 上的时钟比云端慢了四十秒，见 "),
      Json::array([s("a"), Json::array([s("排查记录")]), Json::object({ "href": s("https://example.com/notes") })]),
      s("，已经改成按云端的时间对齐，下一次会准时。"),
    ]),
    p([s("第二段不该出现在一行里。")]),
  ])
}

///|
/// ml_tree's words on one line in a column 16 in from a window `w` wide, drawn by an old view's markdown or as nodes
/// (`node`).
fn ml_tester(node : Bool, w : Double) -> @ui.Tester {
  let tree = ml_tree()
  let t = if node {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=300.0, platform=0)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          c.column(w=Fill(1.0), pad=16.0, fn() { markdown(c, mn_text, tree=Some(tree), one_line=true) |> ignore })
          |> ignore
        })
      },
      w~,
      h=300.0,
      platform=0,
    )
  }
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.lines_up(Is(None)) |> ignore
      root.box(fn(b) {
        b.padding(Is((16.0, 16.0, 16.0, 16.0))) |> ignore
        markdown_node(b, fn() { mn_text }, tree=fn() { Some(tree) }, one_line=true) |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  t
}

///|
test "Markdown as nodes on one line: its first block's words alone, cut with an ellipsis, as an old view's markdown draws them so, wide and narrow" {
  for w in [390.0, 1200.0] {
    let old_t = ml_tester(false, w)
    let old = mn_words(old_t)
    let old_drawn = mn_instances(old_t)
    let made_t = ml_tester(true, w)
    let made = mn_words(made_t)
    let made_drawn = mn_instances(made_t)
    assert_true(old.iter().all(fn(x) { !x.has_prefix("第二段") }), msg="\{w}: \{Repr(old)}")
    assert_eq(made, old, msg="\{w}:\nmade \{Repr(made)}\nold  \{Repr(old)}")
    let only_made = made_drawn.filter(fn(x) { !old_drawn.contains(x) })
    let only_old = old_drawn.filter(fn(x) { !made_drawn.contains(x) })
    assert_true(
      made_drawn == old_drawn,
      msg="\{w}: \{made_drawn.length()} drawn, \{old_drawn.length()} old;\nonly made \{Repr(only_made.iter().take(8).collect())}\nonly old  \{Repr(only_old.iter().take(8).collect())}",
    )
    let faults = made_t.audit()
    assert_true(faults.is_empty(), msg="\{w}: " + faults.join(" | "))
  }
}

///|
test "Markdown as nodes: each paragraph's links told as they are, its words' node with them; none for a paragraph with none" {
  let told : Array[(String, String)] = []
  let nodes : Array[@view.View] = []
  let tree = @signals.signal(ml_tree())
  // (its words with it: a reading is kept by its words, blocks_of)
  let text = @signals.signal(mn_text)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=800.0, h=600.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_node(root, fn() { text.get() }, tree=fn() { Some(tree.get()) }, on_link_shown=fn(v, links) {
      nodes.push(v)
      for l in links {
        told.push((l.0, l.1))
      }
    })
    |> ignore
  })
  t.draw()
  assert_eq(told, [("https://example.com/notes", "排查记录")])
  assert_true(nodes.length() == 2 && nodes.iter().all(fn(v) { v.alive() }), msg="\{nodes.length()}")
  // (its link's way changed: told again, as it is now)
  let s = fn(x : String) { Json::string(x) }
  @signals.start_batch()
  text.set("见 [新的](https://example.com/new)")
  tree.set(
    Json::array([
      Json::array([
        s("p"),
        Json::array([s("见 "), Json::array([s("a"), Json::array([s("新的")]), Json::object({ "href": s("https://example.com/new") })])]),
      ]),
    ]),
  )
  @signals.end_batch()
  t.draw()
  assert_true(told.contains(("https://example.com/new", "新的")), msg="\{Repr(told)}")
}

///|
/// A table too wide for a narrow column: eight columns of a long word each, a row under its head.
fn ml_wide_table() -> Json {
  let s = fn(w : String) { Json::string(w) }
  let el = fn(name : String, kids : Array[Json]) { Json::array([s(name), Json::array(kids)]) }
  let row = fn(words : Array[String]) { el("tr", words.map(fn(w) { el("td", [s(w)]) })) }
  Json::array([
    el("table", [
      row(["station", "session", "runtime", "maker", "started", "finished", "duration", "status"]),
      row(["Willow-MacBook", "s-c1-release", "claude-code", "anthropic", "21:04:11", "21:09:58", "5m47s", "succeeded"]),
    ]),
  ])
}

///|
/// ml_wide_table shown whole (`fit_tables`) in a column 16 in from a window `w` wide, nothing to copy: an old view's
/// markdown's or as nodes (`node`).
fn ml_fit_tester(node : Bool, w : Double) -> @ui.Tester {
  let tree = ml_wide_table()
  let text = "（ml_wide_table 的原文）"
  let t = if node {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=400.0, platform=0)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          c.column(w=Fill(1.0), pad=16.0, fn() {
            markdown(c, text, tree=Some(tree), fit_tables=true, copy=false) |> ignore
          })
          |> ignore
        })
      },
      w~,
      h=400.0,
      platform=0,
    )
  }
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.lines_up(Is(None)) |> ignore
      root.box(fn(b) {
        b.padding(Is((16.0, 16.0, 16.0, 16.0))) |> ignore
        markdown_node(b, fn() { text }, tree=fn() { Some(tree) }, fit_tables=true, copy=false) |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  t
}

///|
test "Markdown as nodes, its tables shown whole: one too wide for the column made as much smaller as fits it, as an old view's markdown does; one that fits as ever" {
  for w in [390.0, 1200.0] {
    let old_t = ml_fit_tester(false, w)
    let old = mn_words(old_t)
    let old_drawn = mn_instances(old_t)
    let made_t = ml_fit_tester(true, w)
    let made = mn_words(made_t)
    let made_drawn = mn_instances(made_t)
    assert_eq(made, old, msg="\{w}:\nmade \{Repr(made)}\nold  \{Repr(old)}")
    let only_made = made_drawn.filter(fn(x) { !old_drawn.contains(x) })
    let only_old = old_drawn.filter(fn(x) { !made_drawn.contains(x) })
    assert_true(
      made_drawn == old_drawn,
      msg="\{w}: \{made_drawn.length()} drawn, \{old_drawn.length()} old;\nonly made \{Repr(only_made.iter().take(8).collect())}\nonly old  \{Repr(only_old.iter().take(8).collect())}",
    )
  }
}

///|
test "Markdown as nodes, its tables shown whole: the window narrowed past where a table fits and widened back, the frame it turns in draws it as one made at that width, nothing on its way" {
  for turn in [(1200.0, 390.0), (390.0, 1200.0)] {
    let (from_w, to_w) = turn
    let t = ml_fit_tester(true, from_w)
    t.run_for(@ui.move_most_ms)
    t.resize(to_w, 400.0)
    let turned = mn_instances(t)
    let turned_words = mn_words(t)
    let made = ml_fit_tester(true, to_w)
    made.run_for(@ui.move_most_ms)
    assert_eq(turned_words, mn_words(made), msg="\{Repr(turn)}")
    assert_true(turned == mn_instances(made), msg="\{Repr(turn)}: drawn otherwise in the frame it turned in")
  }
}

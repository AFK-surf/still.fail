// Links to a station's screens and to a chat's web service as nodes (sfbase's screen_links_node.mbt) set beside the old
// view's (screen_links.mbt, through @sf.markdown's `screens`) on the same words (chat_fixture.mbt's screens_answer: a
// web service's card, the desktop's, a tab's with the link's own words, a tab gone, 共享调试 bare and alone, a link to
// anywhere else), the core said or not yet, a service down, none previewed; wide and narrow, at 1.3; a card tapped; a
// previewed tab's card where the old view's is.

///|
/// The fixture's source of chat-screens: the core has said each card (`said`, else none yet), its service up or
/// stopped (`up`), its tab previewed where it says so (`peek`, else none previewed).
fn sl_src(said? : Bool = true, up? : Bool = true, peek? : Bool = false) -> Source {
  let base = @sffixture.fixture("chat-screens")
  {
    ..base,
    topic_read: fn(name, params) {
      let t = (base.topic_read)(name, params)
      if !said && (name == "screenCard" || name == "job") {
        { ..t, value: None }
      } else if !peek && name == "screenCard" {
        match t.value {
          Some(Object(o)) => {
            let m = o.copy()
            m["peek"] = Json::boolean(false)
            { ..t, value: Some(Json::object(m)) }
          }
          _ => t
        }
      } else if !up && name == "job" {
        match t.value {
          Some(Object(o)) => {
            let m = o.copy()
            m["open"] = Json::boolean(false)
            m["word"] = Json::string("已停止")
            { ..t, value: Some(Json::object(m)) }
          }
          _ => t
        }
      } else {
        t
      }
    },
  }
}

///|
/// The words as the old view draws them (@sf.markdown with screen_links), `w` wide.
fn sl_old(w : Double, src : Source, words : String) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=head_frame, fn() {
          @sf.markdown(c, words, key="sl", size=body_size, screens=Some(screen_links(c, src, "sl"))) |> ignore
        })
        |> ignore
      })
    },
    w~,
    h=900.0,
  )
}

///|
/// The same words as the nodes draw them (markdown_node with screen_links_node), `w` wide.
fn sl_new(w : Double, src : Source, words : String) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        @sf.markdown_node(f, fn() { words }, size=fn() { body_size }, screens=@sfbase.screen_links_node(src)) |> ignore
      })
      |> ignore
    },
    w~,
    h=900.0,
  )
}

///|
/// What a Tester draws (head_drawn's), each place and size to a hundredth (the old view's sums leave tails the nodes'
/// do not: 245.31000080108643 against 245.3100008010864).
fn sl_drawn(t : @ui.Tester) -> String {
  let r = fn(v : Double) { (v * 100.0).round() / 100.0 }
  t.words().map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(d) { "\{r(d.0)},\{r(d.1)} \{r(d.2)}x\{r(d.3)} \{d.4}" }).join("\n")
}

///|
test "links to screens and a web service, made once as nodes, are drawn as the old view drew them: their cards, a bare one's title, said and not yet, a service down; wide and narrow" {
  for case in [("said", true, true), ("not said yet", false, true), ("service down", true, false)] {
    for w in [760.0, 390.0] {
      let at = "\{case.0} at \{w}"
      let old = sl_old(w, sl_src(said=case.1, up=case.2), @sffixture.screens_answer)
      old.run_for(@ui.move_most_ms)
      let was = sl_drawn(old)
      let t = sl_new(w, sl_src(said=case.1, up=case.2), @sffixture.screens_answer)
      t.run_for(@ui.move_most_ms)
      assert_eq(sl_drawn(t), was, msg=at)
      let faults = t.audit()
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
}

///|
test "at 1.3 a card's title and its line each as high as their words, the one over the other; the old view's ran over each other" {
  for case in [("said", true, true), ("not said yet", false, true), ("service down", true, false)] {
    let t = sl_new(390.0, sl_src(said=case.1, up=case.2), @sffixture.screens_answer)
    t.set_font_scale(1.3)
    t.run_for(@ui.move_most_ms)
    if case.1 {
      for pair in [("桌面", "Ana 正在查看"), ("打开定价页", if case.2 { "Willow :5173 · 在线" } else { "Willow :5173 · 已停止" })] {
        let (_, ty, _, th) = t.rect_of(pair.0).unwrap()
        let (_, ly, _, _) = t.rect_of(pair.1).unwrap()
        assert_true(ty + th <= ly + 0.01, msg="\{case.0}: \{pair.0} over \{pair.1}")
      }
    }
    let faults = t.audit()
    assert_true(faults.is_empty(), msg=case.0 + ": " + faults.join(" | "))
  }
}

///|
/// What a tap on `words` in `t` did: what it handed the system, and whether the page on top is another than before.
fn sl_tapped(t : @ui.Tester, words : String) -> (Array[String], Bool) {
  let before = app.nav.top()
  t.tap_text(words)
  t.frame()
  t.frame()
  (t.opened(), app.nav.top() != before)
}

///|
test "a card tapped opens where its link leads, as the old view's does: the desktop's, a tab gone, the web service" {
  for words in ["Ana 正在查看", "此屏幕已不存在", "打开定价页"] {
    let old = sl_old(760.0, sl_src(), @sffixture.screens_answer)
    old.run_for(@ui.move_most_ms)
    let was = sl_tapped(old, words)
    assert_true(was.0.length() > 0 || was.1, msg=words + ": the old one opened nothing")
    let t = sl_new(760.0, sl_src(), @sffixture.screens_answer)
    t.run_for(@ui.move_most_ms)
    assert_eq(sl_tapped(t, words), was, msg=words)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg=words + ": " + faults.join(" | "))
  }
}

///|
test "a tab its station previews: its card drawn by the nodes as the old view draws it, its preview over its words, the rest as they were" {
  let old = sl_old(760.0, sl_src(peek=true), @sffixture.screens_answer)
  old.run_for(@ui.move_most_ms)
  // (each to a hundredth, as sl_drawn's)
  let r = fn(v : Double) { (v * 100.0).round() / 100.0 }
  let at = fn(t : @ui.Tester) {
    ["林 正在查看", "发布清单预览", "Ana 正在查看"].map(fn(w) {
      t.rect_of(w).map(fn(q) { "\{r(q.0)},\{r(q.1)} \{r(q.2)}x\{r(q.3)}" }).unwrap_or("none")
    })
  }
  let was = at(old)
  assert_true(was[0] != "none", msg="the old view's card with its preview")
  let t = sl_new(760.0, sl_src(peek=true), @sffixture.screens_answer)
  t.run_for(@ui.move_most_ms)
  assert_eq(at(t), was)
  let faults = t.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

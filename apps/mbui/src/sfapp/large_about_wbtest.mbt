// 关于, 记忆 and 更新日志 made once on a large screen (sfdesk's pane_made: the pane off the tape, the page laid out wide by
// the width the frame gives it) and on the tape: its parts the tree's own, what the frame does around it, what is
// picked of its words.

///|
/// 关于 on a large screen (`platform`'s input), `w` × 900, in the window's tree's frame: its page made once (`tree`; not:
/// pane_makes off till the next such tester, what the library's pages made once elsewhere are drawn as by their old view).
fn large_about_tester(
  tree : Bool,
  platform : Int,
  w? : Double = 1280.0,
  mode? : String = "settings-about",
  wait? : Double = @ui.move_most_ms,
  scale? : Double = 1.0,
  window_inset? : Bool = false,
  lang? : @signals.Signal[String] = @signals.signal(""),
  topics? : Map[String, @signals.Signal[Json]] = {},
) -> @ui.Tester {
  let base = fixture_app(mode)
  // (the core's language as `lang` says it, where it says one)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      match topics.get(name) {
        Some(v) => return { value: Some(v.get()), error: None, version: 1 }
        None => ()
      }
      let got = base.topic(name, params).get().snapshot()
      if name != "prefs" || lang.get() == "" {
        return got
      }
      let o = match got.value {
        Some(Object(m)) => m.copy()
        _ => {}
      }
      o["lang"] = Json::string(lang.get())
      { ..got, value: Some(Json::object(o)) }
    },
  }
  // (the same frame, the window's tree's; its page the old view's where not `tree`)
  @sfdesk.pane_makes.val = tree
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform~, window_inset~)
  t.set_font_scale(scale)
  t.run_for(wait)
  t
}

///|
test "大屏 关于 made once: its title, section titles, rows and switch are the tree's own nodes; its switch turned, statistics told so" {
  let t = large_about_tester(true, 0)
  let own = tree_words_drawn()
  for w in [
    @sf.t("web-pages.settings.nav.about"),
    @sf.t("web-pages.settings.nav.version"),
    @sf.t("web-pages.about.privacy"),
    @sf.t("web-pages.settings.nav.changelog"),
    @sf.t("common.legal.terms"),
  ] {
    assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="not the tree's own: \{w} in \{Repr(own)}")
  }
  let told : Array[Bool] = []
  reporting_host.set(Some({ get: fn() { told.last().unwrap_or(true) }, set: fn(on) { told.push(on) } }))
  t.click(Switch, label=@sf.t("common.telemetry.title"))
  t.run_for(@ui.move_most_ms)
  assert_eq(told, [false])
}

///|
/// 关于 come to over 更新日志 (made once where `made`, else its old view) in the settings, the sidebar folded, then the
/// sidebar shown a while; a frame between the two (at `t0 + 20`) where `frame_between`, else none: where the move has
/// the page moved aside once it has come (its right margin, the page's move aside, the edge, the sidebar shown).
fn about_peeked(made : Bool, frame_between : Bool) -> (Double, Double, Double, Double)? {
  let t = large_about_tester(made, 0, mode="settings-changelog")
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  let t0 = t.time()
  t.advance(between_frames_ms)
  app.nav.push(Setting(@settings.Route::About))
  if frame_between {
    t.frame_at(t0 + 20.0)
  }
  t.advance(t0 + 30.0 - t.time())
  @sfdesk.wide.peeking.set(true)
  bring(t0 + 30.0)
  @sfdesk.pane_reach_at(t0 + 2000.0)
}

///|
test "大屏 关于 made once, come to and the sidebar shown a while with no frame between: the page moved aside by what it shows as it is then, as with a frame between" {
  let framed = about_peeked(true, true)
  let at_once = about_peeked(true, false)
  assert_eq(at_once, framed)
  match framed {
    Some((_, aside, _, _)) => assert_true(aside > 0.0, msg="moved aside: \{Repr(framed)}")
    None => fail("no move")
  }
}

///|
test "大屏 关于 made once over another 关于: the one that shows is the frame's to read, each by its entry; back to the first, the first again, kept" {
  let t = large_about_tester(true, 0)
  let first = @sfdesk.pane_made_seen()
  assert_true(first is Some(_))
  app.nav.push(Setting(@settings.Route::About))
  t.run_for(@ui.move_most_ms)
  let second = @sfdesk.pane_made_seen()
  assert_true(second is Some(_) && second != first, msg="another node over the first")
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.pane_made_seen() == first, msg="back to the first")
}

///|
test "大屏 关于 made once: words dragged over with the mouse picked none (its words plain: none of them to be picked)" {
  let t = large_about_tester(true, 0)
  t.drag(410.0, 140.0, 700.0, 260.0)
  t.release(700.0, 260.0)
  assert_eq(t.ctx().selected_text(), "")
}

///|
/// Where a press across the top of the window drags it (Tester::drags_window_at), in a window with its buttons in the
/// app's top row (macOS's): at every 20 across, 6, 24 and 46 down; the settings' page of `mode` on it.
fn about_drags(mode : String, platform : Int) -> Array[String] {
  let t = large_about_tester(true, platform, window_inset=true, mode~)
  let out = []
  for y in [6.0, 24.0, 46.0] {
    let mut x = 10.0
    while x < 1280.0 {
      if t.drags_window_at(x, y) {
        out.push("\{x},\{y}")
      }
      x = x + 20.0
    }
  }
  out
}

///|
test "大屏 关于 made once in a window with its buttons in the app's top row: a press across the page's top drags the window where another settings page's (外观, an old view's) does, nowhere else" {
  for platform in [0, 2] {
    let other = about_drags("settings-appearance", platform)
    assert_true(other.iter().any(fn(p) { p.has_prefix("1250,") }), msg="the page's top drags it: \{Repr(other)}")
    assert_eq(about_drags("settings-about", platform), other, msg="at \{platform}")
  }
}

///|
test "记忆 made once, its page wide on a large screen and on the tape: its rows the tree's own" {
  for case in [(0, 1.0, 1280.0), (2, 2.0, 1280.0), (2, 1.0, 839.0), (0, 1.0, 600.0)] {
    let (platform, scale, w) = case
    let _ = large_about_tester(true, platform, scale~, w~, mode="settings-memories")
    assert_true(app.nav.top() == Setting(@settings.Route::Memories), msg="on top: \{@sfbase.page_kind(app.nav.top())}")
    let own = tree_words_drawn()
    assert_true(own.iter().any(fn(o) { o.contains(@sf.t("android-misc.memory.note")) }), msg="its lead the tree's: \{Repr(own)} at \{Repr(case)}")
  }
}

///|
test "大屏 关于 made once over 更新日志, the language changed: its back says where it goes in the new one, the same page and the same back; its title too" {
  let lang = @signals.signal("")
  let t = large_about_tester(true, 0, mode="settings-changelog", lang~)
  app.nav.push(Setting(@settings.Route::About))
  t.run_for(@ui.move_most_ms)
  let back = @sf.t("web-pages.settings.nav.changelog")
  let page = @sfdesk.pane_made_seen()
  let back_node = tree_node_of(back)
  assert_true(page is Some(_) && back_node is Some(_), msg="its back the tree's: \{Repr(tree_words_drawn())}")
  lang.set("en")
  // The made-up prefs notify readers as the core would when the language changes.
  t.stepped()
  t.run_for(@ui.move_most_ms)
  let back_en = @sf.t("web-pages.settings.nav.changelog")
  let title_en = @sf.t("web-pages.settings.nav.about")
  assert_true(back_en != back, msg="in English: \{back_en}")
  let words = tree_words_drawn()
  assert_true(words.contains(back_en) && words.contains(title_en), msg="said anew: \{Repr(words)}")
  assert_true(@sfdesk.pane_made_seen() == page, msg="the same page")
  assert_true(tree_node_of(back_en) == back_node, msg="the same back")
  lang.set("")
  @sf.set_language(None)
}

///|
test "a real client's prefs change the language of the existing settings page" {
  let base = fixture_app("settings-changelog")
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name != "prefs" { return (base.topic_read)(name, params) }
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "prefs" { client.follow_topic(name, params~).waiting } else { (base.waits)(name, params) }
    },
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "prefs" { client.leave_topic(name, params~) } else { (base.leave)(name, params, @sfbase.TopicLeave::Legacy) }
    },
    release: fn(name, params) {
      if name == "prefs" { client.release_topic(name, params~) } else { (base.release)(name, params) }
    },
  }
  @sfdesk.pane_makes.val = true
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=900.0, platform=0, env=[("MBUI_LOCALE", "zh")])
  guard client.peek_topic("prefs") is Some(sub) else { fail("prefs not subscribed") }
  assert_eq(sent.length(), 1, msg="tree creation and the first frame share the prefs subscription")
  let prefs = match (base.topic_read)("prefs", {}).value {
    Some(Object(m)) => m.copy()
    _ => fail("the fixture's prefs are missing")
  }
  prefs["lang"] = "zh"
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": Json::object(prefs) })
  t.frame()
  let chinese = @sf.t("web-pages.settings.nav.changelog")
  assert_true(tree_words_drawn().contains(chinese), msg="the settings page is drawn in Chinese")
  let node = tree_node_of(chinese)
  let english_prefs = prefs.copy()
  english_prefs["lang"] = "en"
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": Json::object(english_prefs) })
  t.frame()
  let english = @sf.t("web-pages.settings.nav.changelog")
  assert_true(english != chinese && tree_words_drawn().contains(english), msg="the existing page follows the core's language")
  assert_true(node is Some(_) && tree_node_of(english) == node, msg="the page kept the same node")
  assert_eq(sent.length(), 1, msg="changing prefs does not resubscribe")
  @ui.run_let_go()
  assert_true(client.peek_topic("prefs") is None, msg="ending the run releases its prefs")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  @sf.set_language(None)
}

///|
/// Whether a word of the window's says `words` among its own.
fn says(t : @ui.Tester, words : String) -> Bool {
  t.words().any(fn(w) { w.0.contains(words) })
}

///|
test "大屏 关于 made once where the device keeps a performance record: turned on, what the host writes after shown as it tells it (分享记录, how much), as it grows and once turned off; the page left, nothing more for it" {
  let t = large_about_tester(true, 0)
  // (a device that keeps one, as it starts: 关于 opened again on it)
  t.set_perf(0)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  open_page(Setting(About))
  t.run_for(@ui.move_most_ms)
  t.wheel(800.0, 500.0, 5000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(says(t, "现有 0 B"), msg="none written yet")
  assert_true(t.find("分享记录") is None)
  // (turned on: nothing written yet as it is)
  t.click(Switch, label="性能记录")
  t.draw()
  assert_eq(t.perf_said().0, [true])
  assert_true(t.find("分享记录") is None)
  // (the host's first lines written, told after: shown on the same page)
  t.set_perf_size(666.0)
  t.draw()
  assert_true(t.find("分享记录") is Some(_), msg="its first lines")
  assert_true(says(t, "现有 666 B"))
  // (more written)
  t.set_perf_size(900.0)
  t.draw()
  assert_true(says(t, "现有 900 B"), msg="more")
  // (turned off: what was still being written, told after)
  t.click(Switch, label="性能记录")
  t.draw()
  assert_eq(t.perf_said().0, [true, false])
  t.set_perf_size(950.0)
  t.draw()
  assert_true(says(t, "现有 950 B"), msg="its last lines")
  // (the page left: what the host tells after asks nothing of a frame)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享记录") is None)
  assert_true(t.at_rest(), msg="at rest once left")
  t.set_perf_size(1000.0)
  assert_true(t.at_rest(), msg="nothing owed for it")
}

///|
test "更新日志 made once on a large screen and on the tape, wide and narrow: its days' words the tree's own" {
  for case in [(0, 1.0, 1280.0), (2, 2.0, 1280.0), (2, 1.0, 839.0), (0, 1.0, 600.0), (2, 2.0, 600.0)] {
    let (platform, scale, w) = case
    let _ = large_about_tester(true, platform, scale~, w~, mode="settings-changelog")
    assert_true(app.nav.top() == Setting(@settings.Route::Changelog))
    assert_true(tree_words_drawn().iter().any(fn(o) { o.contains("10 月 19 日") }), msg="its day the tree's: \{Repr(case)}")
  }
}

///|
test "更新日志 made once, its page narrow on the tape: a change's line with its kind dragged over with the mouse picks its words" {
  let line = "设置里可以添加 station 和 Profile"
  let t = large_about_tester(true, 0, w=600.0, mode="settings-changelog")
  guard t.rect_of("新增" + line) is Some((x, y, w, h)) else { fail("no line") }
  let mid = y + h / 2.0
  t.drag(x + 2.0, mid, x + w + 40.0, mid)
  t.release(x + w + 40.0, mid)
  let said = t.ctx().selected_text()
  assert_true(said.contains(line), msg="\{said}")
}

///|
/// The core's changelog of two parts, 甲 and 乙, each of 12 days of two changes: more than a window shows.
fn long_changelog(first? : Int = 0, days? : Int = 12, more? : Bool = false) -> Json {
  let part = fn(name : String, v0 : Int) -> Json {
    let days = Array::makei(days, fn(d0) {
      let d = d0 + first
      // (the first day, where `more`, with one more change come since, before its others)
      let extra : Array[Json] = if more && d == 0 {
        [
          Json::object({
            "version": Json::number((v0 + 99).to_double()),
            "versionName": Json::string("0.1.\{v0 + 99}"),
            "lines": [{ "kind": "new", "label": "新增", "text": Json::string("\{name} 那天又来的一处") }],
            "has": Json::boolean(true),
            "note": "",
          }),
        ]
      } else {
        []
      }
      Json::object({
        "day": Json::number((20000 - d).to_double()),
        "label": Json::string("\{name} 第 \{d + 1} 天"),
        "entries": Json::array(extra + Array::makei(2, fn(k) {
          Json::object({
            "version": Json::number((v0 + d * 2 + k).to_double()),
            "versionName": Json::string("0.1.\{v0 + d * 2 + k}"),
            "lines": [{ "kind": "fix", "label": "修复", "text": Json::string("\{name} 的第 \{d + 1} 天第 \{k + 1} 处修正，说得长一些好占满一行") }],
            "has": Json::boolean(true),
            "note": "",
          })
        })),
      })
    })
    { "part": Json::string(name), "label": Json::string(name), "days": Json::array(days) }
  }
  { "build": 1300, "tabs": [part("甲", 100), part("乙", 500)] }
}

///|
/// Where 更新日志's first day of part `name` is drawn down the window (none: not drawn).
fn first_day_y(t : @ui.Tester, name : String) -> Double {
  match t.rect_of("\{name} 第 1 天") {
    Some((_, y, _, _)) => y
    None => -1.0
  }
}

///|
test "更新日志 made once, its parts each scrolled and chosen again: each where it was left (as its old view's lists by their keys were: ui/list.mbt's states by id, till the page left the stack)" {
  let t = large_about_tester(true, 0, mode="settings-changelog", topics={ "changelog": @signals.signal(long_changelog()) })
  let ys = []
  ys.push(first_day_y(t, "甲"))
  // (a little: its parts' choice still in view, scrolling with the list)
  t.wheel(800.0, 500.0, 40.0)
  t.run_for(@ui.move_most_ms)
  ys.push(first_day_y(t, "甲"))
  t.tap_text("乙")
  t.run_for(@ui.move_most_ms)
  ys.push(first_day_y(t, "乙"))
  t.wheel(800.0, 500.0, 25.0)
  t.run_for(@ui.move_most_ms)
  ys.push(first_day_y(t, "乙"))
  t.tap_text("甲")
  t.run_for(@ui.move_most_ms)
  ys.push(first_day_y(t, "甲"))
  t.tap_text("乙")
  t.run_for(@ui.move_most_ms)
  ys.push(first_day_y(t, "乙"))
  assert_true(ys[1] < ys[0] && ys[3] < ys[2], msg="each scrolled: \{Repr(ys)}")
  assert_eq((ys[4], ys[5]), (ys[1], ys[3]), msg="each where it was left: \{Repr(ys)}")
}

///|
test "更新日志 made once, a change come on the first day and the last day left off (the list as long): each day the same, its changes' words the same nodes, the new one before them" {
  let changelog = @signals.signal(long_changelog())
  // (narrow on the tape: its changes' lines words to pick)
  let t = large_about_tester(true, 0, w=600.0, mode="settings-changelog", topics={ "changelog": changelog })
  let words = "修复甲 的第 1 天第 1 处修正，说得长一些好占满一行"
  let day = tree_node_of("甲 第 1 天")
  let line = tree_node_of(words)
  assert_true(day is Some(_) && line is Some(_))
  let (x, y, w, h) = t.rect_of(words).unwrap()
  t.drag(x + 2.0, y + h / 2.0, x + w + 20.0, y + h / 2.0)
  t.release(x + w + 20.0, y + h / 2.0)
  let picked = t.ctx().selected_text()
  assert_true(picked.contains("第 1 处修正"), msg="picked: \{picked}")
  changelog.set(long_changelog(days=11, more=true))
  t.run_for(@ui.move_most_ms)
  assert_true(tree_node_of("新增甲 那天又来的一处") is Some(_), msg="the new one")
  assert_true(tree_node_of("甲 第 1 天") == day, msg="the same day")
  assert_true(tree_node_of(words) == line, msg="the same change")
  assert_eq(t.ctx().selected_text(), picked, msg="the same words picked")
}

///|
/// How long changelog_dragged_past holds the pointer past the page's foot, and waits once it lets go: the list comes on
/// as long as it is held.
let held_past_ms : Double = 600.0

///|
/// 更新日志 of long_changelog made once in the tape's page narrow (600 by 900, keyboard and mouse): a
/// press on the first change's line, held past the page's foot a while (its list brought on under it), let go and a
/// while after, ⌘C, the page left. What was seen: the first day's place before, held, let go and after; the words
/// picked held and let go; what was copied; the words picked once the page is left.
fn changelog_dragged_past() -> (Array[Double], String, String, String, String) {
  let t = large_about_tester(true, 0, w=600.0, mode="settings-changelog", topics={ "changelog": @signals.signal(long_changelog()) })
  let line = "修复甲 的第 1 天第 1 处修正，说得长一些好占满一行"
  let (x, y, _, h) = t.rect_of(line).unwrap()
  let ys = [first_day_y(t, "甲")]
  t.press_at(x + 4.0, y + h / 2.0)
  t.move_to(x + 40.0, 898.0)
  t.run_for(held_past_ms)
  ys.push(first_day_y(t, "甲"))
  let held = t.ctx().selected_text()
  t.release(x + 40.0, 898.0)
  ys.push(first_day_y(t, "甲"))
  t.run_for(held_past_ms)
  ys.push(first_day_y(t, "甲"))
  let let_go = t.ctx().selected_text()
  t.key(@ui.key_code_copy, mods=@ui.mod_cmd)
  let copied = t.clipboard()
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  (ys, held, let_go, copied, t.ctx().selected_text())
}

///|
test "更新日志 made once, narrow: words picked dragged past the page's foot bring its list on, picking on; let go, it stops, what was picked kept and copied by ⌘C; the page left, kept still" {
  let (ys, held, let_go, copied, left) = changelog_dragged_past()
  assert_true(ys[1] < ys[0], msg="brought on while held: \{Repr(ys)}")
  assert_eq(ys[3], ys[2], msg="still once let go")
  assert_true(held.has_prefix("甲 的第 1 天") || held.contains("第 1 天第 1 处"), msg="from the line pressed: \{held}")
  assert_true(held.contains("第 3 天"), msg="picking on as it came: \{held}")
  assert_eq(let_go, held)
  assert_eq(copied, let_go)
  // (what was picked kept till a press elsewhere lets it go, the page gone or not: desktop.mbt select_none)
  assert_eq(left, let_go, msg="the page left")
}


///|
test "大屏 一台 station 的记忆 made once, wide, with keyboard and mouse and with a finger, at the system's larger words, the window wider: its rows the tree's own" {
  for case in [(0, 1.0, 1280.0), (2, 1.0, 1280.0), (0, 2.0, 1280.0), (0, 1.0, 1800.0)] {
    let (platform, scale, w) = case
    let made = large_about_tester(true, platform, scale~, w~, mode="settings-memory")
    assert_true(app.nav.top() == Setting(@settings.Route::Memory("ws1/st1")), msg="\{Repr(case)}")
    assert_true(instances_sorted(made).length() > 0)
    let own = tree_words_drawn()
    for w in [@sf.t("web-main.memory.global"), "习惯", "发布流程", "周报", "pdf、xlsx"] {
      assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="\{w} not the tree's own at \{Repr(case)}: \{Repr(own)}")
    }
  }
}

///|
test "大屏 一台 station 的记忆 made once, its own skills folded open and shut, wide" {
  for platform in [0, 2] {
    let t = large_about_tester(true, platform, mode="settings-memory")
    let shut0 = words_where(t)
    t.tap_text(@sf.t("web-main.memory.builtin"))
    t.run_for(@motion.ripple_tap_ms)
    let open = words_where(t)
    t.tap_text(@sf.t("web-main.memory.builtin"))
    t.run_for(@motion.ripple_tap_ms)
    let shut = words_where(t)
    let rows = fn(ws : Array[String]) { ws.iter().any(fn(w) { w.has_prefix("xlsx at") }) }
    assert_true(!rows(shut0) && rows(open) && !rows(shut), msg="its rows at \{platform}")
    same_drawn(shut, shut0, "shut again as at first at \{platform}")
  }
}

///|
test "大屏 一台 station 的记忆 made once, the language changed and the station renamed: its words said anew in the same nodes" {
  let lang = @signals.signal("")
  let t = large_about_tester(true, 0, mode="settings-memory", lang~)
  let global = @sf.t("web-main.memory.global")
  let section = tree_node_of(global)
  let row = tree_node_of("发布流程")
  let title = tree_node_of("Willow")
  assert_true(section is Some(_) && row is Some(_) && title is Some(_), msg="the tree's own: \{Repr(tree_words_drawn())}")
  lang.set("en")
  // The made-up prefs notify readers as the core would when the language changes.
  t.stepped()
  t.run_for(@ui.move_most_ms)
  let global_en = @sf.t("web-main.memory.global")
  assert_true(global_en != global, msg="in English: \{global_en}")
  assert_true(tree_node_of(global_en) == section && tree_node_of("发布流程") == row, msg="the same nodes")
  lang.set("")
  @sf.set_language(None)
  t.stepped()
  t.run_for(@ui.move_most_ms)
  @settings.fixture_call("workspace.renameStation", { "station": Json::string("st1"), "name": Json::string("工作室") }) |> ignore
  t.run_for(@ui.move_most_ms)
  assert_true(tree_node_of("工作室") == title, msg="renamed in the same node: \{Repr(tree_words_drawn())}")
}

///|
test "大屏 一台 station 的记忆 made once: what it is for by one mark after its title, its tip as the pointer rests on it" {
  let t = large_about_tester(true, 0, mode="settings-memory")
  let marks = t.semantics().filter(fn(n) { n.role == Button && n.label == @sf.t("web-main.about") })
  guard marks is [m] else { fail("its mark read out \{marks.length()} times") }
  let mark = m.rect
  t.move_to(mark.0 + mark.2 / 2.0, mark.1 + mark.3 / 2.0)
  t.run_for(@kit.tooltip_delay_ms + @ui.move_most_ms)
  let words = words_where(t)
  assert_true(words.iter().any(fn(w) { w.has_prefix(@sf.t("web-pages.settings.memory.lead")) }), msg="its tip: \{Repr(words)}")
}

///|
test "归档, 一台 station 的归档 and 自动决策 made once on a large screen and on the tape at its every width, narrow and wide, with keyboard and mouse and with a finger, at the system's larger words: what each says, its old view gone" {
  // (wide where its page is: 自动决策's row says whole what it decides, narrow short)
  for case in [
    (0, 1.0, 1280.0),
    (2, 1.0, 1280.0),
    (0, 2.0, 1280.0),
    (2, 1.0, 600.0),
    (0, 1.0, 700.0),
    (0, 1.0, 760.0),
    (2, 1.0, 839.0),
    (2, 1.5, 920.0),
    (0, 1.0, 1000.0),
  ] {
    let (platform, scale, w) = case
    let at = "\{Repr(case)}"
    let _ = large_about_tester(true, platform, scale~, w~, mode="settings-archiving")
    assert_true(app.nav.top() == Setting(@settings.Route::Archiving), msg=at)
    let own = tree_words_drawn()
    for words in ["Willow", @sf.t("web-pages.appearance.archive.title"), @sf.t("web-pages.archiving.auto.title")] {
      assert_true(own.iter().any(fn(o) { o.contains(words) }), msg="归档's \{words} the tree's own at \{at}: \{Repr(own)}")
    }
    let _ = large_about_tester(true, platform, scale~, w~, mode="settings-archiving:ws1/st1")
    let own = tree_words_drawn()
    for words in ["按模型判断", "7 天", "不归档", @sf.t("web-pages.archiving.slackHint")] {
      assert_true(own.iter().any(fn(o) { o.contains(words) }), msg="一台 station 的归档's \{words} the tree's own at \{at}: \{Repr(own)}")
    }
    let t = large_about_tester(true, platform, scale~, w~, mode="settings-decisions")
    let own = tree_words_drawn()
    let whole = own.iter().any(fn(o) { o.contains(@sf.t("web-pages.automaticDecisions.completionNote")) })
    let short = own.iter().any(fn(o) { o.contains(@sf.t("web-pages.automaticDecisions.completionShort")) })
    assert_true(whole != short, msg="自动决策's note one way at \{at}: \{Repr(own)}")
    if w >= 1280.0 {
      assert_true(whole, msg="自动决策 wide at \{at}")
    }
    if w <= 600.0 {
      assert_true(short, msg="自动决策 narrow at \{at}")
    }
    t.tap_text(@sf.t("web-pages.automaticDecisions.completion"))
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::AutoCompletion), msg="自动决策's row at \{at}")
  }
}

///|
/// 归档 made once `w` wide over the core's pictures, the network down, its first station's mark a picture by its address
/// (`url`): how many times that was asked for as the page was put up, as it stayed, as it was come back to from 自动决策
/// and as it stayed then; and each page's time on top it was put up in.
fn archiving_pictures_asked(w : Double, url : String) -> (Array[Int], Array[Int]) {
  let asked = []
  let stints : Array[Int] = []
  let base = fixture_app("settings-archiving")
  let core = core_pictures(fn(u, done) {
    asked.push(u)
    done(None)
  })
  let src : Source = {
    ..base,
    picture: fn(u, s) {
      if u == url && !stints.contains(s) {
        stints.push(s)
      }
      core(u, s)
    },
    topic_read: fn(name, params) {
      let r = base.topic(name, params).get().snapshot()
      guard name == "stations" && r.value is Some(Array(a)) else { return r }
      let first = match a.get(0) {
        Some(Object(m)) => {
          let m2 = m.copy()
          m2["icon"] = Json::string(url)
          [Json::object(m2)]
        }
        _ => []
      }
      { ..r, value: Some(Json::array(first + a[1:].to_owned())) }
    },
  }
  @sfdesk.pane_makes.val = true
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let mine = fn() { asked.filter(fn(u) { u == url }).length() }
  let counts = [mine()]
  let stay = fn() {
    for _ in 0..<5 {
      t.advance(@ui.move_most_ms)
      t.draw()
    }
  }
  stay()
  counts.push(mine())
  app.nav.push(Setting(@settings.Route::AutoDecisions))
  t.run_for(@ui.move_most_ms)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  counts.push(mine())
  stay()
  counts.push(mine())
  (counts, stints)
}

///|
test "归档 made once, on every screen: a station's picture that could not be had asked again as the page is come back to, not while it stays" {
  let url = "https://pictures.example/studio.png"
  let got = [390.0, 700.0, 1280.0].map(fn(w) { (w, archiving_pictures_asked(w, url)) })
  // (asked as it is put up; not while it stays; once again as it is come back to; not while it stays then)
  if got.iter().any(fn(g) { g.1.0 != [1, 1, 2, 2] }) {
    fail("\{Repr(got)}")
  }
}

///|
test "归档 made once, on every screen: a station's picture answered later, while the page stays, shown then in its emoji's place" {
  let url = "https://pictures.example/studio.png"
  let out = []
  for w in [390.0, 700.0, 1280.0] {
    let pending : Array[(Bytes?) -> Unit] = []
    let given : Array[String] = []
    let base = fixture_app("settings-archiving")
    let core = core_pictures(fn(u, done) { if u == url { pending.push(done) } else { done(None) } })
    let src : Source = {
      ..base,
      picture: fn(u, s) {
        let key = core(u, s)
        if u == url {
          given.push(key)
        }
        key
      },
      topic_read: fn(name, params) {
        let r = base.topic(name, params).get().snapshot()
        guard name == "stations" && r.value is Some(Array(a)) else { return r }
        let first = match a.get(0) {
          Some(Object(m)) => {
            let m2 = m.copy()
            m2["icon"] = Json::string(url)
            m2["emoji"] = Json::string("🛰")
            [Json::object(m2)]
          }
          _ => []
        }
        { ..r, value: Some(Json::array(first + a[1:].to_owned())) }
      },
    }
    @sfdesk.pane_makes.val = true
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform=0)
    t.run_for(@ui.move_most_ms)
    let emoji_before = tree_words_drawn().iter().any(fn(o) { o.contains("🛰") })
    let asked_before = pending.length()
    // (the page stays; the core answers: its bytes)
    t.advance(@ui.move_most_ms)
    t.draw()
    for done in pending {
      done(Some(late_gif()))
    }
    t.run_for(@ui.move_most_ms)
    let shown = given.iter().any(fn(k) { k.has_prefix("mem:picture/") })
    // (and drawn: its bytes decoded, an instance of it in the frame)
    let drawn = t.drawlist_images().iter().any(fn(d) { d.1.has_prefix("mem:picture/") })
    let emoji_after = tree_words_drawn().iter().any(fn(o) { o.contains("🛰") })
    if !(asked_before == 1 && emoji_before && shown && drawn && !emoji_after && pending.length() == 1) {
      out.push("\{w}: asked \{asked_before} then \{pending.length()}, emoji \{emoji_before} then \{emoji_after}, read again with its key \{shown}, drawn \{drawn}")
    }
  }
  if out.length() > 0 {
    fail(out.join("\n"))
  }
}

///|
/// A GIF 2 by 1 of two frames, 100 ms each (ui's gif_test's): a picture the core may answer with.
fn late_gif() -> Bytes {
  Bytes::from_array([
    b'G', b'I', b'F', b'8', b'9', b'a', b'\x02', b'\x00', b'\x01', b'\x00', b'\x80', b'\x00', b'\x00', b'\xFF', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\xFF', b'\x21', b'\xF9', b'\x04', b'\x00', b'\x0A', b'\x00', b'\x00', b'\x00', b'\x2C',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x01', b'\x00', b'\x00', b'\x02', b'\x02', b'\x04', b'\x0A',
    b'\x00', b'\x21', b'\xF9', b'\x04', b'\x00', b'\x0A', b'\x00', b'\x00', b'\x00', b'\x2C', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x02', b'\x00', b'\x01', b'\x00', b'\x00', b'\x02', b'\x02', b'\x4C', b'\x0A', b'\x00', b'\x3B',
  ])
}

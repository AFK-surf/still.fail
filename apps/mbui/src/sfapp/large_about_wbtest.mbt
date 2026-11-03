// 关于 made once on a large screen (sfdesk's pane_made: the pane off the tape, the page laid out wide by the width the
// frame gives it) drawn as its old view was there (the same fixture, the same frame, its page the old view's): every
// instance the window draws the same, at rest and as an update goes; its parts the tree's own.

///|
/// 关于 on a large screen (`platform`'s input), `w` × 900, in the window's tree's frame: its page its old view's (`tree`
/// false: pane_makes off till the next such tester), or made once.
fn large_about_tester(
  tree : Bool,
  platform : Int,
  w? : Double = 1280.0,
  mode? : String = "settings-about",
  wait? : Double = @ui.move_most_ms,
  scale? : Double = 1.0,
  window_inset? : Bool = false,
  lang? : Ref[String] = Ref(""),
  topics? : Map[String, @signals.Signal[Json]] = {},
) -> @ui.Tester {
  let base = fixture_app(mode)
  // (the core's language as `lang` says it, where it says one)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match topics.get(name) {
        Some(v) => return { value: Some(v.get()), error: None, version: 1 }
        None => ()
      }
      let got = (base.topic)(name, params)
      if name != "prefs" || lang.val == "" {
        return got
      }
      let o = match got.value {
        Some(Object(m)) => m.copy()
        _ => {}
      }
      o["lang"] = Json::string(lang.val)
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
test "大屏 关于 made once: every instance drawn as its old view's, wide, with keyboard and mouse and with a finger, at the system's larger words, the window wider" {
  for case in [(0, 1.0, 1280.0), (2, 1.0, 1280.0), (0, 2.0, 1280.0), (0, 1.0, 1800.0)] {
    let (platform, scale, w) = case
    let old = large_about_tester(false, platform, scale~, w~)
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = large_about_tester(true, platform, scale~, w~)
    assert_true(app.nav.top() == Setting(@settings.Route::About))
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
  }
}

///|
test "大屏 关于 made once: as an update goes (offered, checked, its bar opening, downloaded, ready), each moment drawn as its old view's" {
  let moments = [1000.0, 2190.0, 2240.0, 2300.0, 2500.0, 4000.0, 6000.0]
  let old = large_about_tester(false, 0, mode="settings-about-flow", wait=0.0)
  let olds = []
  let mut at = 0.0
  for m in moments {
    old.run_for(m - at)
    at = m
    olds.push((instances_sorted(old), words_where(old)))
  }
  let made = large_about_tester(true, 0, mode="settings-about-flow", wait=0.0)
  at = 0.0
  for i, m in moments {
    made.run_for(m - at)
    at = m
    same_drawn(words_where(made), olds[i].1, "words at \{m}")
    same_drawn(instances_sorted(made), olds[i].0, "instances at \{m}")
  }
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
    assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="not the tree's own: \{w} in \{own}")
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
test "大屏 关于 made once, come to and the sidebar shown a while with no frame between: the page moved aside by what it shows as it is then, as with a frame between, as its old view is" {
  let old = about_peeked(false, true)
  let framed = about_peeked(true, true)
  let at_once = about_peeked(true, false)
  assert_eq(framed, old)
  assert_eq(at_once, old)
  match old {
    Some((_, aside, _, _)) => assert_true(aside > 0.0, msg="moved aside: \{old}")
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
test "大屏 关于, its old view and made once alike: words dragged over with the mouse picked none (its words plain, as the old view's c.text: none of them to be picked)" {
  for made in [false, true] {
    let t = large_about_tester(made, 0)
    t.drag(410.0, 140.0, 700.0, 260.0)
    t.release(700.0, 260.0)
    assert_eq(t.ctx().selected_text(), "", msg="made \{made}")
  }
}

///|
test "中屏 关于 made once on the tape, its page wide (under the tape's bar): every instance drawn as its old view's, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0, 839.0), (0, 1.0, 760.0), (2, 2.0, 839.0)] {
    let (platform, scale, w) = case
    let old = large_about_tester(false, platform, scale~, w~)
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = large_about_tester(true, platform, scale~, w~)
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
  }
}

///|
/// Where a press across the top of the window drags it (Tester::drags_window_at), in a window with its buttons in the
/// app's top row (macOS's): at every 20 across, 6, 24 and 46 down; `made` as large_about_tester's.
fn about_drags(made : Bool, platform : Int) -> Array[String] {
  let t = large_about_tester(made, platform, window_inset=true)
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
test "大屏 关于 made once in a window with its buttons in the app's top row: a press across the page's top drags the window where its old view's did, nowhere else" {
  for platform in [0, 2] {
    let old = about_drags(false, platform)
    assert_true(old.iter().any(fn(p) { p.has_prefix("1250,") }), msg="the page's top drags it: \{old}")
    assert_eq(about_drags(true, platform), old, msg="at \{platform}")
  }
}

///|
test "记忆 made once, its page wide on a large screen and on the tape: every instance drawn as its old view's; its rows the tree's own" {
  for case in [(0, 1.0, 1280.0), (2, 2.0, 1280.0), (2, 1.0, 839.0), (0, 1.0, 600.0)] {
    let (platform, scale, w) = case
    let old = large_about_tester(false, platform, scale~, w~, mode="settings-memories")
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = large_about_tester(true, platform, scale~, w~, mode="settings-memories")
    assert_true(app.nav.top() == Setting(@settings.Route::Memories), msg="on top: \{@sfbase.page_kind(app.nav.top())}")
    let own = tree_words_drawn()
    assert_true(own.iter().any(fn(o) { o.contains(@sf.t("android-misc.memory.note")) }), msg="its lead the tree's: \{own}")
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
  }
}

///|
test "大屏 关于 made once over 更新日志, the language changed: its back says where it goes in the new one, the same page and the same back; its title too" {
  let lang = Ref("")
  let t = large_about_tester(true, 0, mode="settings-changelog", lang~)
  app.nav.push(Setting(@settings.Route::About))
  t.run_for(@ui.move_most_ms)
  let back = @sf.t("web-pages.settings.nav.changelog")
  let page = @sfdesk.pane_made_seen()
  let back_node = tree_node_of(back)
  assert_true(page is Some(_) && back_node is Some(_), msg="its back the tree's: \{tree_words_drawn()}")
  lang.val = "en"
  t.run_for(@ui.move_most_ms)
  let back_en = @sf.t("web-pages.settings.nav.changelog")
  let title_en = @sf.t("web-pages.settings.nav.about")
  assert_true(back_en != back, msg="in English: \{back_en}")
  let words = tree_words_drawn()
  assert_true(words.contains(back_en) && words.contains(title_en), msg="said anew: \{words}")
  assert_true(@sfdesk.pane_made_seen() == page, msg="the same page")
  assert_true(tree_node_of(back_en) == back_node, msg="the same back")
  lang.val = ""
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
test "更新日志 made once on a large screen and on the tape, wide and narrow: every instance drawn as its old view's; its days' words the tree's own" {
  for case in [(0, 1.0, 1280.0), (2, 2.0, 1280.0), (2, 1.0, 839.0), (0, 1.0, 600.0), (2, 2.0, 600.0)] {
    let (platform, scale, w) = case
    let old = large_about_tester(false, platform, scale~, w~, mode="settings-changelog")
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = large_about_tester(true, platform, scale~, w~, mode="settings-changelog")
    assert_true(app.nav.top() == Setting(@settings.Route::Changelog))
    assert_true(tree_words_drawn().iter().any(fn(o) { o.contains("10 月 19 日") }), msg="its day the tree's: \{case}")
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
  }
}

///|
test "更新日志 made once on a small screen: every instance drawn as its old view's" {
  for case in [(2, 1.0), (0, 2.0)] {
    let (platform, scale) = case
    let (old, _) = settings_home_tester(false, platform, mode="settings-changelog", scale~)
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let (made, _) = settings_home_tester(true, platform, mode="settings-changelog", scale~)
    assert_true(app.nav.top() == Setting(@settings.Route::Changelog))
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
  }
}

///|
test "更新日志 made once, its page narrow on the tape: a change's line with its kind dragged over with the mouse picks its words as its old view's did" {
  let line = "设置里可以添加 station 和 Profile"
  let said = []
  for made in [false, true] {
    let t = large_about_tester(made, 0, w=600.0, mode="settings-changelog")
    guard t.rect_of("新增" + line) is Some((x, y, w, h)) else { fail("no line, made \{made}") }
    let mid = y + h / 2.0
    t.drag(x + 2.0, mid, x + w + 40.0, mid)
    t.release(x + w + 40.0, mid)
    said.push(t.ctx().selected_text())
  }
  assert_true(said[0].contains("station"), msg="the old one's: \{said}")
  assert_eq(said[1], said[0])
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
  assert_true(ys[1] < ys[0] && ys[3] < ys[2], msg="each scrolled: \{ys}")
  assert_eq((ys[4], ys[5]), (ys[1], ys[3]), msg="each where it was left: \{ys}")
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
/// 更新日志 of long_changelog in the tape's page narrow (600 by 900, keyboard and mouse), its old view's or made once: a
/// press on the first change's line, held past the page's foot a while (its list brought on under it), let go and a
/// while after, ⌘C, the page left. What was seen: the first day's place before, held, let go and after; the words
/// picked held and let go; what was copied; the words picked once the page is left.
fn changelog_dragged_past(made : Bool) -> (Array[Double], String, String, String, String) {
  let t = large_about_tester(made, 0, w=600.0, mode="settings-changelog", topics={ "changelog": @signals.signal(long_changelog()) })
  let line = "修复甲 的第 1 天第 1 处修正，说得长一些好占满一行"
  let (x, y, _, h) = t.rect_of(line).unwrap()
  let ys = [first_day_y(t, "甲")]
  t.press_at(x + 4.0, y + h / 2.0)
  t.move(x + 40.0, 898.0)
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
test "更新日志 made once, narrow: words picked dragged past the page's foot bring its list on, picking on; let go, it stops, what was picked kept and copied by ⌘C; the page left, as its old view's" {
  let (oys, oheld, olet, ocopied, oleft) = changelog_dragged_past(false)
  let (ys, held, let_go, copied, left) = changelog_dragged_past(true)
  // (the old view's: brought on held, still once let go)
  assert_true(oys[1] < oys[0] && oys[3] == oys[2], msg="the old one's: \{oys}")
  assert_true(ys[1] < ys[0], msg="brought on while held: \{ys}")
  assert_eq(ys[3], ys[2], msg="still once let go")
  assert_true(held.has_prefix("甲 的第 1 天") || held.contains("第 1 天第 1 处"), msg="from the line pressed: \{held}")
  assert_true(held.contains("第 3 天"), msg="picking on as it came: \{held}")
  assert_eq(let_go, held)
  assert_eq(copied, let_go)
  assert_true(oheld.contains("第 3 天") && ocopied == olet, msg="the old one's: \{oheld}")
  assert_eq(left, oleft, msg="the page left")
}

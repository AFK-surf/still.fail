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
) -> @ui.Tester {
  let base = fixture_app(mode)
  // (the core's language as `lang` says it, where it says one)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
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

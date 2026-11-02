// The settings' list made once as nodes of the window's tree (sfpages' settings_home_node, the narrow shell's made
// page) drawn as its old view was (the same fixture drawn by the old frame alone): every instance the window draws the
// same, at rest, with a finger and with keyboard and mouse; what the core says of a row followed by its node, the page
// not made again; its rows pressed opening their pages.

///|
/// The settings' list on a small screen (`platform`'s input), 390 × `h`: drawn by the old frame alone (`tree` false),
/// or by the window's tree, its page made once.
fn settings_home_tester(
  tree : Bool,
  platform : Int,
  h? : Double = 2400.0,
  mode? : String = "settings-home",
  wait? : Double = @ui.move_most_ms,
) -> (@ui.Tester, Source) {
  let src = fixture_app(mode)
  let t = if tree {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h~, platform~)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h~, platform~)
  }
  t.run_for(wait)
  (t, src)
}

///|
/// What the window draws, each instance's numbers rounded to a hundredth, in one order whatever order they were drawn in
/// (read at once: the Tester's are what the window last drew, whichever Tester that was).
fn instances_sorted(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances().map(fn(a) {
    a
    .mapi(fn(j, x) {
      // (a glyph's place in its atlas, 12 and 13: where the order its glyphs were first drawn in put it, not what is
      // drawn; which atlas (12 past 16384: the colour one) and its cell's size, 14 and 15, kept)
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
/// The words the window draws, each with where, in one order (read at once, as instances_sorted).
fn words_where(t : @ui.Tester) -> Array[String] {
  let all = t.words().map(fn(w) { "\{w.0} at \{(w.1 * 100.0).round() / 100.0},\{(w.2 * 100.0).round() / 100.0}" })
  all.sort()
  all
}

///|
/// The words drawn by nodes of the window's tree of their own (not an old view's, hosted): the page's own.
fn tree_words_drawn() -> Array[String] {
  match @ui.view_tree() {
    Some(tree) => tree.drawn().filter(fn(d) { !d.hosted && d.words != "" }).map(fn(d) { d.words })
    None => []
  }
}

///|
/// `made` the same as `old`, the whole of each in order (each repeated as often); else what each has the other has not,
/// a few of them, said.
fn same_drawn(made : Array[String], old : Array[String], what : String) -> Unit raise Error {
  if made == old {
    return
  }
  let left = old.copy()
  let extra = []
  for m in made {
    match left.search(m) {
      Some(i) => left.remove(i) |> ignore
      None => extra.push(m)
    }
  }
  let kinds = fn(a : Array[String]) {
    let m : Map[String, Int] = {}
    for x in a {
      let parts = x.split(",").collect()
      let k = if parts.length() > 5 { parts[5].to_string() } else { "?" }
      m[k] = m.get(k).unwrap_or(0) + 1
    }
    m.to_array().map(fn(e) { "kind \{e.0}: \{e.1}" }).join(", ")
  }
  // (each whole: what differs may be any of its numbers, where it is cut or faded as much as where it is)
  let short = fn(a : Array[String]) {
    a.join("\n  ")
  }
  fail(
    "\{what}: made \{made.length()}, old \{old.length()}; by kind, old's alone \{kinds(left)}; made's alone \{kinds(extra)}\nold's alone:\n  \{short(left)}\nmade's alone:\n  \{short(extra)}",
  )
}

///|
test "the settings' list made once: every instance drawn as its old view's, with a finger and with keyboard and mouse" {
  for platform in [2, 0] {
    let (old, _) = settings_home_tester(false, platform)
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let (made, _) = settings_home_tester(true, platform)
    assert_true(app.nav.top() == Settings)
    // (the words first: what differs said by what it says)
    same_drawn(words_where(made), old_words, "words")
    same_drawn(instances_sorted(made), old_drawn, "instances")
  }
}

///|
test "the settings' list made once: its title, back, headings, rows and what they say are the tree's own nodes" {
  let (_, _) = settings_home_tester(true, 2)
  let own = tree_words_drawn()
  for w in ["设置", "外观", "通知", "关于", "密钥", "星火工作室", "林"] {
    assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="not the tree's own: \{w} in \{own}")
  }
}

///|
test "the settings' list made once: a row pressed opens its page" {
  let (t, _) = settings_home_tester(true, 2)
  let at = t.find("外观")
  let shown = t.words().map(fn(w) { w.0 })
  assert_true(shown.contains("外观"), msg="外观 not shown: \{shown}")
  t.tap_text("外观")
  t.run_for(@ui.move_most_ms)
  assert_true(
    app.nav.top() == Setting(@settings.Route::Appearance),
    msg="at \{at}: on top \{@sfbase.page_kind(app.nav.top())}, \{app.nav.depth()} deep",
  )
}

///|
test "关于 made once: every instance drawn as its old view's, with an update on its way and statistics sent" {
  for platform in [2, 0] {
    let (old, _) = settings_home_tester(false, platform, mode="settings-about")
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let (made, _) = settings_home_tester(true, platform, mode="settings-about")
    assert_true(app.nav.top() == Setting(@settings.Route::About))
    // (the words first: what differs said by what it says)
    same_drawn(words_where(made), old_words, "words")
    same_drawn(instances_sorted(made), old_drawn, "instances")
  }
}

///|
test "关于 made once: as an update goes (offered, checked, its bar opening, downloaded, ready), each moment drawn as its old view's" {
  let moments = [1000.0, 2190.0, 2240.0, 2300.0, 2500.0, 4000.0, 6000.0]
  let (old, _) = settings_home_tester(false, 2, mode="settings-about-flow", wait=0.0)
  let olds = []
  let mut at = 0.0
  for m in moments {
    old.run_for(m - at)
    at = m
    olds.push((instances_sorted(old), words_where(old)))
  }
  let (made, _) = settings_home_tester(true, 2, mode="settings-about-flow", wait=0.0)
  at = 0.0
  for i, m in moments {
    made.run_for(m - at)
    at = m
    same_drawn(words_where(made), olds[i].1, "words at \{m}")
    same_drawn(instances_sorted(made), olds[i].0, "instances at \{m}")
  }
}

///|
test "关于 made once: its title, rows and switch are the tree's own nodes; its switch turned, statistics told so" {
  let (t, _) = settings_home_tester(true, 2, mode="settings-about")
  let own = tree_words_drawn()
  for w in [@sf.t("web-pages.settings.nav.about"), @sf.t("web-pages.settings.nav.changelog"), @sf.t("common.legal.terms"), @sf.t("common.legal.privacy")] {
    assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="not the tree's own: \{w} in \{own}")
  }
  let told : Array[Bool] = []
  reporting_host.set(Some({ get: fn() { told.last().unwrap_or(true) }, set: fn(on) { told.push(on) } }))
  t.click(Switch, label=@sf.t("common.telemetry.title"))
  t.run_for(@ui.move_most_ms)
  assert_eq(told, [false])
}

///|
/// The node of the tree's that draws `words` (its own, not an old view's), if one does.
fn tree_node_of(words : String) -> @view.NodeId? {
  match @ui.view_tree() {
    Some(tree) =>
      match tree.drawn().search_by(fn(d) { !d.hosted && d.words == words }) {
        Some(i) => Some(tree.drawn()[i].id)
        None => None
      }
    None => None
  }
}

///|
test "the settings' list made once: what the core says of a row followed by the same nodes, the page made no more" {
  let (t, _) = settings_home_tester(true, 2)
  let title = tree_node_of("通知")
  let page = tree_node_of("设置")
  assert_true(title is Some(_) && page is Some(_))
  let off = @sf.t("web-pages.notifications.off")
  assert_true(tree_node_of(off) is None)
  // (switched off where its page switches it: what the row says at its end follows, at the next frame drawn)
  // (told from outside any event, a frame of the clock alone: the node told of it, nothing built again for it)
  @settings.notify_switched.set(Some(false))
  t.frame_at(t.next_frame_time())
  assert_true(tree_node_of(off) is Some(_), msg="\{tree_words_drawn()}")
  assert_true(tree_node_of("通知") == title && tree_node_of("设置") == page)
}

///|
test "the settings' list made once, as its screen is recorded: what shows drawn as the old view's; the text asked beyond it, said" {
  // (each played as screens_wbtest plays it, to the Mac's last frame; read at once)
  let old = screen_played("settings-home", @ui.move_most_ms, tree=false)
  let (old_drawn, old_words, old_missing) = (instances_sorted(old), words_where(old), old.text_missing())
  let made = screen_played("settings-home", @ui.move_most_ms)
  let (made_drawn, made_words, made_missing) = (instances_sorted(made), words_where(made), made.text_missing())
  // (each said as it is, whichever differs)
  let said = "old lacks \{old_missing.length()}: \{old_missing}\nmade lacks \{made_missing.length()}: \{made_missing}"
  same_drawn(made_drawn, old_drawn, "instances (\{said})")
  same_drawn(made_words, old_words, "words (\{said})")
  assert_eq(made_missing, old_missing, msg=said)
}

///|
test "the settings' list made once: flung by a finger, it glides on as a list's does, said so till it is at rest" {
  let (t, _) = settings_home_tester(true, 2, h=844.0)
  let at = fn() { t.words().filter(fn(w) { w.0 == "外观" }).map(fn(w) { w.2 }) }
  let before = at()
  t.drag(195.0, 600.0, 195.0, 200.0)
  let end = @ui.rest_of("a list's")
  assert_true(end > t.time(), msg="at rest at \{end}, now \{t.time()}; 外观 at \{before} before, \{at()} after")
  t.run_for(end - t.time())
  assert_eq(@ui.rest_of("a list's"), -1.0)
}

///|
test "the settings' list dragged on past its end by a finger, counted taller below than it is: held at its end as it really is while the finger is still on it, where it rests let go" {
  let (t, _) = settings_home_tester(true, 2, h=844.0)
  let at = fn() { t.words().filter(fn(w) { w.0 == "外观" }).map(fn(w) { w.2 }) }
  let before = at()
  t.touch(0, 195.0, 600.0)
  for k in 1..=10 {
    t.advance(@ui.drag_step_ms)
    t.touch(1, 195.0, 600.0 - 40.0 * k.to_double())
    t.draw()
  }
  let held = at()
  t.touch(2, 195.0, 200.0)
  // (let go: on to where it rests, as its glide says, and at rest there)
  let end = @ui.rest_of("a list's")
  if end > t.time() {
    t.run_for(end - t.time())
  }
  assert_eq(@ui.rest_of("a list's"), -1.0)
  let rests = at()
  assert_true(before.length() == 1 && held.length() == 1 && rests.length() == 1, msg="\{before} \{held} \{rests}")
  assert_true(held[0] < before[0], msg="not moved by the finger: \{before} \{held}")
  assert_eq(held, rests)
}

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
  scale? : Double = 1.0,
  corners_held? : Bool = true,
) -> (@ui.Tester, Source) {
  let src = fixture_app(mode)
  let t = if tree {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h~, platform~, corners_held~)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h~, platform~, corners_held~)
  }
  // (the system's size of words as said)
  t.set_font_scale(scale)
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
test "the settings' list made once: every instance drawn as its old view's, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 2.0)] {
    let (platform, scale) = case
    // (at twice the words main's old view of this list breaks the corner rule (its account card's row, 18 round in a
    // card 22.8 round, too square to follow it): what this compares with, not held here, its fault said and kept
    // known; every other case, and every other page at any size, held as ever)
    let corners_held = scale < 2.0
    let (old, _) = settings_home_tester(false, platform, scale~, corners_held~)
    if !corners_held {
      let faults = old.corner_faults()
      assert_true(faults.length() == 1 && faults[0].contains("lin@example.com"), msg="main's own fault at \{scale}: \{faults}")
    }
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let (made, _) = settings_home_tester(true, platform, scale~, corners_held~)
    if !corners_held {
      // (the tree's drawn as the old view's, every instance (below); its corner checker finds nothing: it does not look
      // at that pair among the tree's own nodes, the old views' alone, a difference of what it checks, said so)
      assert_eq(made.corner_faults(), [])
    }
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
test "关于 made once: every instance drawn as its old view's, with an update on its way and statistics sent, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 2.0)] {
    let (platform, scale) = case
    let (old, _) = settings_home_tester(false, platform, mode="settings-about", scale~)
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let (made, _) = settings_home_tester(true, platform, mode="settings-about", scale~)
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

///|
/// 记忆 on a small screen (`platform`'s input), 390 × 2400, its stations as the fixture has them, never come (`held`) or
/// failed (`failed`): drawn by the old frame alone (`tree` false) or by the window's tree, its page made once.
fn memories_tester(
  tree : Bool,
  platform : Int,
  held? : Bool = false,
  failed? : Bool = false,
  scale? : Double = 1.0,
  mode? : String = "settings-memories",
  calls? : Array[String] = [],
  wrap? : (Source) -> Source = fn(s) { s },
) -> @ui.Tester {
  let made = fixture_app(mode)
  // (what is asked of the core, by name, kept in `calls`)
  let base : Source = {
    ..made,
    call: fn(name, params, done) {
      calls.push(name)
      (made.call)(name, params, done)
    },
  }
  let base = wrap(base)
  let src = if held {
    @sffixture.held_topics(base, ["stations"])
  } else if failed {
    @sffixture.failed_topics(base, ["stations"], "网络连接失败")
  } else {
    base
  }
  let t = if tree {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=2400.0, platform~)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=2400.0, platform~)
  }
  // (the system's size of words as said: what the bones' bars are as high as follows it)
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "记忆 made once: every instance drawn as its old view's, a station online and one offline, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let old = memories_tester(false, platform, scale~)
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = memories_tester(true, platform, scale~)
    assert_true(app.nav.top() == Setting(@settings.Route::Memories))
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
  }
}

///|
test "记忆 made once, its stations read the first time: its list in its bones as the old view's, as it breathes, at the system's sizes of words; none of it found or read out" {
  for scale in [1.0, 1.5, 2.0] {
    let seen = fn(tree : Bool) {
      let t = memories_tester(tree, 2, held=true, scale~)
      let t0 = t.time()
      let out = [instances_sorted(t)]
      for dt in [@sf.breath_ms / 4.0, @sf.breath_ms / 2.0] {
        t.frame_at(t0 + dt)
        out.push(instances_sorted(t))
      }
      (out, words_where(t), t.words_said().map(fn(w) { w.0 }))
    }
    let (old, old_words, old_said) = seen(false)
    let (made, made_words, made_said) = seen(true)
    same_drawn(made_words, old_words, "words at \{scale}")
    assert_eq(made_said, old_said, msg="read out at \{scale}")
    for i, o in old {
      same_drawn(made[i], o, "instances at \{scale}, step \{i}")
      assert_true(o.length() > 0, msg="nothing drawn at \{scale}, step \{i}")
    }
    // (it breathes: not drawn the same at its faintest as at first)
    assert_true(made[0] != made[2], msg="not breathing at \{scale}")
    assert_true(!made_words.iter().any(fn(w) { w.contains("字") }), msg="\{made_words}")
  }
}

///|
test "记忆 made once, its stations not read: what failed said over its list in its bones, still, read out, as the old view's, at the system's sizes of words" {
  for scale in [1.0, 1.5, 2.0] {
    let seen = fn(tree : Bool) {
      let t = memories_tester(tree, 2, failed=true, scale~)
      let t0 = t.time()
      let out = [instances_sorted(t)]
      t.frame_at(t0 + @sf.breath_ms / 2.0)
      out.push(instances_sorted(t))
      (out, words_where(t), t.words_said().map(fn(w) { w.0 }), t.find("网络连接失败") is Some(_))
    }
    let (old, old_words, old_said, _) = seen(false)
    let (made, made_words, made_said, found) = seen(true)
    same_drawn(made_words, old_words, "words at \{scale}")
    assert_eq(made_said, old_said, msg="read out at \{scale}")
    assert_true(made_said.contains("网络连接失败"), msg="\{made_said}")
    assert_true(found)
    for i, o in old {
      same_drawn(made[i], o, "instances at \{scale}, step \{i}")
      assert_true(o.length() > 0, msg="nothing drawn at \{scale}, step \{i}")
    }
    // (still: what failed stops its breath, whole at its faintest's moment as at first)
    same_drawn(made[1], made[0], "still at \{scale}")
  }
}

///|
test "记忆 made once: its rows are the tree's own; an online station's opens its memory" {
  let t = memories_tester(true, 2)
  let own = tree_words_drawn()
  for w in [@sf.t("web-pages.settings.memory.title"), @sf.t("android-misc.memory.note"), @sf.t("android-misc.memory.row")] {
    assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="not the tree's own: \{w} in \{own}")
  }
  t.tap_text(@sf.t("android-misc.memory.row"))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Setting(@settings.Route::Memory(_)), msg="on top \{@sfbase.page_kind(app.nav.top())}")
}

///|
test "归档 made once: every instance drawn as its old view's, its choice, notes and stations, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let old = memories_tester(false, platform, scale~, mode="settings-archiving")
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = memories_tester(true, platform, scale~, mode="settings-archiving")
    assert_true(app.nav.top() == Setting(@settings.Route::Archiving))
    same_drawn(words_where(made), old_words, "words at \{case}")
    same_drawn(instances_sorted(made), old_drawn, "instances at \{case}")
    assert_true(old_drawn.length() > 0)
  }
}

///|
test "归档 made once, its stations read the first time: their rows in their bones as the old view's, as they breathe" {
  for scale in [1.0, 2.0] {
    let seen = fn(tree : Bool) {
      let t = memories_tester(tree, 2, held=true, scale~, mode="settings-archiving")
      let t0 = t.time()
      let out = [instances_sorted(t)]
      t.frame_at(t0 + @sf.breath_ms / 2.0)
      out.push(instances_sorted(t))
      (out, words_where(t), t.words_said().map(fn(w) { w.0 }))
    }
    let (old, old_words, old_said) = seen(false)
    let (made, made_words, made_said) = seen(true)
    same_drawn(made_words, old_words, "words at \{scale}")
    assert_eq(made_said, old_said, msg="read out at \{scale}")
    for i, o in old {
      same_drawn(made[i], o, "instances at \{scale}, step \{i}")
      assert_true(o.length() > 0)
    }
  }
}

///|
test "归档 made once: its own nodes; its choice chosen, what the one chosen means said under it, the one set chosen again saying nothing" {
  let calls : Array[String] = []
  let t = memories_tester(true, 2, mode="settings-archiving", calls~)
  let own = tree_words_drawn()
  for w in [@sf.t("web-pages.archiving.title"), @sf.t("web-pages.archiving.auto.title")] {
    assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="not the tree's own: \{w} in \{own}")
  }
  let sets = fn() { calls.filter(fn(n) { n == "prefs.set" }).length() }
  // (the one set (做完就提示, the device's own) chosen again: nothing kept anew)
  t.tap_text(@sf.t("web-pages.appearance.archive.done"))
  t.run_for(@ui.move_most_ms)
  assert_eq(sets(), 0)
  t.tap_text(@sf.t("web-pages.appearance.archive.off"))
  t.run_for(@ui.move_most_ms)
  assert_eq(sets(), 1)
  assert_true(t.find(@sf.t("web-pages.appearance.archive.offHint")) is Some(_), msg="\{t.words().map(fn(w) { w.0 })}")
}

///|
/// `base` with each station's own archiving (its overview's) as `f` makes it of the core's, as `f` is now (followed:
/// the core said to have it anew), and the station's save `busy()` on its way as long as that says so (the core's
/// `doing`).
fn archiving_as(base : Source, f : @signals.Signal[(Json) -> Json], busy : @signals.Signal[Bool]) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let r = (base.topic)(name, params)
      match name {
        "stations" => {
          let g = f.get()
          let value = match r.value {
            Some(Array(a)) =>
              Some(
                Json::array(
                  a.map(fn(st) {
                    match st {
                      Object(m) =>
                        match m.get("overview") {
                          Some(Object(o)) =>
                            match o.get("archiving") {
                              Some(ar) => {
                                let o2 = o.copy()
                                o2["archiving"] = g(ar)
                                let m2 = m.copy()
                                m2["overview"] = Json::object(o2)
                                Json::object(m2)
                              }
                              None => st
                            }
                          _ => st
                        }
                      _ => st
                    }
                  }),
                ),
              )
            v => v
          }
          { ..r, value, }
        }
        "doing" if busy.get() =>
          {
            ..r,
            value: Some({
              "doing": [{ "call": "archiving.save", "stage": "running", "params": { "station": "ws1/st1" } }],
            }),
          }
        _ => r
      }
    },
  }
}

///|
/// An archiving of the core's with `fields` said anew.
fn archiving_with(fields : Array[(String, Json)]) -> (Json) -> Json {
  fn(ar) {
    match ar {
      Object(m) => {
        let m2 = m.copy()
        for kv in fields {
          m2[kv.0] = kv.1
        }
        Json::object(m2)
      }
      _ => ar
    }
  }
}

///|
/// The station's own archiving page (st1's), as an old view's or made once, its archiving as `f` has it.
fn station_archiving_tester(
  tree : Bool,
  platform : Int,
  scale? : Double = 1.0,
  f? : @signals.Signal[(Json) -> Json] = @signals.signal(fn(a) { a }),
  busy? : @signals.Signal[Bool] = @signals.signal(false),
  calls? : Array[String] = [],
) -> @ui.Tester {
  memories_tester(tree, platform, scale~, mode="settings-archiving:ws1/st1", calls~, wrap=fn(s) { archiving_as(s, f, busy) })
}

///|
test "一台 station 的归档 made once: every instance drawn as its old view's, with a finger and with keyboard and mouse, at the system's larger words; its managers' alone, off, and not online" {
  let cases : Array[(String, Int, Double, (Json) -> Json)] = [
    ("as it is", 2, 1.0, fn(a) { a }),
    ("as it is", 0, 1.0, fn(a) { a }),
    ("as it is", 2, 1.5, fn(a) { a }),
    ("as it is", 2, 2.0, fn(a) { a }),
    ("not a manager", 2, 1.0, archiving_with([("canEdit", Json::boolean(false))])),
    ("off", 2, 1.0, archiving_with([("mode", Json::string("off"))])),
    ("too old to say", 2, 1.0, fn(_) { Json::null() }),
  ]
  for c in cases {
    let (what, platform, scale, f) = c
    let old = station_archiving_tester(false, platform, scale~, f=@signals.signal(f))
    let old_drawn = instances_sorted(old)
    let old_words = words_where(old)
    let made = station_archiving_tester(true, platform, scale~, f=@signals.signal(f))
    assert_true(app.nav.top() == Setting(@settings.Route::StationArchiving("ws1/st1")), msg="\{what}")
    same_drawn(words_where(made), old_words, "words, \{what} at \{platform} \{scale}")
    same_drawn(instances_sorted(made), old_drawn, "instances, \{what} at \{platform} \{scale}")
    assert_true(old_drawn.length() > 0)
  }
}

///|
/// How many saves of the station's archiving were asked for, in a page made once or an old one, after `act` (taps by
/// words), as its archiving is (`f`) and a save of it on its way or not (`busy`).
fn station_archiving_saves(tree : Bool, f : (Json) -> Json, busy : Bool, act : (@ui.Tester) -> Unit) -> Int {
  let calls : Array[String] = []
  let t = station_archiving_tester(tree, 2, f=@signals.signal(f), busy=@signals.signal(busy), calls~)
  act(t)
  t.run_for(@ui.move_most_ms)
  calls.filter(fn(n) { n == "archiving.save" }).length()
}

///|
test "一台 station 的归档 made once: chosen as the old view's: a way, after how long, Slack's, saved; the one chosen again, a way not allowed, not a manager's, or while a save is on its way, not" {
  let tap = fn(w : String) { fn(t : @ui.Tester) { t.tap_text(w) } }
  let cases : Array[(String, (Json) -> Json, Bool, (@ui.Tester) -> Unit, Int)] = [
    ("another way", fn(a) { a }, false, tap("按模型判断"), 1),
    ("the way it is", fn(a) { a }, false, tap("空闲就归档"), 0),
    ("after another while", fn(a) { a }, false, tap("7 天"), 1),
    ("after the while it is", fn(a) { a }, false, tap("1 天"), 0),
    ("Slack's", fn(a) { a }, false, tap("不归档"), 1),
    (
      "a way not allowed",
      archiving_with([
        (
          "modes",
          [
            { "mode": "off", "label": "不自动归档", "days": 0.0, "reviewed": false, "allowed": true },
            { "mode": "idle", "label": "空闲就归档", "days": 1.0, "reviewed": false, "allowed": true },
            { "mode": "reviewed", "label": "按模型判断", "days": 1.0, "reviewed": true, "allowed": false },
          ],
        ),
      ]),
      false,
      tap("按模型判断"),
      0,
    ),
    ("not a manager", archiving_with([("canEdit", Json::boolean(false))]), false, tap("按模型判断"), 0),
    ("a save on its way", fn(a) { a }, true, tap("7 天"), 0),
  ]
  for c in cases {
    let (what, f, busy, act, n) = c
    let old = station_archiving_saves(false, f, busy, act)
    let made = station_archiving_saves(true, f, busy, act)
    assert_eq(old, n, msg="\{what}: the old one saved \{old} times")
    assert_eq(made, old, msg="\{what}: made, saved \{made} times, the old one \{old}")
  }
}

///|
test "一台 station 的归档 made once: as the core says it anew, the same nodes say it: the way and the while chosen, its note" {
  let anew = archiving_with([("mode", Json::string("reviewed")), ("days", Json::number(7.0)), ("modeNote", Json::string("按模型判断，空闲七天以上"))])
  // (the old view's as the core says it then: made first, alone)
  let old_drawn = instances_sorted(station_archiving_tester(false, 2, f=@signals.signal(anew)))
  let f : @signals.Signal[(Json) -> Json] = @signals.signal(fn(a) { a })
  let t = station_archiving_tester(true, 2, f~)
  let ids = fn(w : String) {
    @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == w }).map(fn(d) { (d.id.at, d.id.gen) })
  }
  let before = (ids("7 天"), ids("按模型判断"), ids(@sf.t("web-pages.archiving.slackHint")))
  // (7 天 both an idle while and a Slack one: two nodes, each the same)
  assert_true(before.0.length() == 2 && before.1.length() == 1 && before.2.length() == 1, msg="\{before}")
  f.set(anew)
  // (its thumbs sent to the way and the while said anew, from that moment, on a cover's way, 0 to 1: at rest at the
  // first whole ms past its length, as a Way ends; nothing still moving then)
  t.run_for(@ui.cover_slide_ms.ceil())
  assert_eq(t.moving(), [], msg="at rest once a cover's way is out")
  assert_eq((ids("7 天"), ids("按模型判断"), ids(@sf.t("web-pages.archiving.slackHint"))), before, msg="the same nodes")
  assert_true(t.find("按模型判断，空闲七天以上") is Some(_), msg="its note said anew")
  same_drawn(instances_sorted(t), old_drawn, "said anew, as the old one draws it")
}

///|
test "归档 made once: a station's row pressed opens its own archiving, made once too" {
  let t = memories_tester(true, 2, mode="settings-archiving")
  t.tap_text("Studio")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::StationArchiving("ws1/st1")), msg="on top \{@sfbase.page_kind(app.nav.top())}")
  let own = tree_words_drawn()
  assert_true(own.iter().any(fn(o) { o.contains(@sf.t("web-pages.archiving.mode")) }), msg="not the tree's own: \{own}")
}

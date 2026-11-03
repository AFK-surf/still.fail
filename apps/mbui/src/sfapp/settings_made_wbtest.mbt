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
/// What the window draws, each instance's numbers rounded to a hundredth, in one order whatever order they were drawn in,
/// a shape's band by its pieces (read at once: the Tester's are what the window last drew, whichever Tester that was).
fn instances_sorted(t : @ui.Tester) -> Array[String] {
  // (a shape's band by its pieces, not where they stand among the frame's: drawn_instances_keyed)
  let all = t.drawn_instances_keyed().map(fn(a) {
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
  w? : Double = 390.0,
  words_over_held? : Bool = true,
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
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=2400.0, platform~, words_over_held~)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w~, h=2400.0, platform~, words_over_held~)
  }
  // (the system's size of words as said: what the bones' bars are as high as follows it)
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "记忆 made once, its stations read the first time: its list in its bones, as it breathes, at the system's sizes of words; none of it found or read out" {
  for scale in [1.0, 1.5, 2.0] {
    let t = memories_tester(true, 2, held=true, scale~)
    let t0 = t.time()
    let out = [instances_sorted(t)]
    for dt in [@sf.breath_ms / 4.0, @sf.breath_ms / 2.0] {
      t.frame_at(t0 + dt)
      out.push(instances_sorted(t))
    }
    let words = words_where(t)
    let said = t.words_said().map(fn(w) { w.0 })
    for i, o in out {
      assert_true(o.length() > 0, msg="nothing drawn at \{scale}, step \{i}")
    }
    // (it breathes: not drawn the same at its faintest as at first)
    assert_true(out[0] != out[2], msg="not breathing at \{scale}")
    // (its bones' words neither drawn nor read out)
    assert_true(!words.iter().any(fn(w) { w.contains("字") }), msg="\{words}")
    assert_true(!said.iter().any(fn(w) { w.contains("字") }), msg="read out at \{scale}: \{said}")
  }
}

///|
test "记忆 made once, its stations not read: what failed said over its list in its bones, still, read out, at the system's sizes of words" {
  for scale in [1.0, 1.5, 2.0] {
    let t = memories_tester(true, 2, failed=true, scale~)
    let t0 = t.time()
    let out = [instances_sorted(t)]
    t.frame_at(t0 + @sf.breath_ms / 2.0)
    out.push(instances_sorted(t))
    let said = t.words_said().map(fn(w) { w.0 })
    assert_true(said.contains("网络连接失败"), msg="\{said}")
    assert_true(t.find("网络连接失败") is Some(_))
    assert_true(out[0].length() > 0, msg="nothing drawn at \{scale}")
    // (still: what failed stops its breath, whole at its faintest's moment as at first)
    same_drawn(out[1], out[0], "still at \{scale}")
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
test "归档 made once: its choice, notes and stations drawn, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let made = memories_tester(true, platform, scale~, mode="settings-archiving")
    assert_true(app.nav.top() == Setting(@settings.Route::Archiving))
    assert_true(instances_sorted(made).length() > 0, msg="\{case}")
    for w in ["Studio", @sf.t("web-pages.appearance.archive.title"), @sf.t("web-pages.archiving.auto.title")] {
      assert_true(made.find(w) is Some(_), msg="\{w} at \{case}")
    }
  }
}

///|
test "归档 made once, its stations read the first time: their rows in their bones, as they breathe; none of them read out" {
  for scale in [1.0, 2.0] {
    let t = memories_tester(true, 2, held=true, scale~, mode="settings-archiving")
    let t0 = t.time()
    let first = instances_sorted(t)
    t.frame_at(t0 + @sf.breath_ms / 2.0)
    let faintest = instances_sorted(t)
    assert_true(first.length() > 0, msg="nothing drawn at \{scale}")
    // (they breathe: not drawn the same at their faintest as at first)
    assert_true(first != faintest, msg="not breathing at \{scale}")
    // (their made-up words neither drawn nor read out)
    let said = t.words_said().map(fn(w) { w.0 })
    assert_true(!words_where(t).iter().any(fn(w) { w.contains("字") }), msg="its bones drawn at \{scale}")
    assert_true(!said.iter().any(fn(w) { w.contains("字") }), msg="its bones read out at \{scale}: \{said}")
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
test "一台 station 的归档 made once, with a finger and with keyboard and mouse, at the system's larger words; its managers' alone, off, and not online: what each says" {
  let cases : Array[(String, Int, Double, (Json) -> Json, Array[String], Array[String])] = [
    ("as it is", 2, 1.0, fn(a) { a }, ["按模型判断", "7 天", "不归档"], []),
    ("as it is", 0, 1.0, fn(a) { a }, ["按模型判断", "7 天", "不归档"], []),
    ("as it is", 2, 2.0, fn(a) { a }, ["按模型判断", "7 天", "不归档"], []),
    ("not a manager", 2, 1.0, archiving_with([("canEdit", Json::boolean(false))]), [@sf.t("web-pages.archiving.adminOnly")], []),
    ("off", 2, 1.0, archiving_with([("mode", Json::string("off"))]), ["不归档"], [@sf.t("web-pages.archiving.idle")]),
    ("too old to say", 2, 1.0, fn(_) { Json::null() }, [@sf.t("web-pages.archiving.upgrade")], ["按模型判断"]),
  ]
  for c in cases {
    let (what, platform, scale, f, shown, none) = c
    let made = station_archiving_tester(true, platform, scale~, f=@signals.signal(f))
    assert_true(app.nav.top() == Setting(@settings.Route::StationArchiving("ws1/st1")), msg="\{what}")
    for w in shown {
      assert_true(made.find(w) is Some(_), msg="\{what}: \{w} at \{platform} \{scale}")
    }
    for w in none {
      assert_true(made.find(w) is None, msg="\{what}: no \{w} at \{platform} \{scale}")
    }
  }
}

///|
/// How many saves of the station's archiving were asked for, in a page made once or an old one, after `act` (taps by
/// words), as its archiving is (`f`) and a save of it on its way or not (`busy`).
fn station_archiving_saves(f : (Json) -> Json, busy : Bool, act : (@ui.Tester) -> Unit) -> Int {
  let calls : Array[String] = []
  let t = station_archiving_tester(true, 2, f=@signals.signal(f), busy=@signals.signal(busy), calls~)
  act(t)
  t.run_for(@ui.move_most_ms)
  calls.filter(fn(n) { n == "archiving.save" }).length()
}

///|
test "一台 station 的归档 made once: chosen: a way, after how long, Slack's, saved; the one chosen again, a way not allowed, not a manager's, or while a save is on its way, not" {
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
    assert_eq(station_archiving_saves(f, busy, act), n, msg="\{what}")
  }
}

///|
test "一台 station 的归档 made once: as the core says it anew, the same nodes say it: the way and the while chosen, its note" {
  let anew = archiving_with([("mode", Json::string("reviewed")), ("days", Json::number(7.0)), ("modeNote", Json::string("按模型判断，空闲七天以上"))])
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

///|
test "自动决定 made once, with a finger and with keyboard and mouse, at the system's larger words; its row opens the decision's page" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let made = memories_tester(true, platform, scale~, mode="settings-decisions-settings")
    assert_true(app.nav.top() == Setting(@settings.Route::AutoDecisions))
    // (narrow: its row's note short)
    assert_true(made.find(@sf.t("web-pages.automaticDecisions.completionShort")) is Some(_), msg="\{case}")
  }
  let t = memories_tester(true, 2, mode="settings-decisions-settings")
  let own = tree_words_drawn()
  assert_true(own.iter().any(fn(o) { o.contains(@sf.t("web-pages.automaticDecisions.completion")) }), msg="not the tree's own: \{own}")
  t.tap_text(@sf.t("web-pages.automaticDecisions.completion"))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::AutoCompletion), msg="on top \{@sfbase.page_kind(app.nav.top())}")
}

///|
test "用量 made once: its figures, its days, its chats and its stations the tree's own, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let made = memories_tester(true, platform, scale~, mode="settings-usage")
    assert_true(app.nav.top() == Setting(@settings.Route::Usage))
    assert_true(instances_sorted(made).length() > 0)
    let own = tree_words_drawn()
    for w in ["用量", "$118", "比前 7 天", "10/4", "最花钱的对话", "整理发布清单", "各设备的工作量", "MBA"] {
      assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="\{w} not the tree's own at \{case}: \{own}")
    }
  }
}

///|
/// 用量's 价目表 reached by its link (查看价目表 →), made once (`tree`), at `platform`'s hand and the system's size of
/// words `scale`; its usage as `state` says once there (prices_said).
fn prices_tester(
  tree : Bool,
  platform : Int,
  scale : Double,
  state? : @signals.Signal[String] = @signals.signal(""),
) -> @ui.Tester {
  let t = memories_tester(tree, platform, scale~, mode="settings-usage", wrap=fn(base) { prices_said(base, state) })
  t.tap_text("查看价目表 →")
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// `base` with its usage as `state` says, as it changes: "" as it is; "held" not read yet; "failed" failing to be read;
/// "reading" read with no prices, the stations' still reading; "failing" so, a station failing; "none" no prices.
fn prices_said(base : Source, state : @signals.Signal[String]) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      if name != "usage" {
        return t
      }
      let read_as = fn(wait : Json?) -> Topic {
        let m : Map[String, Json] = match t.value {
          Some(Object(o)) => o.copy()
          _ => {}
        }
        m["prices"] = Json::array([])
        match wait {
          Some(w) => m["wait"] = w
          None => m.remove("wait")
        }
        { ..t, value: Some(Json::object(m)) }
      }
      match state.get() {
        "held" => ({ value: None, error: None, version: -1 } : Topic)
        "failed" => ({ value: None, error: Some({ "message": Json::string("网络连接失败") }), version: 1 } : Topic)
        "reading" => read_as(Some({ "reading": Json::boolean(true) }))
        "failing" => read_as(Some({ "failing": Json::array([{ "text": Json::string("Studio 离线") }]) }))
        "none" => read_as(None)
        _ => t
      }
    },
  }
}

///|
test "价目表 made once while its usage is not read yet, fails to be read, is read with no prices (its stations still reading, one failing, none): each said, its bones neither drawn nor read out" {
  for case in [(2, 1.0), (0, 1.0)] {
    let (platform, scale) = case
    for state in ["held", "failed", "reading", "failing", "none"] {
      let said = @signals.signal("")
      let t = prices_tester(true, platform, scale, state=said)
      said.set(state)
      t.run_for(@ui.move_most_ms)
      let at = "\{case} \{state}"
      assert_true(app.nav.top() is Setting(@settings.Route::UsagePrices(_)), msg=at)
      assert_true(instances_sorted(t).length() > 0, msg=at)
      let words = words_where(t)
      let out = t.words_said().map(fn(w) { w.0 })
      let has = fn(w : String) { words.iter().any(fn(x) { x.contains(w) }) }
      match state {
        "failed" => assert_true(has("网络连接失败") && out.iter().any(fn(w) { w.contains("网络连接失败") }), msg=at)
        "failing" => assert_true(has("Studio 离线"), msg="\{at}: \{words}")
        "none" => assert_true(has(@sf.t("web-main.usage.noPrices")), msg="\{at}: \{words}")
        _ => ()
      }
      // (its bones' made-up words neither drawn nor read out)
      assert_true(!words.iter().any(fn(w) { w.contains("字") }), msg="bones drawn at \{at}: \{words}")
      assert_true(!out.iter().any(fn(w) { w.contains("字") }), msg="bones read out at \{at}: \{out}")
    }
  }
}

///|
test "价目表 made once in a window made narrower and wider as it shows: its cards' words within the window at each width" {
  for case in [(2, 1.0), (0, 1.0)] {
    let (platform, scale) = case
    for w in [300.0, 240.0, 520.0] {
      let made = prices_tester(true, platform, scale)
      made.resize(w, 2400.0)
      made.run_for(@ui.move_most_ms)
      // (its card's name and what its prices are within the window; its table scrolls across within the card)
      let words = made.words().filter(fn(x) { x.5 > 0.5 && (x.0 == "Studio" || x.0.contains("价")) })
      assert_true(words.iter().any(fn(x) { x.0 == "Studio" }), msg="its card at \{w}")
      for x in words {
        assert_true(x.1 >= -0.5 && x.1 + x.3 <= w + 0.5, msg="\{x.0} within \{w} at \{case}: \{x}")
      }
    }
  }
}

///|
test "价目表 made once: its stations' cards and their tables the tree's own, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let made = prices_tester(true, platform, scale)
    assert_true(app.nav.top() is Setting(@settings.Route::UsagePrices(_)), msg="\{case}")
    assert_true(instances_sorted(made).length() > 0)
    let own = tree_words_drawn()
    for w in ["价目表", "Studio"] {
      assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="\{w} not the tree's own at \{case}: \{own}")
    }
  }
}

///|
test "用量 made once in a window 220 wide at words twice as large, as it is reached: its title on its line and 分享 with its days under it at the line's end, each within the window and over none, 分享 opening its card; the year's head and the days' split each a line beside its choice; no words over words on its title's line" {
  let made = memories_tester(true, 2, scale=2.0, mode="settings-usage", w=220.0, words_over_held=false)
  let made_over = made.words_over_frames()
  assert_true(app.nav.top() == Setting(@settings.Route::Usage))
  let words = made.words()
  let at = fn(all : Array[(String, Double, Double, Double, Double, Double)], w : String) {
    match all.search_by(fn(x) { x.0 == w }) {
      Some(i) => Some(all[i])
      None => None
    }
  }
  let title = at(words, "用量").unwrap()
  let share = match made.semantics().search_by(fn(n) { n.role == Button && n.label == @sf.t("web-main.stations.shareCard") }) {
    Some(i) => made.semantics()[i].rect
    None => fail("分享 read out")
  }
  let day = at(words, "7 天").unwrap()
  // (each within the window; 分享 and the days under the title, 分享 before the days, the days' end 16 in)
  for p in [("title", (title.1, title.2, title.3, title.4)), ("分享", share), ("7 天", (day.1, day.2, day.3, day.4))] {
    let (x, y, w, h) = p.1
    assert_true(x >= 0.0 && x + w <= 220.0 + 0.01 && y >= 0.0 && w > 0.0 && h > 0.0, msg="\{p.0} within the window: \{p.1}")
  }
  assert_true(share.1 >= title.2 + title.4 && day.2 >= title.2 + title.4, msg="under the title: \{title} \{share} \{day}")
  assert_true(share.0 + share.2 <= day.1, msg="分享 before the days: \{share} \{day}")
  // (no words over words on its title's line as it comes in)
  let made_end = usage_line_end(words)
  assert_true(made_over.iter().all(fn(m) { m.y >= made_end }), msg="words over words on its title's line: \{made_over}")
  // (the year's head and the days' bars' split, each a line of words beside a choice)
  let bands = fn(all : Array[(String, Double, Double, Double, Double, Double)]) {
    let band = fn(names : Array[String]) {
      let of = all.filter(fn(x) { names.contains(x.0) })
      (
        of.fold(init=1.0e9, fn(m, x) { @cmp.minimum(m, x.2) }) - 4.0,
        of.fold(init=0.0, fn(m, x) { @cmp.maximum(m, x.2 + x.4) }) + 4.0,
      )
    }
    [band(["Token 活跃度", "近 12 个月", "按天", "按周", "累计"]), band(["按人", "按模型"])]
  }
  let made_bands = bands(words)
  let made_drawn = made.drawn_instances()
  // (those two lines: the words beside the choice as wide as its track, 12 apart; the chosen one's words drawn within
  // the track, seen)
  for b in made_bands {
    let track = made_drawn.filter(fn(a) {
      a[5] == 0.0 && a[11] > 0.05 && a[11] < 0.07 && a[1] + a[3] > b.0 && a[1] < b.1
    })
    assert_true(track.length() == 1, msg="the choice's track in \{b}: \{track.length()}")
    let (tx, tw) = (track[0][0], track[0][2])
    // (what is beside it from the card's room's start, where the year's title starts, to 12 before it: as wide as it,
    // each within that)
    let beside = words.filter(fn(x) { x.2 + x.4 > b.0 && x.2 < b.1 && x.1 + x.3 <= tx })
    let start = words.fold(init=1.0e9, fn(m, x) { if x.0 == "Token 活跃度" { @cmp.minimum(m, x.1) } else { m } })
    assert_true(beside.length() > 0 && (tx - 12.0 - start - tw).abs() < 0.5, msg="the line shared alike: from \{start}, \{beside} \{tx}+\{tw}")
    for x in beside {
      assert_true(x.1 + x.3 <= tx - 12.0 + 0.5, msg="\{x.0} beside the track \{tx}+\{tw}")
    }
    let glyphs = made_drawn.filter(fn(a) { a[5] == 1.0 && a[1] + a[3] > b.0 && a[1] < b.1 && a[0] >= tx })
    assert_true(
      glyphs.length() > 0 && glyphs.iter().all(fn(a) { a[0] + a[2] <= tx + tw + 0.5 && a[18] > a[0] }),
      msg="the chosen one's words within the track, seen: \{glyphs.map(fn(a) { (a[0], a[2], a[16], a[18]) })}",
    )
  }
  // (分享: its card; then 30 天: chosen there, or from the pick the chosen one opens)
  // (its card put up and drawn: what the library's presenters show)
  let shown = @sf.last_presented()
  made.tap(share.0 + share.2 / 2.0, share.1 + share.3 / 2.0)
  made.run_for(@ui.move_most_ms)
  let card = @sf.last_presented()
  assert_true(card != shown && @sf.presented_drawn_of(card), msg="分享's card: \{shown} then \{card}")
}

///|
/// Where 用量's title's line ends down (`all`: its words): its title (the first 用量 down) and its days.
fn usage_line_end(all : Array[(String, Double, Double, Double, Double, Double)]) -> Double {
  let first = all.fold(init=1.0e9, fn(m, x) { if x.0 == "用量" { @cmp.minimum(m, x.2) } else { m } })
  all.fold(init=0.0, fn(m, x) {
    if (x.0 == "用量" && x.2 == first) || x.0 == "7 天" || x.0 == "30 天" { @cmp.maximum(m, x.2 + x.4) } else { m }
  })
}

///|
/// 30 天 chosen in 用量 by a finger: where both show, tapped; else the chosen one tapped and 30 天 in the pick it
/// opens.
fn usage_30_days(t : @ui.Tester) -> Unit {
  if !t.words().iter().any(fn(x) { x.0 == "30 天" }) {
    t.tap_text("7 天")
    t.run_for(@ui.move_most_ms)
  }
  t.tap_text("30 天")
  t.run_for(@ui.move_most_ms)
}

///|
test "用量 made once in a window 220 wide at words twice as large: 30 天 chosen by a finger from its days under the title, its total then; no words over words on its title's line as it goes, frame by frame" {
  let made = memories_tester(true, 2, scale=2.0, mode="settings-usage", w=220.0, words_over_held=false)
  let made_end = usage_line_end(made.words())
  let from = made.words_over_frames().length()
  usage_30_days(made)
  assert_true(made.words().iter().any(fn(x) { x.0 == "$486" }), msg="30 天's total")
  let over = made.words_over_frames()[from:].to_array()
  assert_true(over.iter().all(fn(m) { m.y >= made_end }), msg="words over words on its title's line: \{over}")
}
///|
/// 用量 made once (`tree`), a finger's steps on its days' bars (by where its days' names are), then what it says: its
/// words where they are, as words_where has them.
fn usage_days_after(tree : Bool, steps : (@ui.Tester, (String) -> (Double, Double)) -> Unit) -> Array[String] {
  let t = memories_tester(tree, 2, mode="settings-usage")
  // (a day's bar's middle, by its name under it: 6 under the plot's foot, the plot 150 high)
  let at = fn(name : String) {
    match t.words().search_by(fn(w) { w.0 == name }) {
      Some(i) => {
        let w = t.words()[i]
        (w.1 + w.3 / 2.0, w.2 - 7.0 - 40.0)
      }
      None => (-1.0, -1.0)
    }
  }
  steps(t, at)
  t.run_for(@ui.move_most_ms)
  let out = words_where(t)
  // (and back as it was: what is picked kept across pages, usage_pick)
  out
}

///|
/// How long a finger stays down before it is let go or called off, in the steps usage's days are driven by: a press,
/// short of any hold.
let usage_press_ms : Double = 30.0

///|
test "用量 made once: its days chosen by a finger: a day tapped seen alone, tapped again all again; slid across, the one let go on; slid up or down, the list's, none; called off, none" {
  let tap = fn(name : String) {
    fn(t : @ui.Tester, at : (String) -> (Double, Double)) {
      let (x, y) = at(name)
      t.touch(0, x, y)
      t.run_for(usage_press_ms)
      t.touch(2, x, y)
      t.run_for(@ui.move_most_ms)
    }
  }
  let cases : Array[(String, (@ui.Tester, (String) -> (Double, Double)) -> Unit)] = [
    ("tapped", tap("10/3")),
    ("tapped again", fn(t, at) {
      tap("10/3")(t, at)
      tap("10/3")(t, at)
    }),
    ("slid across", fn(t, at) {
      let (x0, y) = at("10/1")
      let (x1, _) = at("10/5")
      t.touch(0, x0, y)
      for k in 1..=8 {
        t.run_for(@ui.input_step_ms)
        t.touch(1, x0 + (x1 - x0) * k.to_double() / 8.0, y)
      }
      t.touch(2, x1, y)
    }),
    ("slid up", fn(t, at) {
      let (x, y) = at("10/3")
      t.touch(0, x, y)
      for k in 1..=8 {
        t.run_for(@ui.input_step_ms)
        t.touch(1, x, y - 10.0 * k.to_double())
      }
      t.touch(2, x, y - 80.0)
    }),
    ("called off", fn(t, at) {
      let (x, y) = at("10/3")
      t.touch(0, x, y)
      t.run_for(usage_press_ms)
      t.touch(3, x, y)
    }),
  ]
  let none = usage_days_after(true, fn(_, _) {  })
  let seen = fn(what : String) {
    match cases.search_by(fn(c) { c.0 == what }) {
      Some(i) => usage_days_after(true, cases[i].1)
      None => []
    }
  }
  // (a day tapped: seen alone, its words other than all of them; the one let go on as the one tapped is)
  let tapped = seen("tapped")
  assert_true(tapped != none, msg="a day tapped: nothing changed")
  same_drawn(usage_days_after(true, tap("10/5")), seen("slid across"), "slid across: the one let go on")
  // (tapped again, called off: all of them, as at first; slid up: the list's (moved, maybe), no day of it picked)
  for what in ["tapped again", "called off"] {
    same_drawn(seen(what), none, what)
  }
  let words_of = fn(all : Array[String]) {
    let out = all.map(fn(w) {
      match w.find(" at ") {
        Some(i) => w.unsafe_substring(start=0, end=i)
        None => w
      }
    })
    out.sort()
    out
  }
  same_drawn(words_of(seen("slid up")), words_of(none), "slid up")
}
///|
/// `base` with the core's `usage` view as `f` makes it of the one it says.
fn usage_as(base : Source, f : (Json) -> Json) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let r = (base.topic)(name, params)
      if name == "usage" {
        { ..r, value: r.value.map(f) }
      } else {
        r
      }
    },
  }
}

///|
/// The usage view with `fields` said anew.
fn usage_with_fields(fields : Array[(String, Json)]) -> (Json) -> Json {
  fn(v) {
    match v {
      Object(m) => {
        let m2 = m.copy()
        for kv in fields {
          m2[kv.0] = kv.1
        }
        Json::object(m2)
      }
      _ => v
    }
  }
}

///|
test "用量 made once, while it is read, failed, nothing spent (still read or not): each drawn and read out, its bones neither (breathing), what failed said, at the system's sizes of words" {
  let cases : Array[(String, (Source) -> Source)] = [
    ("read the first time", fn(s) { @sffixture.held_topics(s, ["usage"]) }),
    ("failed", fn(s) { @sffixture.failed_topics(s, ["usage"], "网络连接失败") }),
    ("nothing spent", fn(s) { usage_as(s, usage_with_fields([("empty", Json::boolean(true))])) }),
    (
      "nothing spent, still read",
      fn(s) { usage_as(s, usage_with_fields([("empty", Json::boolean(true)), ("wait", { "reading": true })])) },
    ),
  ]
  for c in cases {
    let (what, wrap) = c
    for scale in [1.0, 2.0] {
      let at = "\{what} at \{scale}"
      let t = memories_tester(true, 2, scale~, mode="settings-usage", wrap~)
      let t0 = t.time()
      let first = instances_sorted(t)
      t.frame_at(t0 + @sf.breath_ms / 2.0)
      let later = instances_sorted(t)
      assert_true(first.length() > 0 && later.length() > 0, msg=at)
      let words = words_where(t)
      let said = t.words_said().map(fn(w) { w.0 })
      assert_true(!words.iter().any(fn(w) { w.contains("字") }), msg="bones drawn, \{at}: \{words}")
      assert_true(!said.iter().any(fn(w) { w.contains("字") }), msg="bones read out, \{at}: \{said}")
      assert_eq(said.iter().any(fn(w) { w.contains("网络连接失败") }), what == "failed", msg="\{at}: \{said}")
      // (in its bones while read the first time: breathing)
      if what == "read the first time" {
        assert_true(first != later, msg="breathing, \{at}")
      }
    }
  }
}
///|
test "用量 made once: a day's bar activated by a screen reader seen alone, as a finger's tap on it has it; read out so" {
  let t = memories_tester(true, 2, mode="settings-usage")
  let said = t.semantics().filter(fn(s) { s.role == Button && s.label.contains("$") })
  assert_true(said.length() >= 3, msg="the days read out: \{said.length()}")
  let before = words_where(t)
  t.act(Button, Activate, label=said[2].label)
  t.run_for(@ui.move_most_ms)
  let after = words_where(t)
  assert_true(after != before, msg="nothing seen alone")
  // (the same day tapped by a finger: the same seen)
  let (x, y, w, h) = said[2].rect
  let tapped = usage_days_after(true, fn(t2, _) {
    t2.touch(0, x + w / 2.0, y + h / 2.0)
    t2.run_for(usage_press_ms)
    t2.touch(2, x + w / 2.0, y + h / 2.0)
  })
  same_drawn(tapped, after, "as tapped")
}
///|
test "用量 made once: what the pointer rests on said: a day of the year; by week, its week" {
  let t = memories_tester(true, 0, mode="settings-usage")
  // (the year's last week's Monday: by its weekday's name's row, at the grid's end)
  let mon = match t.words().search_by(fn(w) { w.0 == "一" || w.0 == "周一" || w.0 == "Mon" }) {
    Some(i) => t.words()[i]
    None => ("", 0.0, 0.0, 0.0, 0.0, 0.0)
  }
  assert_true(mon.0 != "", msg="the year's Monday row found")
  let before = words_where(t)
  t.move(370.0 - 20.0, mon.2 + mon.4 / 2.0)
  t.run_for(@ui.move_most_ms + @sf.tip_delay_ms)
  let first = words_where(t)
  assert_true(first.length() > before.length(), msg="a tip shown: \{first.length()} words, \{before.length()} before")
  t.tap_text("按周")
  t.leave()
  t.run_for(@ui.move_most_ms + @sf.tip_delay_ms)
  // (by week: a column of the year's last weeks lit, its square on the Monday row where it is drawn)
  let squares = t.drawn_rects().filter(fn(r) {
    r.2 == r.3 && r.2 > 4.0 && r.2 < 20.0 && (r.1 + r.3 / 2.0 - (mon.2 + mon.4 / 2.0)).abs() < r.3
  })
  assert_true(squares.length() > 0, msg="the last weeks' columns lit")
  let cell = squares[squares.length() - 1]
  t.move(cell.0 + cell.2 / 2.0, cell.1 + cell.3 / 2.0)
  t.run_for(@ui.move_most_ms + @sf.tip_delay_ms)
  let week = words_where(t)
  assert_true(week.iter().any(fn(w) { w.contains("起一周") }), msg="its week said: \{week}")
}
///|
test "一台 station 的记忆 made once: its global memory's parts, its project's, its other skills and its own folded, the tree's own, with a finger and with keyboard and mouse, at the system's larger words" {
  for case in [(2, 1.0), (0, 1.0), (2, 1.5), (2, 2.0)] {
    let (platform, scale) = case
    let made = memories_tester(true, platform, scale~, mode="settings-memory")
    assert_true(app.nav.top() == Setting(@settings.Route::Memory("ws1/st1")), msg="on top \{@sfbase.page_kind(app.nav.top())}")
    assert_true(instances_sorted(made).length() > 0)
    let own = tree_words_drawn()
    for w in [@sf.t("web-main.memory.global"), "习惯", "发布流程", "周报", "pdf、xlsx"] {
      assert_true(own.iter().any(fn(o) { o.contains(w) }), msg="\{w} not the tree's own at \{case}: \{own}")
    }
  }
}

///|
test "一台 station 的记忆 made once, its own skills' row pressed: folded open, read out open; back and in again, still open; pressed again, shut" {
  for platform in [2, 0] {
    let t = memories_tester(true, platform, mode="settings-memory")
    t.tap_text(@sf.t("web-main.memory.builtin"))
    // (its press's ripple gone)
    t.run_for(@motion.ripple_tap_ms)
    // (the pointer gone from the window: nothing lit by it, open, nor as the pages go and come; a page come back to
    // under a still pointer: still_pointer_push_wbtest)
    t.leave()
    t.run_for(@ui.move_most_ms)
    let open = (instances_sorted(t), words_where(t))
    let said = t.semantics().filter(fn(n) { n.label == @sf.t("web-main.memory.builtin") }).map(fn(n) { n.expanded })
    // (back to 记忆, and in again)
    app.nav.pop() |> ignore
    t.run_for(@ui.move_most_ms)
    app.nav.push(Setting(@settings.Route::Memory("ws1/st1")))
    t.run_for(@ui.move_most_ms)
    let again = instances_sorted(t)
    t.tap_text(@sf.t("web-main.memory.builtin"))
    t.run_for(@motion.ripple_tap_ms)
    let shut = words_where(t)
    assert_true(said == [Some(true)], msg="read out open: \{said}")
    same_drawn(again, open.0, "in again as it was left at \{platform}")
    assert_true(open.1.iter().any(fn(w) { w.has_prefix("xlsx at") }) && !shut.iter().any(fn(w) { w.has_prefix("xlsx at") }), msg="its rows")
  }
}

///|
test "一台 station 的记忆 made once, read the first time or failing to be: in its bones, what could not be read said over them" {
  for failed in [false, true] {
    let wrap = fn(base : Source) {
      if failed {
        @sffixture.failed_topics(base, ["memory"], "网络连接失败")
      } else {
        @sffixture.held_topics(base, ["memory"])
      }
    }
    let made = memories_tester(true, 2, mode="settings-memory", wrap~)
    assert_true(instances_sorted(made).length() > 0, msg="nothing drawn, failed \{failed}")
    let said = made.words_said().map(fn(w) { w.0 })
    // (its bones' made-up words neither drawn nor read out; what failed said, and read out)
    let words = words_where(made)
    assert_true(!words.iter().any(fn(w) { w.contains("字") }), msg="its bones drawn, failed \{failed}: \{words}")
    assert_true(!said.iter().any(fn(w) { w.contains("字") }), msg="its bones read out, failed \{failed}: \{said}")
    assert_eq(said.iter().any(fn(w) { w.contains("网络连接失败") }), failed, msg="\{said}")
  }
}

///|
test "一台 station 的记忆 made once: a part of its global memory pressed opens it, a skill its own; 记忆's station row opens this page made once" {
  let t = memories_tester(true, 2, mode="settings-memory")
  // (the part's page reads its words as Markdown: the core said to read them as they are)
  @sf.markdown_read.val = Some(fn(_, done) { done(None) })
  t.tap_text("习惯")
  t.run_for(@ui.move_most_ms)
  let part = app.nav.top()
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  t.tap_text("发布流程")
  t.run_for(@ui.move_most_ms)
  let skill = app.nav.top()
  @sf.markdown_read.val = None
  assert_true(
    part == Setting(@settings.Route::MemoryDoc("ws1/st1", "", 1)) && skill == Setting(@settings.Route::MemoryDoc("ws1/st1", "发布流程", 0)),
    msg="\{@sfbase.page_kind(part)} \{@sfbase.page_kind(skill)}",
  )
  let list = memories_tester(true, 2)
  list.tap_text("Studio")
  list.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Memory("ws1/st1")), msg="on top \{@sfbase.page_kind(app.nav.top())}")
  let own = tree_words_drawn()
  assert_true(own.iter().any(fn(o) { o.contains("习惯") }), msg="not the tree's own: \{own}")
}

///|
test "一台 station 的记忆 made once, a skill shared and no longer and again: its tag said, gone with no room left for it, said again, the same row all along" {
  let t = memories_tester(true, 2, mode="settings-memory")
  let shared = @sf.t("web-main.memory.share.shared")
  let row = fn() { @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == "发布流程" }).map(fn(d) { (d.id.at, d.id.gen) }) }
  let tagged = fn() { tree_words_drawn().iter().any(fn(o) { o == shared }) }
  let at = fn() { t.words().filter(fn(w) { w.0 == "发布流程" }).map(fn(w) { (w.1, w.3) }) }
  let first = (row(), tagged(), at())
  @settings.fixture_call("skill.share", { "name": Json::string("发布流程"), "on": Json::boolean(false) }) |> ignore
  t.run_for(@ui.move_most_ms)
  let off = (row(), tagged(), at())
  @settings.fixture_call("skill.share", { "name": Json::string("发布流程"), "on": Json::boolean(true) }) |> ignore
  t.run_for(@ui.move_most_ms)
  let on = (row(), tagged(), at())
  assert_true(first.0.length() == 1 && first.0 == off.0 && off.0 == on.0, msg="the same row: \{first.0} \{off.0} \{on.0}")
  assert_eq((first.1, off.1, on.1), (true, false, true))
  assert_eq(on.2, first.2)
}

///|
/// The core's topic `name` as it is read, its params' `key` each time (the source `base` otherwise as it is).
fn topic_asked(base : Source, name : String, key : String, asked : Array[String]) -> Source {
  {
    ..base,
    topic: fn(n, params) {
      if n == name {
        asked.push(
          match params.get(key) {
            Some(String(s)) => s
            Some(Number(d, ..)) => d.to_int().to_string()
            _ => ""
          },
        )
      }
      (base.topic)(n, params)
    },
  }
}

///|
test "a station's memory made once become another's in its place: its title that station's, its memory read of it, its rows there" {
  let asked : Array[String] = []
  let t = memories_tester(true, 2, mode="settings-memory", wrap=fn(b) { topic_asked(b, "memory", "station", asked) })
  let first = (asked.last(), tree_words_drawn().contains("Studio"))
  app.nav.become(Setting(@settings.Route::Memory("ws1/st2")))
  t.run_for(@ui.move_most_ms)
  let own = tree_words_drawn()
  assert_eq(
    (first, asked.last(), own.contains("MBA"), own.iter().any(fn(o) { o.contains("发布流程") })),
    ((Some("ws1/st1"), true), Some("ws1/st2"), true, true),
    msg="\{own}",
  )
}

///|
test "价目表 made once become another's of other days in its place: its usage read for those days, its tables there" {
  let asked : Array[String] = []
  let t = memories_tester(true, 2, mode="settings-usage", wrap=fn(b) { topic_asked(b, "usage", "days", asked) })
  t.tap_text("查看价目表 →")
  t.run_for(@ui.move_most_ms)
  guard app.nav.top() is Setting(@settings.Route::UsagePrices(days)) else { fail("not on 价目表") }
  let other = if days == 7 { 30 } else { 7 }
  app.nav.become(Setting(@settings.Route::UsagePrices(other)))
  t.run_for(@ui.move_most_ms)
  let own = tree_words_drawn()
  assert_eq((asked.last(), own.iter().any(fn(o) { o.contains("Opus") })), (Some(other.to_string()), true), msg="\{asked} \{own}")
}

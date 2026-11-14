// The places of the bottom bar on 小屏 as switching between them is (an audit for keeping a place switched away from
// instead of letting it go, 2026-11-12, made to assert as it was kept): what each switch makes and lets go of the
// window's tree, the stack's entry before and after it, and what the client tells the core on the way (the made-up core
// under the app's own client, late_core_wbtest's switch_core: the messages a run's trace keeps), held to what it told
// as every switch made its page anew (the 2026-11-12 baseline, `today_baseline`); then, of each place made as nodes,
// that it is as it was left once it is come back to (its scroll, its choice: the owner, 2026-11-12, 「三样都记得」).

///|
/// A second of frames after a switch or a step: every way it sets off (a place's way in, the bar's springs, a page's
/// slide, a menu's) over by then.
let kept_switch_over_ms : Double = 1000.0

///|
/// What a finger's drag up or down a list glides for after it is let go, over by then (two seconds; three for a long one).
let kept_glide_over_ms : Double = 2000.0

///|
let kept_glide_long_ms : Double = 3000.0

///|
/// A few frames: what a change told, or a Tab, takes to be drawn.
let kept_few_frames_ms : Double = 100.0

///|
/// Between two Tabs, a frame or so drawn after each.
let kept_tab_gap_ms : Double = 50.0

///|
/// The bar the switches are made on: the three places made as nodes (对话, 连接, 用量) and one old view's (额度).
let today_bar : Array[String] = ["chats", "connects", "usage", "profiles"]

///|
/// The bar's places' middles in the phone's window (390 by 844), and its middle's height.
fn today_bar_at() -> (Array[Double], Double) {
  (bar_centres(390.0 - 44.0, 1.0, 4).map(fn(x) { x + 22.0 }), 844.0 - 22.0 - 28.0)
}

///|
/// What of `heard` from `from` on the client sent and was told, read: each subscription (`sub #id topic {params}`), each
/// letting go (`unsub #id topic {params}`), each call (`call name`) in order; then what was told of each subscription
/// (`told #id topic ×n`), the ids' topics from all of `heard`.
fn today_wire(heard : Array[String], from : Int) -> Array[String] {
  let names : Map[Int, String] = Map([])
  let out : Array[String] = []
  let told : Map[Int, Int] = Map([])
  for i, h in heard {
    let (dir, text) = if h.has_prefix("out ") {
      ("out", h.exact_view(start=4).to_owned())
    } else if h.has_prefix("in ") {
      ("in", h.exact_view(start=3).to_owned())
    } else {
      continue
    }
    let j = @json.parse(text) catch { _ => continue }
    guard j is Object(m) else { continue }
    let id = match m.get("id") {
      Some(Number(n, ..)) => n.to_int()
      _ => -1
    }
    if dir == "out" {
      match (m.get("subscribe"), m.get("unsubscribe"), m.get("call")) {
        (Some(Object(t)), _, _) => {
          let rest : Map[String, Json] = Map([])
          for k, v in t {
            if k != "topic" {
              rest[k] = v
            }
          }
          let topic = match t.get("topic") {
            Some(String(x)) => x
            _ => "?"
          }
          names[id] = topic + " " + Json::object(rest).stringify()
          if i >= from {
            out.push("sub #\{id} \{names[id]}")
          }
        }
        (_, Some(True), _) => if i >= from { out.push("unsub #\{id} \{names.get(id).unwrap_or("?")}") }
        (_, _, Some(String(c))) => if i >= from { out.push("call \{c}") }
        _ => if i >= from { out.push("out \{text}") }
      }
    } else if i >= from && names.contains(id) {
      told[id] = told.get(id).unwrap_or(0) + 1
    }
  }
  for id, n in told {
    out.push("told #\{id} \{names.get(id).unwrap_or("?")} ×\{n}")
  }
  out
}

///|
/// The stack's root entry now: its page, its serial and its time on top.
fn today_entry() -> String {
  let (serial, stint) = app.nav.top_stay()
  "\{Repr(place_of(app.nav.top()))} serial \{serial} stint \{stint}"
}

///|
/// `act` done, then frames for a second: what all of them made, let go, laid out and measured, and the most of one;
/// and all made and let go.
fn today_work(t : @ui.Tester, act : () -> Unit) -> (String, Int, Int) {
  t.tree_frames_from_now()
  act()
  t.run_for(kept_switch_over_ms)
  let all = t.tree_frames()
  let mut made = 0
  let mut let_go = 0
  let mut laid = 0
  let mut peak : @ui.TreeFrame? = None
  for f in all {
    made += f.made
    let_go += f.let_go
    laid += f.laid
    match peak {
      Some(p) if p.made + p.laid >= f.made + f.laid => ()
      _ => peak = Some(f)
    }
  }
  let p = match peak {
    Some(p) => "made \{p.made} let_go \{p.let_go} laid \{p.laid} measured \{p.measured}"
    None => "none"
  }
  ("frames \{all.length()}: made \{made} let_go \{let_go} laid \{laid}; the most of one: \{p}", made, let_go)
}

///|
/// Line `l` of today_wire's without the id it names (`#12 `).
fn today_unid(l : String) -> String {
  let out = StringBuilder()
  let mut skip = false
  for c in l {
    if c == '#' {
      skip = true
    } else if skip {
      if c == ' ' {
        skip = false
      }
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// What the client told the core of `heard` from `from` (today_wire's subscriptions, lettings go and calls), each without
/// its id, in order.
fn today_told(heard : Array[String], from : Int) -> Array[String] {
  today_wire(heard, from).filter(fn(l) { !l.has_prefix("told ") }).map(today_unid)
}

///|
/// The topics subscribed to after all of `heard` (each `topic {params}`, its id's subscription not let go of).
fn today_live(heard : Array[String]) -> Array[String] {
  let live : Map[String, Bool] = Map([])
  for l in today_wire(heard, 0) {
    let u = today_unid(l)
    if u.has_prefix("sub ") {
      live[u.exact_view(start=4).to_owned()] = true
    } else if u.has_prefix("unsub ") {
      live[u.exact_view(start=6).to_owned()] = false
    }
  }
  live.iter().filter(fn(e) { e.1 }).map(fn(e) { e.0 }).collect()
}

///|
/// What the client told the core at each switch of the finger's walk while every switch made its page anew (2026-11-12,
/// before places were kept), and what keeping them told otherwise: each message the same, but where the page left and
/// the one come to read the same topic, which is then held through the switch (`doing`, read by 连接 and Home: let go of
/// and asked again, as two messages, while the one was let go before the other was made). Their order within a switch
/// is no part of it: held as a set.
let today_baseline : Array[(String, Array[String], Array[String])] = [
  (
    "chats→connects",
    [
      "unsub doing {}", "unsub changelog {\"news\":true}", "unsub driveTransfers {\"workspace\":\"ws1\"}", "unsub longJobs {\"scope\":\"ws1\"}",
      "sub doing {}", "unsub lock {\"workspace\":\"ws1\"}",
    ],
    [],
  ),
  (
    "connects→chats",
    [
      "sub lock {\"workspace\":\"ws1\"}", "sub longJobs {\"scope\":\"ws1\"}", "sub changelog {\"news\":true}", "unsub doing {}", "sub doing {}",
      "sub driveTransfers {\"workspace\":\"ws1\"}",
    ],
    ["unsub doing {}", "sub doing {}"],
  ),
  (
    "chats→usage",
    [
      "sub usage {\"scope\":\"ws1\",\"days\":7}", "unsub doing {}", "unsub changelog {\"news\":true}", "unsub driveTransfers {\"workspace\":\"ws1\"}",
      "unsub longJobs {\"scope\":\"ws1\"}", "unsub lock {\"workspace\":\"ws1\"}",
    ],
    [],
  ),
  ("usage→connects", ["unsub usage {\"scope\":\"ws1\",\"days\":7}", "sub doing {}"], []),
  ("connects→usage", ["sub usage {\"scope\":\"ws1\",\"days\":7}", "unsub doing {}"], []),
  (
    "usage→chats",
    [
      "sub lock {\"workspace\":\"ws1\"}", "sub longJobs {\"scope\":\"ws1\"}", "sub changelog {\"news\":true}", "unsub usage {\"scope\":\"ws1\",\"days\":7}",
      "sub doing {}", "sub driveTransfers {\"workspace\":\"ws1\"}",
    ],
    [],
  ),
  (
    "chats→profiles",
    [
      "unsub doing {}", "unsub changelog {\"news\":true}", "unsub driveTransfers {\"workspace\":\"ws1\"}", "unsub longJobs {\"scope\":\"ws1\"}",
      "unsub lock {\"workspace\":\"ws1\"}",
    ],
    [],
  ),
  ("profiles→connects", ["sub doing {}"], []),
  ("connects→profiles", ["unsub doing {}"], []),
  ("profiles→usage", ["sub usage {\"scope\":\"ws1\",\"days\":7}"], []),
]

///|
/// `told` held to the baseline of switch `name` (today_baseline): the same messages, but those it says keeping drops,
/// whatever their order.
fn today_held(name : String, told : Array[String]) -> Unit raise {
  guard today_baseline.iter().find_first(fn(b) { b.0 == name }) is Some((_, was, dropped)) else {
    @halt.saying("bar-today: no baseline for \{name}")
  }
  let want = was.copy()
  for d in dropped {
    match want.search(d) {
      Some(i) => want.remove(i) |> ignore
      None => ()
    }
  }
  let a = told.copy()
  let b = want.copy()
  a.sort()
  b.sort()
  assert_eq(a, b, msg="\{name}: what the client told the core")
}

///|
/// The topics of the page each place opens on that it alone holds there (what Home, 连接 and 用量 asked as they were
/// first made, less what the bar holds ahead for every place: `chats`, `connects`): none of them held while it rests.
let today_own : Array[(String, Array[String])] = [
  (
    "chats",
    [
      "doing {}", "changelog {\"news\":true}", "driveTransfers {\"workspace\":\"ws1\"}", "longJobs {\"scope\":\"ws1\"}",
      "lock {\"workspace\":\"ws1\"}",
    ],
  ),
  ("connects", ["doing {}"]),
  ("usage", ["usage {\"scope\":\"ws1\",\"days\":7}"]),
  ("profiles", []),
]

///|
test "bar places today: each switch's nodes made and let go, the stack's entry, and what the client tells the core, by a finger on the bar" {
  let heard : Array[String] = []
  let (t, _) = switch_on(fn(_) { 0.0 }, heard, 390.0, 844.0, 2, 60.0)
  bars_picked.set(Some(([today_bar], 0)))
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  let (xs, y) = today_bar_at()
  println("bar-today: at rest on \{today_entry()}")
  let at_rest_heard = heard.length()
  for line in today_wire(heard, 0) {
    println("bar-today:   (as it opened) \{line}")
  }
  ignore(at_rest_heard)
  let walk = ["connects", "chats", "usage", "connects", "usage", "chats", "profiles", "connects", "profiles", "usage", "chats"]
  // (what each switch made and let go of the tree: the first visit of a place made as nodes makes it, a place come back
  // to makes and lets go of nothing but a node of Home's (made while it was away, let go as it is back), an old view's
  // place its few)
  let works = [(124, 0), (0, 1), (649, 262), (0, 0), (0, 0), (0, 1), (7, 0), (0, 6), (6, 0), (0, 6), (0, 1)]
  let mut from_place = "chats"
  for k, place in walk {
    let i = today_bar.search(place).unwrap()
    let mark = heard.length()
    let before = today_entry()
    let (work, made, let_go) = today_work(t, fn() { t.tap(xs[i], y) })
    to_bar_rest(t)
    println("bar-today: \{from_place}→\{place}: \{work}")
    println("bar-today:   entry \{before} → \{today_entry()}")
    for line in today_wire(heard, mark) {
      println("bar-today:   \{line}")
    }
    let name = "\{from_place}→\{place}"
    assert_eq((made, let_go), works[k], msg=name)
    today_held(name, today_told(heard, mark))
    // (what the place left alone held let go of, none of it told while it rests)
    let live = today_live(heard)
    match today_own.iter().find_first(fn(o) { o.0 == from_place }) {
      Some((_, own)) =>
        for topic in own {
          let shown_holds = match today_own.iter().find_first(fn(o) { o.0 == place }) {
            Some((_, now)) => now.contains(topic)
            None => false
          }
          if !shown_holds {
            assert_false(live.contains(topic), msg="\{name}: \{topic} held as \{from_place} rests")
          }
        }
      None => ()
    }
    from_place = place
  }
}

///|
test "bar places today: the same switches with no finger (go_place at an event, as a notification or the shell does), what the client tells the core" {
  let heard : Array[String] = []
  let (t, _) = switch_on(fn(_) { 0.0 }, heard, 390.0, 844.0, 2, 60.0)
  bars_picked.set(Some(([today_bar], 0)))
  t.run_for(kept_switch_over_ms)
  let walk = ["connects", "chats", "usage", "connects", "chats"]
  let mut from_place = "chats"
  for place in walk {
    let mark = heard.length()
    let (work, _, _) = today_work(t, fn() {
      @ui.view_tree().unwrap().event(t.time(), fn() { go_place(t.time(), place, [today_bar], 0) })
    })
    println("bar-today nofinger: \{from_place}→\{place}: \{work}")
    for line in today_wire(heard, mark) {
      println("bar-today nofinger:   \{line}")
    }
    today_held("\{from_place}→\{place}", today_told(heard, mark))
    from_place = place
  }
}

///|
/// What of the page shows now that a return may keep or lose: the first word drawn between 300 and 700 down and where
/// (what it is scrolled to), what is chosen (semantics selected or checked), what has the keyboard's focus, whether a
/// presenter is up, and the words typed (`typed`) where they are drawn.
fn today_looks(t : @ui.Tester, typed : String) -> String {
  let mid = t.words().iter().find_first(fn(w) { w.1 >= 0.0 && w.1 < 390.0 && w.2 >= 300.0 && w.2 <= 700.0 && w.0.length() > 1 })
  let chosen = t
    .semantics()
    .filter(fn(s) { !s.hidden && (s.selected == Some(true) || s.check is Some(@view.Check::On)) })
    .map(fn(s) { s.label })
  let focus = match t.focused() {
    Some(s) => s.label + " value=" + s.value
    None => "none"
  }
  let typed_at = if typed == "" {
    "-"
  } else {
    Repr(t.words().filter(fn(w) { w.0.contains(typed) }).map(fn(w) { w.2 })).to_string()
  }
  "mid \{Repr(mid.map(fn(w) { (w.0, w.2) }))} chosen \{Repr(chosen)} focus \{focus} presenting \{@sf.presenting()} typed_at \{typed_at}"
}

///|
test "bar places today: each place made as nodes left for another and come back to is as it was left: its scroll and its choice" {
  for place in ["chats", "connects", "usage"] {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    bars_picked.set(Some(([today_bar], 0)))
    t.run_for(kept_switch_over_ms)
    to_bar_rest(t)
    let (xs, y) = today_bar_at()
    let i = today_bar.search(place).unwrap()
    if place != "chats" {
      t.tap(xs[i], y)
      t.run_for(kept_switch_over_ms)
      to_bar_rest(t)
    }
    let w = @signals.untracked(fn() { workspace_in_view(src).0.unwrap() })
    // (the page's own choice as it is now: the chats' filter, 连接's 我的, and what is chosen as a screen reader has it)
    let choice = fn() { "filter \{filter_of(src, w.id)} connects_mine \{@settings.connects_mine.val}" }
    println("bar-keep \{place}: opened: \{today_looks(t, "")} \{choice()}")
    // a choice of the page's own: the chats' filter 我参与的; 用量's days 30; 连接's 我的 (their words pressed)
    match place {
      "chats" => @ui.view_tree().unwrap().event(t.time(), fn() { home_filter_go(src, w, "mine") })
      "usage" => t.tap_text(@sf.t("web-main.usage.days", args=[("n", "30")]))
      _ =>
        match t.query(Button, label=connects_filter_label()) {
          Some(f) => {
            t.tap(f.rect.0 + f.rect.2 / 2.0, f.rect.1 + f.rect.3 / 2.0)
            t.run_for(kept_switch_over_ms)
            match t.words().iter().find_first(fn(w) { w.0 == @sf.t("web-main.filter.connects.mine") }) {
              Some(m) => t.tap(m.1 + 4.0, m.2 + 4.0)
              None => println("bar-keep connects: no 我的 in the menu")
            }
          }
          None => println("bar-keep connects: no filter shown")
        }
    }
    t.run_for(kept_switch_over_ms)
    if place == "connects" {
      assert_true(@settings.connects_mine.val, msg="连接's 我的 chosen")
    }
    // scrolled: a finger up the page
    t.drag(195.0, 650.0, 195.0, 350.0, steps=20)
    t.run_for(kept_glide_over_ms)
    // the keyboard's focus put in the page (Tab twice)
    t.tab()
    t.tab()
    t.run_for(kept_few_frames_ms)
    let left = today_looks(t, "")
    // (a word of the page in view as it was left, by its words: where it is drawn once come back is how far it is scrolled)
    let marked = t.words().iter().find_first(fn(w) { w.1 >= 0.0 && w.1 < 390.0 && w.2 >= 300.0 && w.2 <= 700.0 && w.0.length() > 1 })
    let mark_y = fn() {
      match marked {
        Some(m) => Repr(t.words().filter(fn(w) { w.0 == m.0 && w.1 >= 0.0 && w.1 < 390.0 }).map(fn(w) { w.2 })).to_string()
        None => "-"
      }
    }
    let left_y = mark_y()
    println("bar-keep \{place}: scroll mark \{Repr(marked.map(fn(m) { m.0 }))} at \{left_y} as left")
    println("bar-keep \{place}: as left: \{left} \{choice()} entry \{today_entry()}")
    // to 额度 (an old view's place) and back, by a finger on the bar
    t.tap(xs[3], y)
    t.run_for(kept_switch_over_ms)
    to_bar_rest(t)
    t.tap(xs[i], y)
    t.run_for(kept_switch_over_ms)
    to_bar_rest(t)
    let back = today_looks(t, "")
    println("bar-keep \{place}: scroll mark at \{mark_y()} come back")
    println("bar-keep \{place}: come back: \{back} \{choice()} entry \{today_entry()}")
    println("bar-keep \{place}: same as left: \{left == back}")
    // (each as it was left, to the point, the same nodes taken back (made anew Home's list came back 14 points off):
    // Home's list, filter and search, 用量's list and its days, 连接's list and its 我的; the owner, 2026-11-12:
    // 「三样都记得」. Only the keyboard's focus is lost at the switch)
    let what = fn(looks : String) { looks.split(" focus ").to_array()[0].to_owned() }
    assert_eq(mark_y(), left_y, msg="\{place}: its list where it was left")
    assert_eq(what(back), what(left), msg="\{place}: what shows and what is chosen as left")
    match place {
      "chats" => assert_eq(mark_y(), "[318]", msg="Home's list where it was left")
      "usage" => {
        // (scrolled as left: not at its top, where 用量 opens on its activity at 340)
        assert_false(left.has_prefix("mid Some((\"Token 活跃度\", 340))"), msg="用量 scrolled before it was left: \{left}")
        assert_true(back.contains("\"30 天\""), msg="用量's days as chosen: \{back}")
      }
      _ => {
        assert_true(@settings.connects_mine.val, msg="连接's 我的 still on")
        let mine_label = @sf.t("web-main.filter.connects.named", args=[("named", @sf.t("web-main.filter.connects.mine"))])
        assert_true(t.query(Button, label=mine_label) is Some(_), msg="连接's filter shows 我的")
      }
    }
    // a layer opened from the page (a menu), then the place switched with no finger (the menu's scrim over the bar),
    // and back
    @ui.view_tree()
    .unwrap()
    .event(t.time(), fn() { @sfpages.filter_menu(@sf.Beside::At(20.0, 60.0, 34.0, 34.0), filter_of(src, w.id), fn(_) {  }) })
    t.run_for(kept_switch_over_ms)
    println("bar-keep \{place}: a menu up: presenting \{@sf.presenting()}")
    @ui.view_tree().unwrap().event(t.time(), fn() { go_place(t.time(), "profiles", [today_bar], 0) })
    t.run_for(kept_switch_over_ms)
    println("bar-keep \{place}: switched away with it up: presenting \{@sf.presenting()}")
    @ui.view_tree().unwrap().event(t.time(), fn() { go_place(t.time(), place, [today_bar], 0) })
    t.run_for(kept_switch_over_ms)
    println("bar-keep \{place}: come back: \{today_looks(t, "")}")
  }
}

///|
test "bar places today: Home's search field typed into, then the place switched with no finger and come back to" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  bars_picked.set(Some(([today_bar], 0)))
  t.run_for(kept_switch_over_ms)
  // (the field tucked over the rows under the top bar: the list pulled down till it shows)
  t.drag(195.0, 300.0, 195.0, 420.0, steps=20)
  t.run_for(kept_glide_over_ms)
  let field = t.words().iter().find_first(fn(w) { w.0.contains("搜索") && w.2 > 60.0 })
  println("bar-keep search: field words \{Repr(field.map(fn(w) { (w.0, w.1, w.2) }))}")
  match field {
    Some(f) => {
      t.tap(f.1 + 4.0, f.2 + 4.0)
      t.run_for(kept_switch_over_ms)
      t.type_text("abcq")
      t.run_for(kept_switch_over_ms)
      println("bar-keep search: typed: \{today_looks(t, "abcq")} bar away \{@sfpages.search_bar_away()}")
      @ui.view_tree().unwrap().event(t.time(), fn() { go_place(t.time(), "connects", [today_bar], 0) })
      t.run_for(kept_switch_over_ms)
      println("bar-keep search: on 连接: \{today_looks(t, "abcq")} entry \{today_entry()}")
      @ui.view_tree().unwrap().event(t.time(), fn() { go_place(t.time(), "chats", [today_bar], 0) })
      t.run_for(kept_switch_over_ms)
      println("bar-keep search: come back: \{today_looks(t, "abcq")} bar away \{@sfpages.search_bar_away()}")
    }
    None => println("bar-keep search: no field found")
  }
}

///|
/// `act` done, then each frame for `span` ms printed as `tag`: made, let go, laid out, measured, and why it was built.
fn today_frames(t : @ui.Tester, tag : String, act : () -> Unit, span? : Double = 400.0) -> Unit {
  t.tree_frames_from_now()
  let start = t.time()
  act()
  let mut seen = 0
  let take = fn() {
    let all = t.tree_frames()
    for i in seen..<all.length() {
      let f = all[i]
      if f.made + f.let_go + f.laid + f.measured > 0 {
        let why = if i == all.length() - 1 { t.built_why() } else { "(earlier)" }
        println("finger \{tag} +\{(t.time() - start).to_int()}ms #\{i}: made \{f.made} let_go \{f.let_go} laid \{f.laid} measured \{f.measured} why \{why}")
      }
    }
    seen = all.length()
  }
  take()
  while t.time() < start + span {
    t.frame()
    take()
  }
}

///|
test "bar places today: why the page left is laid out in the switch's frame by a finger, not without one" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 60.0)
  bars_picked.set(Some(([today_bar], 0)))
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  let (xs, y) = today_bar_at()
  // (a finger down and up on the tab of the place already shown: no switch)
  today_frames(t, "home on home, down then up", fn() {
    t.press_at(xs[0], y)
    t.run_for(tap_held_ms)
    t.release(xs[0], y)
  })
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  // (a finger down on 连接's tab, then up 30 ms later)
  today_frames(t, "home→connects, down then up", fn() {
    t.press_at(xs[1], y)
    t.run_for(tap_held_ms)
    t.release(xs[1], y)
  })
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  today_frames(t, "connects→home, down then up", fn() {
    t.press_at(xs[0], y)
    t.run_for(tap_held_ms)
    t.release(xs[0], y)
  })
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  // (no finger: the press's asking ahead said first, then the switch, at one event)
  today_frames(t, "home→connects, no finger, pressed first", fn() {
    @ui.view_tree().unwrap().event(t.time(), fn() {
      @sfbase.place_pressed("connects")
      go_place(t.time(), "connects", [today_bar], 0)
    })
  })
  t.run_for(kept_switch_over_ms)
  to_bar_rest(t)
  today_frames(t, "connects→home, no finger, pressed first", fn() {
    @ui.view_tree().unwrap().event(t.time(), fn() {
      @sfbase.place_pressed("chats")
      go_place(t.time(), "chats", [today_bar], 0)
    })
  })
}

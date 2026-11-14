// Home on the workspace of real size, given what the owner's phone reports as hangs there (PostHog `ui_hang`, PLP110,
// builds 8486–8625: frames of 30–55 ms whose window's tree made 750–1050 nodes and laid out 1100–1400, `why` the bar's
// switch or a workspace's; `chats` deltas laying out ~760 for ~60 made), which the sweep of real_size_wbtest.mbt does
// not give: Home is opened there once, and given each change of the core's rig as it opens. Here it is held as the
// sweep holds it (screen_in's `changing`: what the core sends each topic, as a device asks it and applies its messages)
// in the phone's window, and each frame from an event until the tree is still (a span said) is printed: the tree's
// nodes made, let go, laid out, words measured (Tester::tree_frames, a device's FrameDone counts) and why the frame was
// built (Tester::built_why), then the most of them, the peak, as a row of the gate would be written
// (`"<event>": (made, let_go, laid, measured),`). Its frames are a host's, `period` apart (Tester::set_frame_period):
// each test walks them at 60 and at 120 a second itself, whatever MBUI_TEST_FPS says. Motion as a phone has it (not
// reduced, as the sweep's are) unless said; how what moves goes is not judged here (it counts work, as the sweep does).
// A place of the bar switched to and Home switched back to are held (2026-11-12, as places came to be kept): the first
// visit of a place made as nodes makes it, Home come back to makes nothing and lays out only the stack's few (6), what
// it was laid out as kept with it; the rest is measured and printed, a step to rows of the gate.

///|
/// The phone's window of the sweep (real_size_windows' first).
let home_again_window : (String, Double, Double, Int, String) = ("phone", 360.0, 740.0, 2, "")

///|
/// What is taken as the next frame begins, in order: each a message of the core's put (home_again_post).
// kept across runs: emptied by the frame that takes it, each test's posts taken before it ends
let home_again_due : Array[() -> Unit] = []

///|
/// The channel what is put is posted on, taken as the core's messages are (real_size_change_channel's way).
let home_again_channel : String = "home-again"

///|
/// Home opened in the phone's window on the workspace of real size held as a device holds it (screen_in's `changing`),
/// motion reduced (`reduced`, the sweep's) or not, the Tester's checks of a frame drawn again whole (`checks`) or the
/// frames drawn as a host draws them; at rest, its frames from then a host's, `period` apart. Its opening's most frame
/// (made, laid, measured: the gate's `phone home`) printed.
fn home_again_open(
  tag : String,
  period : Double,
  reduced? : Bool = false,
  checks? : Bool = true,
  win? : (String, Double, Double, Int, String) = home_again_window,
) -> (@ui.Tester, @sfrealsize.RealSizeChanging, Source) {
  let c = @sfrealsize.RealSizeChanging::new()
  let (_, w, h, platform, _) = win
  let src : Ref[Source?] = Ref(None)
  let made = fn() {
    match src.val {
      Some(s) => s
      None => {
        reset()
        let s = c.source(@sffixture.fixture("home"))
        open_fixture_over("home", s)
        src.val = Some(s)
        s
      }
    }
  }
  let t = @ui.Tester::new(
    fn(x) { view(x, made()) },
    tree=fn(root) { app_tree(made())(root) },
    w~,
    h~,
    platform~,
    window_corner=test_window_corner(platform),
    corners_held=false,
    words_over_held=false,
    env=[("MBUI_LOCALE", "zh")] + (if reduced { [("MBUI_REDUCE_MOTION", "1")] } else { [] }),
  )
  t.motion_unjudged(true)
  if !checks {
    t.check_looks(false)
  }
  t.run_for(squeeze_opening)
  t.frame()
  let (m, l, ms) = real_size_most()
  println("home-again \{tag} opening's most frame: made \{m} laid \{l} measured \{ms}")
  @ui.on_message_said(home_again_channel, fn(_, _) {
    if home_again_due.length() > 0 {
      (home_again_due.remove(0))()
    }
    true
  })
  t.set_frame_period(period)
  t.run_for(kept_switch_over_ms)
  (t, c, made())
}

///|
/// The peak of the last home_again_measure: made, let go, laid out.
// kept across runs: set by each measure, read right after it by the test that made it
let home_again_peak : Ref[(Int, Int, Int)] = Ref((0, 0, 0))

///|
/// `act` done (an input, a message posted, an event of the tree's), then frames drawn till `span` ms after it: each
/// frame that did anything printed (from the act, made, let go, laid out, measured, why it was built), then the peak
/// (the frame most made and laid out), how many frames after it laid out anything, and whether the app was at rest.
fn home_again_measure(t : @ui.Tester, name : String, act : () -> Unit, span? : Double = 1500.0) -> Unit {
  home_again_peak.val = (0, 0, 0)
  t.tree_frames_from_now()
  let start = t.time()
  act()
  let frames : Array[(Double, @ui.TreeFrame, String)] = []
  let take = fn() {
    let all = t.tree_frames()
    for i in frames.length()..<all.length() {
      frames.push((t.time() - start, all[i], if i == all.length() - 1 { t.built_why() } else { "(an earlier frame of the same step)" }))
    }
  }
  take()
  while t.time() < start + span {
    t.frame()
    take()
  }
  let mut peak = -1
  for i, f in frames {
    let (_, x, _) = f
    if x.made + x.let_go + x.laid + x.measured > 0 || f.2 != "" {
      println("  \{name} +\{f.0.to_int()}ms made \{x.made} let_go \{x.let_go} laid \{x.laid} measured \{x.measured} why \{f.2}")
    }
    if peak < 0 || x.made + x.laid > frames[peak].1.made + frames[peak].1.laid {
      peak = i
    }
  }
  if peak < 0 {
    println("PEAK \{name}: no frame drawn")
    return
  }
  let (at, p, why) = frames[peak]
  home_again_peak.val = (p.made, p.let_go, p.laid)
  let mut after = 0
  for i in (peak + 1)..<frames.length() {
    if frames[i].1.laid > 0 {
      after += 1
    }
  }
  println(
    "PEAK \{name}: made \{p.made} let_go \{p.let_go} laid \{p.laid} measured \{p.measured} at +\{at.to_int()}ms, of \{frames.length()} frames; \{after} after it laid out anything; why \{why}; at rest \{t.at_rest()} \{t.rest_why()}",
  )
  println("  \"\{name}\": (\{p.made}, \{p.let_go}, \{p.laid}, \{p.measured}),")
}

///|
/// A message of the core's for way `at` of `c` posted as the core's are, taken between frames (the sweep's way).
fn home_again_post(t : @ui.Tester, c : @sfrealsize.RealSizeChanging, at : Int, message : Json) -> Unit {
  home_again_due.push(fn() { c.put(at, message) })
  t.post(home_again_channel, "{}")
}

///|
/// The way `name` (real_size_way's) of workspace `scope` among what `c` holds.
fn home_again_way(c : @sfrealsize.RealSizeChanging, name : String, scope : String) -> Int {
  for i, way in c.ways() {
    if @sfrealsize.real_size_way(way.0, way.1) == name && way.1.get("scope") == Some(Json::string(scope)) {
      return i
    }
  }
  let all = c.ways().map(fn(w) { @sfrealsize.real_size_way(w.0, w.1) + " " + Json::object(w.1).stringify() })
  @halt.saying("home-again: no way \{name} of \{scope} among \{all.join(", ")}")
}

///|
/// The bar's places' middles in the phone's window with the notch open (the chats' pages, newchat_wbtest's
/// bar_places_at's), and its middle's height.
fn home_again_bar(win? : (String, Double, Double, Int, String) = home_again_window) -> (Array[Double], Double) {
  let (_, w, h, _, _) = win
  (bar_centres(w - 44.0, 1.0, 4).map(fn(x) { x + 22.0 }), h - 22.0 - 28.0)
}

///|
/// The rates the frames are walked at: a phone's 60 and 120 a second.
let home_again_periods : Array[(String, Double)] = [("60", 1000.0 / 60.0), ("120", 1000.0 / 120.0)]

///|
test "home again: a place of the bar tapped from Home at rest, and Home tapped again" {
  for rate in home_again_periods {
    for variant in [("phone", false, true), ("reduced", true, true), ("host-drawn", false, false)] {
      // (drawn as a host draws, the checks off: at 60 alone)
      if !variant.2 && rate.0 != "60" {
        continue
      }
      for place in ["profiles", "connects"] {
        let tag = "\{rate.0} \{variant.0}"
        let (t, _, _) = home_again_open(tag, rate.1, reduced=variant.1, checks=variant.2)
        bars_picked.set(Some(([["chats", "profiles", "connects", "usage"]], 0)))
        t.run_for(kept_switch_over_ms)
        let (xs, y) = home_again_bar()
        let i = if place == "profiles" { 1 } else { 2 }
        home_again_measure(t, "\{tag} home→\{place}", fn() { t.tap(xs[i], y) })
        println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked \{place})")
        // (the place made, first visit; Home put by, not laid out again nor let go)
        assert_eq(home_again_peak.val, if place == "profiles" { (7, 0, 10) } else { (723, 0, 506) }, msg="\{tag} home→\{place}")
        t.run_for(kept_switch_over_ms)
        home_again_measure(t, "\{tag} \{place}→home", fn() { t.tap(xs[0], y) })
        println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked chats)")
        // (Home taken back: nothing made; the old view's place let go of, 连接 put by)
        assert_eq(home_again_peak.val, (0, if place == "profiles" { 7 } else { 1 }, 6), msg="\{tag} \{place}→home")
      }
    }
  }
}

///|
test "home again: another workspace switched to from Home at rest, and back" {
  for rate in home_again_periods {
    let tag = "\{rate.0} phone"
    let (t, _, src) = home_again_open(tag, rate.1)
    let ws = fn() { @signals.untracked(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }) }
    let names = @signals.untracked(fn() { workspace_in_view(src).1.map(fn(w) { w.id }) })
    println("home-again \{tag}: workspaces \{names.join(", ")}, in view \{Repr(ws())}")
    home_again_measure(t, "\{tag} ws1→ws2", fn() {
      @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
    })
    println("home-again \{tag}: in view \{Repr(ws())}")
    t.run_for(kept_switch_over_ms)
    home_again_measure(t, "\{tag} ws2→ws1", fn() {
      @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.switch_workspace(src, "ws1") })
    })
    println("home-again \{tag}: in view \{Repr(ws())}")
  }
}

///|
test "home again: the filter switched from all to mine at rest, and back" {
  for rate in home_again_periods {
    let tag = "\{rate.0} phone"
    let (t, _, src) = home_again_open(tag, rate.1)
    let w = @signals.untracked(fn() { workspace_in_view(src).0.unwrap() })
    home_again_measure(t, "\{tag} all→mine", fn() {
      @ui.view_tree().unwrap().event(t.time(), fn() { home_filter_go(src, w, "mine") })
    })
    t.run_for(kept_switch_over_ms)
    home_again_measure(t, "\{tag} mine→all", fn() {
      @ui.view_tree().unwrap().event(t.time(), fn() { home_filter_go(src, w, "all") })
    })
    t.run_for(kept_switch_over_ms)
    home_again_measure(t, "\{tag} all→mine again", fn() {
      @ui.view_tree().unwrap().event(t.time(), fn() { home_filter_go(src, w, "mine") })
    })
  }
}

///|
test "home again: the whole chats value arriving again at rest, the same and with one row's words changed" {
  for rate in home_again_periods {
    let tag = "\{rate.0} phone"
    let (t, c, _) = home_again_open(tag, rate.1)
    let at = home_again_way(c, "chats", "ws1")
    let asked = c.ways()[at].1
    let whole = @sfrealsize.real_size_value("chats", asked).unwrap()
    // (as a device has it: the core's words parsed anew, every object another with the same in it)
    let anew = fn() { @json.parse(whole.stringify()) catch { _ => whole } }
    home_again_measure(t, "\{tag} chats whole, the same", fn() {
      home_again_post(t, c, at, Json::object({ "value": anew() }))
    })
    t.run_for(kept_switch_over_ms)
    // (the pinned day's second row, in view: its title, the keys and order as they were)
    let ops = @json.parse(
      (
        #|[{"path":["days"],"key":["daysAgo"],"patch":-1,"ops":[{"path":["items"],"key":["station","id"],"patch":["ws1/st2","k-willow-3"],"ops":[{"path":["title"],"set":"换了一个标题：升级测试都过了"}]}]}]
      ),
    ) catch {
      _ => Json::array([])
    }
    let changed = match ops {
      Array(o) => @core.apply_delta(anew(), o)
      _ => anew()
    }
    home_again_measure(t, "\{tag} chats whole, a row's words", fn() {
      home_again_post(t, c, at, Json::object({ "value": changed }))
    })
    t.run_for(kept_switch_over_ms)
    home_again_measure(t, "\{tag} chats whole, the same again", fn() {
      home_again_post(t, c, at, Json::object({ "value": anew() }))
    })
    t.run_for(kept_switch_over_ms)
    // (the list in its bones, as it is before the core has said it (a workspace or a filter come to before it is
    // answered), then the value whole: its rows in the bones' place)
    home_again_measure(t, "\{tag} chats none (bones)", fn() {
      home_again_post(t, c, at, Json::object({ "value": Json::null() }))
    })
    t.run_for(kept_switch_over_ms)
    home_again_measure(t, "\{tag} chats whole after bones", fn() {
      home_again_post(t, c, at, Json::object({ "value": anew() }))
    })
    t.run_for(kept_switch_over_ms)
    // (the gate's own: the core's rig's message in the chat, a delta on a row in place)
    for cause in c.changed(at) {
      if cause.0 == "message" {
        home_again_measure(t, "\{tag} chats delta, message (the gate's)", fn() {
          home_again_post(t, c, at, cause.1[0])
        })
      }
    }
  }
}

///|
/// A message in `id` of station `st` (fixture names), its row taken to the top of today's day, before `before`: the
/// keyed ops the core sends a device for it (a move and a patch, collections.ts `applyKeyed`).
fn home_again_moved(st : String, id : String, before : (String, String)) -> Json {
  let row = Json::array([Json::string(st), Json::string(id)])
  let ahead = Json::array([Json::string(before.0), Json::string(before.1)])
  let key = Json::array([Json::string("station"), Json::string("id")])
  let items = Json::array([Json::string("items")])
  Json::array([
    Json::object({
      "path": Json::array([Json::string("days")]),
      "key": Json::array([Json::string("daysAgo")]),
      "patch": Json::number(0.0),
      "ops": Json::array([
        Json::object({ "path": items, "key": key, "move": row, "before": ahead }),
        Json::object({
          "path": items,
          "key": key,
          "patch": row,
          "ops": Json::array([
            Json::object({ "path": Json::array([Json::string("last"), Json::string("preview")]), "set": Json::string("好的，已经合进去了。") }),
            Json::object({ "path": Json::array([Json::string("last"), Json::string("seq")]), "set": Json::number(9001.0) }),
          ]),
        }),
      ]),
    }),
  ])
}

///|
test "home again: a chat not first taken to the top by a message, as a chats delta" {
  for rate in home_again_periods {
    let tag = "\{rate.0} phone"
    let (t, c, _) = home_again_open(tag, rate.1)
    let at = home_again_way(c, "chats", "ws1")
    let today = fn() { t.words().filter(fn(w) { w.0 == "今天" }).map(fn(w) { w.2.to_int() }) }
    println("home-again \{tag}: 今天 drawn at \{Repr(today())}")
    // (today's eighth row to its top, the list at its top: the pinned day's 13 rows over both)
    home_again_measure(t, "\{tag} chats delta, today's 8th to its top (out of view)", fn() {
      home_again_post(t, c, at, home_again_moved("ws1/st3", "k-studio-1", ("ws1/st1", "k-maple-0")))
    })
    t.run_for(kept_switch_over_ms)
    // (the list dragged up till today's day is in view, then today's eighth again, another row now, to its top)
    t.drag(180.0, 600.0, 180.0, 150.0, steps=40)
    t.run_for(kept_glide_long_ms)
    t.drag(180.0, 600.0, 180.0, 300.0, steps=40)
    t.run_for(kept_glide_long_ms)
    println("home-again \{tag}: 今天 drawn at \{Repr(today())}")
    home_again_measure(t, "\{tag} chats delta, today's 8th to its top (in view)", fn() {
      home_again_post(t, c, at, home_again_moved("ws1/st2", "k-willow-1", ("ws1/st3", "k-studio-1")))
    })
  }
}

///|
test "home again: Home come back to in a taller phone's window, and from a page of nodes by no tap" {
  for rate in home_again_periods {
    let tall = ("tall", 412.0, 915.0, 2, "")
    for place in ["profiles", "connects", "usage"] {
      let tag = "\{rate.0} tall"
      let (t, _, _) = home_again_open(tag, rate.1, win=tall)
      bars_picked.set(Some(([["chats", "profiles", "connects", "usage"]], 0)))
      t.run_for(kept_switch_over_ms)
      let (xs, y) = home_again_bar(win=tall)
      let i = if place == "profiles" { 1 } else if place == "connects" { 2 } else { 3 }
      home_again_measure(t, "\{tag} home→\{place}", fn() { t.tap(xs[i], y) })
      println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked \{place})")
      let first = if place == "profiles" {
        (7, 0, 10)
      } else if place == "connects" {
        (723, 0, 506)
      } else {
        (346, 0, 273)
      }
      assert_eq(home_again_peak.val, first, msg="\{tag} home→\{place}")
      t.run_for(kept_switch_over_ms)
      home_again_measure(t, "\{tag} \{place}→home", fn() { t.tap(xs[0], y) })
      println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked chats)")
      assert_eq(home_again_peak.val, (0, if place == "profiles" { 7 } else { 1 }, 6), msg="\{tag} \{place}→home")
    }
    // (the phone's window: Home put back at the stack's root by the shell itself, no finger on the bar)
    for place in ["connects", "usage"] {
      let tag = "\{rate.0} phone"
      let (t, _, _) = home_again_open(tag, rate.1)
      bars_picked.set(Some(([["chats", "profiles", "connects", "usage"]], 0)))
      t.run_for(kept_switch_over_ms)
      let (xs, y) = home_again_bar()
      home_again_measure(t, "\{tag} home→\{place}", fn() { t.tap(xs[if place == "connects" { 2 } else { 3 }], y) })
      println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked \{place})")
      t.run_for(kept_switch_over_ms)
      home_again_measure(t, "\{tag} \{place}→home, no tap", fn() {
        @ui.view_tree().unwrap().event(t.time(), fn() { go_place(t.time(), "chats", [], -1) })
      })
      println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked chats)")
      assert_eq(home_again_peak.val, (0, 1, 6), msg="\{tag} \{place}→home, no tap")
    }
  }
}

///|
test "home again: the bar's place already shown tapped again (no switch), on Home and on a page of nodes" {
  let tag = "60 phone"
  let (t, _, _) = home_again_open(tag, 1000.0 / 60.0)
  bars_picked.set(Some(([["chats", "profiles", "connects", "usage"]], 0)))
  t.run_for(kept_switch_over_ms)
  let (xs, y) = home_again_bar()
  home_again_measure(t, "\{tag} home tapped on home", fn() { t.tap(xs[0], y) })
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} home→connects", fn() { t.tap(xs[2], y) })
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} connects tapped on connects", fn() { t.tap(xs[2], y) })
  println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked connects)")
  // (no finger, but from a side as the bar's tap goes: app.switch_way -1, the page coming in sliding as well as fading)
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} connects→home, no tap, from a side", fn() {
    @ui.view_tree().unwrap().event(t.time(), fn() {
      go_place(t.time(), "chats", [["chats", "profiles", "connects", "usage"]], 0)
    })
  })
  println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked chats)")
  // (no finger, the press's asking ahead said first as a finger down on the tab says it (bar.mbt's Pressed), then the
  // switch: which of the two lays out the page that goes)
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} home→connects, no tap, pressed first", fn() {
    @ui.view_tree().unwrap().event(t.time(), fn() {
      @sfbase.place_pressed("connects")
      go_place(t.time(), "connects", [["chats", "profiles", "connects", "usage"]], 0)
    })
  })
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} connects→home, no tap, pressed first", fn() {
    @ui.view_tree().unwrap().event(t.time(), fn() {
      @sfbase.place_pressed("chats")
      go_place(t.time(), "chats", [["chats", "profiles", "connects", "usage"]], 0)
    })
  })
  // (a finger down on the tab, then up 30 ms later, each its own frame)
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} home→connects, down then up", fn() {
    t.press_at(xs[2], y)
    t.run_for(tap_held_ms)
    t.release(xs[2], y)
  })
  // (a finger's switch lays out what the same switch at an event does: the page leaving is put by as it was, never
  // laid out nowhere first, nav_view's `laid_nowhere`)
  assert_eq(home_again_peak.val, (1, 0, 7), msg="home→connects, down then up")
  t.run_for(kept_switch_over_ms)
  home_again_measure(t, "\{tag} connects→home, down then up", fn() {
    t.press_at(xs[0], y)
    t.run_for(tap_held_ms)
    t.release(xs[0], y)
  })
  assert_eq(home_again_peak.val, (0, 1, 6), msg="connects→home, down then up")
  println("home-again \{tag}: on \{Repr(place_of(app.nav.top()))} (asked chats)")
}

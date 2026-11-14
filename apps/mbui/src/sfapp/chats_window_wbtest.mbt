// A chats' list asked by what the screen shows (sfbase rows.mbt first_window: the rows its room shows and a screen
// more, told the core before the list is asked) and grown as it is scrolled near its foot (chats_grow), over the
// made-up core of a long account (sffixture's long-paged, which gives a list by its window as the core does). Its
// first ask is asserted on what the app's own client sent (as late_core_wbtest.mbt's wire_chats); its walk down the
// list on what the pages asked of their source, which the client turns one for one into its messages (a topic read
// is a subscription, let go of an unsubscription, a call a call): under the late core's client (round_trip_again)
// the made-up core's list told a window more did not come again to the client.

///|
/// What of `heard` (the client's messages out) asks or lets go of ws1's list of all its chats, or tells its window:
/// `window <rows>`, `sub`, `unsub`, in order.
fn window_wire(heard : Array[String]) -> Array[String] {
  let ids : Map[Int, Bool] = Map([])
  let out : Array[String] = []
  let ours = fn(p : Map[String, Json]) {
    p.get("scope") == Some(Json::string("ws1")) && p.get("mine") == Some(Json::boolean(false)) && !p.contains("watching") && !p.contains("hidden")
  }
  for h in heard {
    guard h.has_prefix("out ") else { continue }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    match (m.get("subscribe"), m.get("unsubscribe"), m.get("call")) {
      (Some(Object(t)), _, _) if t.get("topic") == Some(Json::string("chats")) && ours(t) => {
        ids[n.to_int()] = true
        out.push("sub")
      }
      (_, Some(True), _) if ids.contains(n.to_int()) => out.push("unsub")
      (_, _, Some(String("chats.window"))) =>
        match m.get("params") {
          Some(Object(p)) if ours(p) =>
            match p.get("rows") {
              Some(Number(r, ..)) => out.push("window \{r.to_int()}")
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// The rows of ws1's list as the app holds them now: their titles, in order, and how many more the core has.
fn window_rows(src : Source) -> (Array[String], Int) {
  @signals.untracked(fn() {
    let titles : Array[String] = []
    match chats_of(src, "ws1", "all").0 {
      Some(v) =>
        for d in v.days {
          for i in d.items {
            titles.push(i.title)
          }
        }
      None => ()
    }
    (titles, @sfbase.chats_more(src, "ws1", "all"))
  })
}

///|
/// Which of `titles` are drawn now within the window's `h` (a word drawn there that its title begins with, cut short
/// or whole).
fn window_drawn(t : @ui.Tester, titles : Array[String], h : Double) -> Array[String] {
  let words = t.words().filter(fn(w) { w.2 + w.4 > 0.0 && w.2 < h && w.5 > 0.0 })
  titles.filter(fn(title) {
    words.iter().any(fn(w) {
      let said = if w.0.has_suffix("…") { w.0.exact_view(end=w.0.length() - 1).to_owned() } else { w.0 }
      said.length() >= 4 && title.has_prefix(said)
    })
  })
}

///|
/// The made-up core of a long account under the app's own client, its calls of a list's window asked of the client as
/// the app's are (src/stillfail's source: every call through it), so that what the client sends has them.
fn window_source(heard : Array[String]) -> Source {
  let src = round_trip_again(fixture("long-paged"), 20.0, heard=fn(m) { heard.push(m) })
  {
    ..src,
    call: fn(name, params, done) {
      if name == "chats.window" {
        @core.call(name, params~)
      } else {
        (src.call)(name, params, done)
      }
    },
  }
}

///|
/// The made-up core of a long account as the app's pages ask it (no client between: what is asked of it is what the app
/// asks), what of ws1's list of all its chats is told its window, asked or let go of put in `asked` as window_wire says
/// it.
fn window_asks(asked : Array[String]) -> Source {
  let src = fixture("long-paged")
  let ours = fn(p : Map[String, Json]) {
    p.get("scope") == Some(Json::string("ws1")) && p.get("mine") == Some(Json::boolean(false)) && !p.contains("watching") && !p.contains("hidden")
  }
  {
    ..src,
    topic_read: fn(name, params) {
      if name == "chats" && ours(params) && !asked.contains("sub") {
        // (its first window told before it, as the app's client tells it: sfbase's chats_told_before)
        let topic = params.copy()
        topic["topic"] = Json::string("chats")
        for told in @sfbase.chats_told_before("chats", Json::object(topic)) {
          match told.1 {
            Object(p) =>
              match p.get("rows") {
                Some(Number(r, ..)) => asked.push("window \{r.to_int()}")
                _ => ()
              }
            _ => ()
          }
          (src.call)(told.0, told.1, @sfbase.answer_unread)
        }
        asked.push("sub")
      }
      (src.topic_read)(name, params)
    },
    call: fn(name, params, done) {
      match (name, params) {
        ("chats.window", Object(p)) if ours(p) =>
          match p.get("rows") {
            Some(Number(r, ..)) => asked.push("window \{r.to_int()}")
            _ => ()
          }
        _ => ()
      }
      (src.call)(name, params, done)
    },
    leave: fn(name, params, reason) {
      if name == "chats" && ours(params) {
        asked.push("unsub")
      }
      (src.leave)(name, params, reason)
    },
    release: fn(name, params) {
      if name == "chats" && ours(params) {
        asked.push("unsub")
      }
      (src.release)(name, params)
    },
  }
}

///|
/// How long the app is let open on its list before a test looks: what it asks answered by the made-up core (the late
/// core's 20 ms too), what comes in moved in.
let window_opened_ms : Double = @ui.move_most_ms * 2.0

///|
/// How long the list is let be after a stroke of the finger or the wheel's turns: its glide comes to rest within it.
let window_rest_ms : Double = @ui.move_most_ms * 2.0

///|
/// The screens a list is held on: its name, its window, its platform (小屏 a phone's, with a finger; 大屏 a desktop's,
/// with a mouse).
let window_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
test "a chats' list's first ask on 小屏 and 大屏: its window told before it, the rows its room shows and a screen more, never fewer than are drawn" {
  let said : Array[String] = []
  for s in window_screens {
    let (name, w, h, platform) = s
    new_run()
    let heard : Array[String] = []
    let src = window_source(heard)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
    t.draw()
    t.run_for(window_opened_ms)
    let wire = window_wire(heard)
    let (titles, more) = window_rows(src)
    let drawn = window_drawn(t, titles, h).length()
    let first = @sfbase.first_window(h)
    said.push("\{name}: \{@ui.list_text(wire[:2].to_owned())} first \{first}, held \{titles.length()}, drawn \{drawn}, more \{more > 0}, bones \{t.bones_drawn()}")
    assert_true(drawn > 0 && drawn <= first, msg="\{name}: \{drawn} rows drawn, told \{first}")
  }
  assert_eq(said, [
    "小屏: [window 30, sub] first 30, held 30, drawn 10, more true, bones 0",
    "大屏: [window 30, sub] first 30, held 30, drawn 11, more true, bones 0",
  ])
}

///|
test "a chats' list scrolled down on 小屏 with a finger and on 大屏 with a mouse: its window grown before its foot shows, the rows there every frame, one subscription all along" {
  let faults : Array[String] = []
  let said : Array[String] = []
  for s in window_screens {
    let (name, w, h, platform) = s
    new_run()
    let asked : Array[String] = []
    let src = window_asks(asked)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
    t.draw()
    t.run_for(window_opened_ms)
    let frames = Ref(0)
    // (each frame: no bones, and while the core has more, the last row held not drawn: the foot never comes up empty)
    let look = fn() {
      frames.val += 1
      if t.bones_drawn() > 0 {
        faults.push("\{name} frame \{frames.val}: bones")
      }
      let (titles, more) = window_rows(src)
      if more > 0 && titles.length() > 0 && window_drawn(t, [titles[titles.length() - 1]], h).length() > 0 {
        faults.push("\{name} frame \{frames.val}: its last row of \{titles.length()} drawn with \{more} more to come")
      }
    }
    if platform == 2 {
      // strokes of a finger up the list, 15 points a move (900 points a second), held still before it is let go, the
      // list at rest a second after each: every frame looked at
      for _ in 0..<8 {
        t.hold_drag(195.0, 700.0, 195.0, 685.0, steps=1)
        look()
        let mut y = 685.0
        while y > 160.0 {
          y -= 15.0
          t.hold_move(195.0, y)
          look()
        }
        for _ in 0..<6 {
          t.hold_move(195.0, y)
          look()
        }
        t.release(195.0, y)
        look()
        let rest = t.time()
        while t.time() - rest < window_rest_ms - 1.0e-6 {
          t.run_for(@ui.frame_period_default)
          look()
        }
      }
    } else {
      // the wheel of a trackpad over the sidebar's list, five turns of 30 points at one moment (each looked at), then a
      // second at rest, every frame of it looked at: the next turns come while its bar still shows from these, and take
      // it along with the list
      for _ in 0..<24 {
        for _ in 0..<5 {
          t.wheel(140.0, 400.0, 30.0)
          look()
        }
        let rest = t.time()
        while t.time() - rest < window_rest_ms - 1.0e-6 {
          t.run_for(@ui.frame_period_default)
          look()
        }
      }
    }
    let wire = asked
    let (titles, _) = window_rows(src)
    said.push("\{name}: subs \{wire.filter(fn(x) { x == "sub" }).length()}, unsubs \{wire.filter(fn(x) { x == "unsub" }).length()}, windows \{@ui.list_text(wire.filter(fn(x) { x.has_prefix("window") }))}, held \{titles.length()}")
  }
  assert_eq(faults, [])
  assert_eq(said, [
    "小屏: subs 1, unsubs 0, windows [window 30, window 50, window 70, window 90], held 90",
    "大屏: subs 1, unsubs 0, windows [window 30, window 50, window 70, window 90], held 90",
  ])
}

///|
test "the made-up core of a long account gives a chats' list by its window as it is told it, as the core does" {
  new_run()
  let src = fixture("long-paged")
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0)
  t.draw()
  let params : Map[String, Json] = { "scope": "ws1", "mine": false }
  let rows = fn() {
    @signals.untracked(fn() {
      let v = src.topic("chats", params).get().value
      (items(v, "days").fold(init=0, fn(n, d) { n + items(Some(d), "items").length() }), field(v, "more"))
    })
  }
  @sffixture.fix_ctx.val = Some(t.ctx())
  let untold = rows()
  (src.call)("chats.window", { "scope": "ws1", "mine": false, "rows": 70 }, @sfbase.answer_unread)
  t.run_for(@ui.frame_period_default * 3.0)
  let told = rows()
  (src.call)("chats.window", { "scope": "ws1", "mine": false, "rows": 40 }, @sfbase.answer_unread)
  t.run_for(@ui.frame_period_default * 3.0)
  assert_eq((untold, told, rows()), ((50, Some(Json::number(1160.0))), (70, Some(Json::number(1140.0))), (70, Some(Json::number(1140.0)))))
}

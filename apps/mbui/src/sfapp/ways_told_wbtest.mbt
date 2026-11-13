// The ways set out with no cause (the owner's recordings of 2026-11-13: on a wide screen, switching a page's tab or a
// chat, an agent's history beside it folding block by block, 用量's hover card drawn longer, 账号's page sliding down
// whole, the sidebar's list reordering): each walked over a core answering late, as a device's does, each call and
// every subscription. A way that sets out after the act's own moment is a cell of `ways_told_known` (answers_still's
// late_ways_held: `B` set out only as an answer came late, `C` the page's own, at 0 ms too), which only falls.

///|
/// The cells that set out a way after their act now, which of the two they are and how many ways at all the paces. What and where is printed as each
/// test runs (WAYS_TOLD).
let ways_told_known : Array[(String, String, Int)] = []

///|
/// How late the made-up core answers what is asked of it (its topics and its calls, ms): at once (what sets out then is
/// the page's own), before what the step sets out at a moment of its own (a hover card's) and after it.
let ways_paces : Array[Double] = [0.0, 80.0, 700.0]

///|
/// The app over fixture `mode` with its core answering all asked of it `ms` late (round_trip: its topics and its calls),
/// in a wide window as a desktop's, built as a host builds it (check_looks(false)), at rest, its chat open where `chat`
/// says.
fn ways_wide(mode : String, ms : Double, chat? : Bool = true, settled? : Bool = true) -> @ui.Tester {
  new_run()
  // (each call answered `ms` late every time, round_trip's; each topic `ms` late each time the client subscribes to it,
  // round_trip_again's: a chat gone back to subscribed anew and answered late again, as on a device)
  let src = round_trip_again(round_trip(fixture(mode), ms), 0.0, late=fn(_, _) { ms })
  if chat {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.check_looks(false)
  t.draw()
  if settled {
    t.run_for(ms * 8.0 + 1000.0)
  }
  t.ways_set_out() |> ignore
  t
}

///|
/// What ways set out after `from` since the last asked, as cell `name`'s at `ms`, put in `found`.
fn ways_after(t : @ui.Tester, found : Array[LateWays], name : String, ms : Double, from : Double) -> Unit {
  let late = t.ways_set_out().filter(fn(w) { w.at > from + 0.5 })
  if late.length() > 0 {
    found.push({
      cell: name,
      ms,
      ways: late.map(fn(w) { "\{w.kind} +\{(w.at - from).round()} ms \{w.made} \{w.part}" }),
    })
  }
}

///|
/// The cells of a wide window, each name its own: held to ways_told_known.
fn ways_told_held(found : Array[LateWays], prefix : String) -> Unit raise {
  late_ways_held("WAYS_TOLD", found, ways_told_known, prefix)
}

///|
/// The sidebar's 用量 hovered in `t`: false where there is none.
fn hover_usage(t : @ui.Tester) -> Bool {
  match t.query(Button, label="用量") {
    Some(b) => {
      let (x, y, w, h) = b.rect
      t.move_to(x + w / 2.0, y + h / 2.0)
      true
    }
    None => false
  }
}

///|
test "ways told: an agent's history open beside a chat, another chat opened, its core answering late" {
  let found = []
  for ms in ways_paces {
    let t = ways_wide("chat", ms)
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
    // (its history opened beside it: what of it comes once its answers are in)
    let opened = t.time()
    app.nav.push(History(r, "s-c1", Some(3)))
    t.run_for(ms * 8.0 + 1000.0)
    ways_after(t, found, "history opened beside the chat", ms, opened)
    let from = t.time()
    let r2 : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" }
    open_chat(r2)
    t.run_for(ms * 8.0 + 1000.0)
    ways_after(t, found, "history beside, another chat", ms, from)
    // (that chat's history open beside it too, then back and forth between the two, each with its history beside it)
    app.nav.push(History(r2, "s-c2", None))
    t.run_for(ms * 8.0 + 1000.0)
    t.ways_set_out() |> ignore
    for c in [r, r2] {
      let from = t.time()
      open_chat(c)
      t.run_for(ms * 8.0 + 1000.0)
      ways_after(t, found, "history beside both, to \{c.session}", ms, from)
    }
  }
  ways_told_held(found, "history ")
}

///|
test "ways told: the sidebar's 用量 hovered, after its core answered and before, its core answering late" {
  let found = []
  for ms in ways_paces {
    // (hovered once all the window asked is answered, and as it opens, its answers still to come)
    for settled in [true, false] {
      let name = if settled { "用量 hovered" } else { "用量 hovered as it opens" }
      let t = ways_wide("chat", ms, settled~)
      // (as it opens: hovered the frame the sidebar first shows 用量, what it holds still to come)
      while !hover_usage(t) {
        assert_true(t.time() < 10000.0, msg="\{name}: no 用量 to hover")
        t.frame_at(t.time() + @ui.frame_period_default)
      }
      let from = t.time()
      t.run_for(ms * 8.0 + 1000.0)
      ways_after(t, found, name, ms, from)
    }
  }
  ways_told_held(found, "用量 ")
}

///|
test "ways told: 账号's page opened from the rail, its core answering late" {
  let found = []
  for ms in ways_paces {
    let t = ways_wide("chat", ms)
    let from = t.time()
    @sfbase.go_place("profiles") |> ignore
    t.run_for(ms * 8.0 + 1000.0)
    ways_after(t, found, "账号", ms, from)
  }
  ways_told_held(found, "账号")
}

///|
test "ways told: the rail's places one after another and back to the chats, its core answering late" {
  let found = []
  for ms in ways_paces {
    let t = ways_wide("chat", ms)
    for place in ["files", "profiles", "archive"] {
      let from = t.time()
      @sfbase.go_place(place) |> ignore
      t.run_for(ms * 8.0 + 1000.0)
      ways_after(t, found, "rail " + place, ms, from)
    }
    let from = t.time()
    match t.query(Button, label="对话") {
      Some(b) => {
        let (x, y, w, h) = b.rect
        t.tap(x + w / 2.0, y + h / 2.0)
      }
      None => fail("rail back: no 对话 on the rail")
    }
    t.run_for(ms * 8.0 + 1000.0)
    ways_after(t, found, "rail back to the chats", ms, from)
  }
  ways_told_held(found, "rail ")
}

// A web service's panel sliding in beside a chat on the wide frame, or out: the chat's column crosses the width its
// list is laid out narrow at (sfpages' chat_narrow_w: 20 between messages, not 28) on the way, and the one its composer
// reaches across the pane at, 8 under it, not 16 (composer_foot_in). Laid out by the width it had at each frame, every
// message's room over it stepped 8 at once partway (rows_steady.mbt's jolt), and the composer with it, or apart from the
// last row. Now on the page's way (@sfbase.page_way, said from the frame the panel sets off on) the list and the
// composer are laid out as at the narrower of where the pane set off and where it goes, from that frame till the moment
// it is there: each row another version then and the composer's room going there, from those moments, whichever frames
// are drawn between. The chat and its tabs come from a Client as a device's core gives them, the tabs it keeps two
// frames after they are asked, not at once as the fixture's core answers.

///|
/// The fixture's chat open on a 1280 by 800 frame, a file dropped on it (`drop`), its chat and prefs from `client`; its
/// chat's value as given, and its subscription's id.
fn panel_gap_open(client : @core.Client, drop? : Bool = true) -> (@ui.Tester, Source, Map[String, Json], Int) raise {
  new_run()
  let base = fixture("chat")
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let params = @sfbase.chat_params(chat)
  let which = fn(name : String, p : Map[String, Json]) {
    name == "prefs" || (name == "chat" && p.get("session") == Some(Json::string("s-c1")))
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if !which(name, p) {
        return base.topic(name, p).get().snapshot()
      }
      let sub = client.subscribe(name, params=@sfbase.core_topic_params(name, p)).followed()
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if which(name, p) {
        client.subscribe(name, params=@sfbase.core_topic_params(name, p)).followed().waiting
      } else {
        (base.waits)(name, p)
      }
    },
  }
  open_chat(chat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  let give = fn(topic : String, p : Map[String, Json]) raise {
    let sub = client.subscribe(topic, params=@sfbase.core_topic_params(topic, p))
    guard base.prefetch(topic, p).value is Some(Object(m)) else { fail("no \{topic} in the fixture") }
    client.receive_json({ "id": Json::number(sub.id.to_double()), "value": Json::object(m.copy()) })
    (m.copy(), sub.id)
  }
  give("prefs", {}) |> ignore
  t.frame()
  let (chat_value, chat_id) = give("chat", params)
  t.frame()
  guard t.shown_of("做完了：") is Some((x, y, w, h)) && w > 0.0 && h > 0.0 else { fail("the chat's message not shown") }
  if drop {
    @sfbase.machine_here.val = Some("ws1/st1")
    t.drop_files(x + w / 2.0, y + h / 2.0, [("报告.pdf", b"%PDF")], paths=["/Users/lin/报告.pdf"])
    t.frame()
    t.frame()
  }
  (t, src, chat_value, chat_id)
}

///|
test "wide: a web service's panel sliding in beside a chat, its tabs coming late: the chat's rows steady as its column narrows" {
  let client = @core.Client::new(fn(_) {  })
  let (t, src, chat_value, chat_id) = panel_gap_open(client)
  let link = @sfbase.link_target({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "s-c1", "service": "j-web" })
  assert_true(@sfbase.open_target(src, link, false, None))
  t.frame()
  t.frame()
  let with_tabs = chat_value.copy()
  with_tabs["tabs"] = { "open": ["service:j-web"], "shown": "service:j-web", "auto": true }
  client.receive_json({ "id": Json::number(chat_id.to_double()), "value": Json::object(with_tabs) })
  // (each frame held to rows_steady.mbt as it is drawn)
  t.run_for(@ui.move_most_ms)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  assert_eq(side_now(r), (["service:j-web"], "service:j-web"))
  // (its column narrow at rest beside the panel: the way it took crossed chat_narrow_w)
  let widths = t.list_row_boxes().map(fn(rows) { rows.map(fn(b) { b.2 }) }).filter(fn(ws) { ws.length() > 3 })
  assert_true(widths.length() > 0 && widths[0][0] <= @sfpages.chat_narrow_w, msg="\{Repr(widths)}")
  // and out again, the tabs closed coming late as well
  // (closed by its ×: the hand's)
  t.by_hand(fn() { side_change(r, "close", Some("service:j-web")) })
  t.frame()
  t.frame()
  client.receive_json({ "id": Json::number(chat_id.to_double()), "value": Json::object(chat_value) })
  t.run_for(@ui.move_most_ms)
  assert_eq(side_now(r), ([], ""))
  @ui.run_let_go()
}

///|
/// The chat's list's rows (the widest list's) as drawn: (x, y, width, height) each, top to bottom.
fn chat_rows_drawn(t : @ui.Tester) -> Array[(Double, Double, Double, Double)] {
  let mut best : Array[(Double, Double, Double, Double)] = []
  for rs in t.list_row_boxes() {
    if rs.length() > 0 && (best.length() == 0 || rs[0].2 > best[0].2) {
      best = rs
    }
  }
  best
}

///|
/// Where the composer's field is drawn from the top (the first editor of the draw list, as Tester::dump says it).
fn composer_field_y(t : @ui.Tester) -> Double {
  for line in t.dump().split("\n") {
    let l = line.trim_start(chars=" ").to_owned()
    if l.has_prefix("editor ") {
      let xy = l.split(" ").collect()[1].split(",").collect()
      return dump_number(xy[1].to_owned())
    }
  }
  -1.0
}

///|
/// Held on every frame the Tester draws from now (Tester::each_frame) till `stop` is called: no row of the chat's list
/// moves more than `most` from where it was the frame before (the rows still in view, matched from the list's end it
/// follows), nor the composer's field more than 1.5 from where it was over the list's last row (its room); each frame's
/// column width kept (where the list is laid out narrower on the way, in its middle), to tell which widths the frames
/// compared crossed. `stop` gives those, and
/// the first row that went further ("" none).
fn rows_held(t : @ui.Tester, most : Double) -> (() -> (Array[(Double, Double)], String)) {
  let was : Ref[Array[(Double, Double, Double, Double)]] = Ref(chat_rows_drawn(t))
  // (the column's width: the list's, and as far again as it is put in from the column's side, at rest none)
  let x0 = was.val[0].0
  let pane = fn(b : (Double, Double, Double, Double)) { b.2 + 2.0 * (b.0 - x0) }
  let apart = Ref(composer_field_y(t) - was.val[was.val.length() - 1].1)
  let crossed : Array[(Double, Double)] = []
  let failed : Ref[String] = Ref("")
  t.each_frame(
    Some(fn() {
      let now = chat_rows_drawn(t)
      let before = was.val
      if now.length() > 0 && before.length() > 0 {
        let n = if now.length() < before.length() { now.length() } else { before.length() }
        for k in 1..=n {
          let a = before[before.length() - k]
          let b = now[now.length() - k]
          let d = (b.1 - a.1).abs()
          if d > most && failed.val == "" {
            failed.val = "at \{t.time()}: the row \{k} from the end went \{d} at once (\{Repr(a)} to \{Repr(b)})"
          }
        }
        crossed.push((pane(before[0]), pane(now[0])))
        let gap = composer_field_y(t) - now[now.length() - 1].1
        if (gap - apart.val).abs() > 1.5 && failed.val == "" {
          failed.val = "at \{t.time()}: the composer's field went \{gap - apart.val} from the last row at once (\{apart.val} to \{gap})"
        }
        apart.val = gap
      }
      was.val = now
    }),
  )
  fn() {
    t.each_frame(None)
    (crossed, failed.val)
  }
}

///|
/// Whether a frame compared went across width `w` (one way or the other).
fn went_across(crossed : Array[(Double, Double)], w : Double) -> Bool {
  crossed.iter().any(fn(p) { (p.0 > w) != (p.1 > w) })
}

///|
test "wide: a web service's panel sliding in beside a chat and out, no file in its composer: no row steps in a frame" {
  let client = @core.Client::new(fn(_) {  })
  let (t, src, chat_value, chat_id) = panel_gap_open(client, drop=false)
  let link = @sfbase.link_target({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "s-c1", "service": "j-web" })
  assert_true(@sfbase.open_target(src, link, false, None))
  t.frame()
  t.frame()
  let with_tabs = chat_value.copy()
  with_tabs["tabs"] = { "open": ["service:j-web"], "shown": "service:j-web", "auto": true }
  client.receive_json({ "id": Json::number(chat_id.to_double()), "value": Json::object(with_tabs) })
  // (the rows measured here as well as by rows_steady.mbt: each display frame on the way in, drawn as a host draws
  // them, its column crossing the width the composer reaches across at and chat_narrow_w; a row's room going 8 at
  // once is a step; the rooms under a row easing to theirs together, as the list is laid out anew as the way sets off
  // or is there (sfpages' chat_list laid_w), move it less)
  let across = @sfpages.composer_width(2000.0) + 2.0 * @sfpages.composer_side()
  let stop = rows_held(t, 7.5)
  t.run_as_host(@ui.move_most_ms)
  let (crossed, went) = stop()
  assert_eq(went, "")
  assert_true(went_across(crossed, across) && went_across(crossed, @sfpages.chat_narrow_w), msg="\{Repr(crossed)}")
  let widths = t.list_row_boxes().map(fn(rows) { rows.map(fn(b) { b.2 }) }).filter(fn(ws) { ws.length() > 3 })
  assert_true(widths.length() > 0 && widths[0][0] <= @sfpages.chat_narrow_w, msg="\{Repr(widths)}")
  // and out again, the tabs closed coming late as well
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let stop = rows_held(t, 7.5)
  // (closed by its ×: the hand's)
  t.by_hand(fn() { side_change(r, "close", Some("service:j-web")) })
  t.run_as_host(2.0 * 1000.0 / 60.0)
  client.receive_json({ "id": Json::number(chat_id.to_double()), "value": Json::object(chat_value) })
  t.run_as_host(@ui.move_most_ms)
  let (crossed, went) = stop()
  assert_eq(went, "")
  assert_true(went_across(crossed, across) && went_across(crossed, @sfpages.chat_narrow_w), msg="\{Repr(crossed)}")
  @ui.run_let_go()
}

///|
/// How far apart the moments of a slide panel_way_seen looks at are.
let way_look_ms : Double = 50.0

///|
/// The chat's rows (the last four's tops), its composer's field and the rows' width, at each 50 ms from the frame the
/// panel sets off on (the frame after its tabs come, in, and after it is closed, out: a display's at 60 Hz either way),
/// the frames between drawn `every` ms apart (0: only as due and at each of those moments, Tester::run_for_exact).
fn panel_way_seen(every : Double) -> Array[String] raise {
  let client = @core.Client::new(fn(_) {  })
  let (t, src, chat_value, chat_id) = panel_gap_open(client, drop=false)
  let hz60 = 1000.0 / 60.0
  t.set_frame_period(hz60)
  let link = @sfbase.link_target({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "s-c1", "service": "j-web" })
  assert_true(@sfbase.open_target(src, link, false, None))
  t.run_for(way_look_ms)
  let seen = []
  let look = fn(phase : String) {
    // (the frame it sets off on)
    t.set_frame_period(hz60)
    t.frame()
    if every > 0.0 {
      t.set_frame_period(every)
    }
    for k in 1..=12 {
      if every > 0.0 {
        t.run_for(way_look_ms)
      } else {
        t.run_for_exact(way_look_ms)
      }
      let rows = chat_rows_drawn(t)
      let tops = rows[rows.length() - 4:].iter().map(fn(b) { (b.1 * 10.0).round() / 10.0 }).collect()
      let w = (rows[0].2 * 10.0).round() / 10.0
      let x = (rows[0].0 * 10.0).round() / 10.0
      let foot = (rows[rows.length() - 1].3 * 10.0).round() / 10.0
      seen.push("\{phase} +\{k.to_double() * way_look_ms}: list \{x}+\{w} rows \{@ui.list_text(tops)} foot \{foot} field \{composer_field_y(t)}")
    }
  }
  let with_tabs = chat_value.copy()
  with_tabs["tabs"] = { "open": ["service:j-web"], "shown": "service:j-web", "auto": true }
  client.receive_json({ "id": Json::number(chat_id.to_double()), "value": Json::object(with_tabs) })
  look("in")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  // (closed by its ×: the hand's)
  t.by_hand(fn() { side_change(r, "close", Some("service:j-web")) })
  client.receive_json({ "id": Json::number(chat_id.to_double()), "value": Json::object(chat_value) })
  look("out")
  @ui.run_let_go()
  seen
}

///|
test "wide: a web service's panel sliding in beside a chat and out: its rows and composer where they are at each moment from where it set off, however many frames were drawn" {
  let at60 = panel_way_seen(1000.0 / 60.0)
  let at120 = panel_way_seen(1000.0 / 120.0)
  let sparse = panel_way_seen(0.0)
  assert_eq(at120, at60)
  assert_eq(sparse, at60)
}

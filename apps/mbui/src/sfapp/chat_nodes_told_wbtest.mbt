// What a chat's page made as nodes tells the core is fact, told once it is so (the chat's seventh principle; sfpages'
// chat_read_node says how): read-up-to is the last message seen whole on the page in front, the place the message at
// the top; nothing told while the hand scrolls the list or it glides on after (told as it comes to rest), nothing while
// another page covers it; as it is left, that it shows no more told once and where it was left at most once more, and
// what the page read of the core let go in the frame that tells it (no reader of the page's outlives it: sfbase's
// linger_tick reads a chat only through its page's source). On 小屏 (a finger) and 大屏 (the wheel), over the long chat
// (chat_window_wbtest's) whose every call to the core is answered 0 or 400 ms late, its subscriptions held by a made-up
// core's client (@core.Client), what it is told recorded as it is called.

///|
/// The made-up core round the long chat: the client that holds its subscriptions, the calls it was told
/// (`client.focus`, `chat.place`), and each fault found as a frame was drawn.
priv struct TdCore {
  k : RsCore
  client : @core.Client
  told : Array[(String, Json)]
  faults : Array[String]
}

///|
/// The long chat's source under `k`, its chats' subscriptions held by `client` as a device's client holds them, what
/// it is told recorded in `told`.
fn td_source(k : RsCore, client : @core.Client, told : Array[(String, Json)]) -> Source {
  let base = rs_source(k)
  {
    ..base,
    call: fn(name, args, done) {
      if name == "chat.place" || name == "client.focus" {
        told.push((name, args))
      }
      (base.call)(name, args, done)
    },
    topic_read: fn(name, p) {
      if name == "chat" {
        client.follow_topic(name, params=@sfbase.core_topic_params(name, p)) |> ignore
      }
      (base.topic_read)(name, p)
    },
    leave: fn(name, p, reason) {
      if reason is @sfbase.TopicLeave::Owned(stop) {
        stop()
        return
      }
      if name == "chat" {
        client.leave_topic(name, params=@sfbase.core_topic_params(name, p))
      }
      (base.leave)(name, p, reason)
    },
    release: fn(name, p) {
      if name == "chat" {
        client.release_topic(name, params=@sfbase.core_topic_params(name, p))
      }
      (base.release)(name, p)
    },
  }
}

///|
/// Whether the client holds chat `r`'s subscription.
fn td_held(c : TdCore, r : ChatRef) -> Bool {
  c.client.peek_topic("chat", params=@sfbase.core_topic_params("chat", @sfbase.chat_params(r))) is Some(_)
}

///|
/// What chat `r` was told from the `from`th call on: what it shows (`client.focus {chat}`), that it was left
/// (`client.focus {left}`), where it is (`chat.place`, by its thread).
fn td_of(c : TdCore, r : ChatRef, from : Int, thread : Double) -> (Array[Json], Array[Json], Array[Json]) {
  let shows = []
  let lefts = []
  let places = []
  for i = from; i < c.told.length(); i = i + 1 {
    let (name, args) = c.told[i]
    if name == "client.focus" {
      if @sfbase.text(@sfbase.field(Some(args), "chat"), "session") == r.session {
        shows.push(args)
      }
      if @sfbase.text(@sfbase.field(Some(args), "left"), "session") == r.session {
        lefts.push(args)
      }
    } else if @sfbase.number(Some(args), "thread") == thread {
      places.push(args)
    }
  }
  (shows, lefts, places)
}

///|
/// The long chat opened on screen `s` with its page made as nodes, its core `late` ms late, at rest; each frame drawn
/// looked at: once the chat was told left, its subscription let go by that frame's end.
fn td_open(s : (String, Double, Double, Int), late : Double) -> (@ui.Tester, Source, TdCore) {
  let (_, w, h, platform) = s
  new_run()
  @sf.presenters_reset()
  @sfbase.chat_page_nodes.set(true)
  let k : RsCore = {
    l: long_chat(),
    now: 0.0,
    late,
    gate: Ref(false),
    held: [],
    told: @signals.signal(0),
    working: Ref(false),
    grown: [],
    carded: Map([]),
    look: None,
    older: 0,
  }
  let told : Array[(String, Json)] = []
  let client = @core.Client::new(fn(_) {  })
  let c : TdCore = { k, client, told, faults: [] }
  let src = td_source(k, client, told)
  open_chat(long_ref)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  t.set_rows_on_pixels(true)
  t.each_frame(
    Some(fn() {
      k.now = t.time()
      let (_, lefts, _) = td_of(c, long_ref, 0, td_thread)
      if lefts.length() > 0 && td_held(c, long_ref) && c.faults.length() == 0 {
        c.faults.push("\{s.0} late \{late}: its subscription held past the frame it was told left in, at \{t.time()}")
      }
      rs_answer(k)
    }),
  )
  t.between_frames(fn() {  }, due=fn() { rs_due(k) })
  rs_rest(t, long_opened_ms)
  (t, src, c)
}

///|
/// The long chat's thread (the fixture's s-c1).
let td_thread : Double = 7.0

///|
/// On screen `s` over a core `late` ms late: the long chat opened, read up by two strokes, covered by another chat as a
/// message comes, shown again and left. What it was told that is no fact, or told when it is not to be, said.
fn td_walk(s : (String, Double, Double, Int), late : Double) -> Array[String] {
  let broken : Array[String] = []
  let name = "\{s.0} late \{late}"
  let (t, src, c) = td_open(s, late)
  let r = long_ref
  // opened at its end: it shows, its end seen, its last message seen whole; its subscription held
  let (shows, _, _) = td_of(c, r, 0, td_thread)
  match shows.last() {
    Some(f) =>
      if chat_nodes_focus_told(f) != (Some(Json::boolean(true)), Some(Json::number(200.0))) {
        broken.push("\{name}: opened, told \{f.stringify()}")
      }
    None => broken.push("\{name}: opened, told nothing")
  }
  if !td_held(c, r) {
    broken.push("\{name}: opened, its subscription not held")
  }
  // read up, two strokes: where it is told once a stroke, at rest (as the old page, ui's Ctx::list_moving): nothing
  // while a finger holds the list or as it glides on after it lets go, once as it rests; a pixel wheel's stroke, which
  // eases not, leaves it at rest at once
  for i in 0..<2 {
    let from = c.told.length()
    rs_up(t, s, s.2 * 0.4)
    let (_, _, held) = td_of(c, r, from, td_thread)
    if s.3 == 2 && held.length() > 0 {
      broken.push("\{name}: stroke \{i + 1}, where it is told as the finger holds it: \{Repr(held.map(fn(x) { x.stringify() }))}")
    }
    rs_rest(t, long_rest_ms * 2.0)
    let (_, _, placed) = td_of(c, r, from, td_thread)
    if placed.length() != 1 {
      broken.push("\{name}: stroke \{i + 1}, where it is told \{placed.length()} times: \{Repr(placed.map(fn(x) { x.stringify() }))}")
    }
  }
  let (shows, _, places) = td_of(c, r, 0, td_thread)
  match shows.last() {
    Some(f) if chat_nodes_focus_told(f).0 == Some(Json::boolean(false)) => ()
    _ => broken.push("\{name}: read up, its end not told unseen")
  }
  let read_up = match places.last() {
    Some(p) if @sfbase.field(Some(p), "seq") is Some(_) => Some(p)
    _ => {
      broken.push("\{name}: read up, where it is not told")
      None
    }
  }
  // covered by another chat (a chat's link, over it) as a message comes: nothing told of it
  let covered = c.told.length()
  let link = @sfbase.link_target({ "opens": "chat", "workspace": "ws1", "station": "st1", "chat": "s-c2" })
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.open_target(src, link, false, None) |> ignore })
  rs_rest(t, long_rest_ms)
  rs_told(c.k, fn() { c.k.l.last.set(c.k.l.last.get() + 1) })
  rs_rest(t, long_rest_ms)
  let (shows, lefts, places) = td_of(c, r, covered, td_thread)
  if shows.length() + lefts.length() + places.length() > 0 {
    broken.push("\{name}: told while covered: \{Repr(c.told[covered:].to_owned().map(fn(x) { x.1.stringify() }))}")
  }
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.go_back() |> ignore })
  rs_rest(t, long_rest_ms * 2.0)
  // left: told once it shows no more, where it was left told at most once more (to the pixel) and as it was, nothing
  // told of it after; its subscription let go in the frame that tells it (each_frame's look)
  let before = c.told.length()
  @ui.view_tree().unwrap().event(t.time(), fn() { home() })
  rs_rest(t, long_rest_ms * 2.0)
  let (shows, lefts, places) = td_of(c, r, before, td_thread)
  if lefts.length() != 1 {
    broken.push("\{name}: left, told so \{lefts.length()} times")
  }
  if shows.length() > 0 {
    broken.push("\{name}: told it shows once left")
  }
  if places.length() > 1 {
    broken.push("\{name}: left, where it was told \{places.length()} times")
  }
  match (places.last(), read_up) {
    (Some(p), Some(was)) if @sfbase.field(Some(p), "seq") != @sfbase.field(Some(was), "seq") =>
      broken.push("\{name}: left where it was read (\{was.stringify()}), told \{p.stringify()}")
    _ => ()
  }
  if td_held(c, r) {
    broken.push("\{name}: left, its subscription still held")
  }
  for f in c.faults {
    broken.push(f)
  }
  broken
}

///|
test "a chat's page made as nodes, 小屏, the core 0 ms late: read up, covered, left; what the core is told is fact, told once it is so, and what it read let go with it" {
  assert_eq(td_walk(long_screens[0], 0.0), [])
}

///|
test "a chat's page made as nodes, 小屏, the core 400 ms late: read up, covered, left; what the core is told is fact, told once it is so, and what it read let go with it" {
  assert_eq(td_walk(long_screens[0], 400.0), [])
}

///|
test "a chat's page made as nodes, 大屏, the core 0 ms late: read up, covered, left; what the core is told is fact, told once it is so, and what it read let go with it" {
  assert_eq(td_walk(long_screens[1], 0.0), [])
}

///|
test "a chat's page made as nodes, 大屏, the core 400 ms late: read up, covered, left; what the core is told is fact, told once it is so, and what it read let go with it" {
  assert_eq(td_walk(long_screens[1], 400.0), [])
}

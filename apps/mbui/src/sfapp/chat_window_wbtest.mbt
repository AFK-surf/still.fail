// A chat asked by what the screen shows (sfbase rows.mbt chat_first_window: as many of its last messages as fill the
// window at the least height a row the core counts has, told the core before the chat is asked, `chat.window`), a
// screen kept laid out above what shows as it rests and as it is read back (`chat.older` with chat_grow_rows, whenever
// less is: chat_list.mbt chat_short_above), over a made-up core of a long chat (LongChat: 200 messages, given by its
// window as the core gives them, its answers coming between frames as the core's do). Every frame of a fling up on 小屏
// and of a wheel on 大屏 through its growths is looked at; and what goes to a message outside the window it opened on
// (a notification's, ⌘F, the bell to what waits to be decided, 对话目录) or opens away from its end (its unread line)
// still does.

///|
/// The made-up core of a long chat: its window into 200 messages (`first` to `last`), what it was asked in order
/// (`asked`: `window <rows>`, `sub`, `older`, `around <seq>`, `newer`), its answers held till the next frame (`held`),
/// where it opens as the core does: about its first unread (`unread`, 0 none) whatever it was told, else at its end
/// with as many as it was told (50 untold); what waits to be decided in it (`asks`, their seqs).
priv struct LongChat {
  first : @signals.Signal[Int]
  last : @signals.Signal[Int]
  asked : Array[String]
  held : Array[() -> Unit]
  unread : Int
  asks : Array[Int]
  /// each message a station's notice, joined to the one before (the shortest rows a chat has)
  notices : Bool
}

///|
let long_count : Int = 200

///|
/// How many entries the core's page before brings (station/topics.ts PAGE).
let long_page : Int = 50

///|
/// What message `n` of the long chat says: its number first, every third a word, the others a line or two.
fn long_words(n : Int) -> String {
  if n % 3 == 0 {
    "第\{n}条：好。"
  } else {
    "第\{n}条：检查了构建脚本的第 \{n % 7 + 1} 步，接下来把签名和上传也过一遍，有问题再说。"
  }
}

///|
/// The long chat as the core gives it, its window now, made of the fixture's chat `base` (its head, its agent).
fn long_value(base : Json, l : LongChat) -> Json {
  guard base is Object(chat) else { return base }
  let template = items(Some(base), "messages")
    .iter()
    .find_first(fn(m) {
      if l.notices {
        m is Object(o) && o.contains("notice")
      } else {
        !flag(Some(m), "system") && !flag(Some(m), "mine")
      }
    })
    .unwrap_or(Json::object({}))
  guard template is Object(t) else { return base }
  let first = l.first.get()
  let last = l.last.get()
  let messages : Array[Json] = []
  for n in first..=last {
    let m = t.copy()
    let words = long_words(n)
    m["seq"] = Json::number(n.to_double())
    m["ts"] = Json::string("ts\{n}")
    m["text"] = Json::string(words)
    m["words"] = Json::array([{ "text": Json::string(words) }])
    // (its tree as the core gives it, a line of words: nothing asked of the core's `markdown` for it)
    let md : Json = [["p", [[0, Json::number(words.length().to_double())]]]]
    m["md"] = md
    if l.notices {
      m["notice"] = { "failed": false, "words": Json::string(words), "md": md }
    }
    m["joined"] = Json::boolean(n > first && (l.notices || n % 4 != 1))
    for k in ["said", "attachments", "card", "options", "quotes"] {
      m.remove(k)
    }
    messages.push(Json::object(m))
  }
  let v = chat.copy()
  v["messages"] = Json::array(messages)
  v["more"] = Json::boolean(first > 1)
  v["newer"] = Json::boolean(last < long_count)
  v["firstEntry"] = Json::number(first.to_double())
  v["lastEntry"] = Json::number(last.to_double())
  v.remove("unreadLine")
  v.remove("at")
  if l.unread > 0 && l.unread >= first && l.unread <= last {
    v["unreadLine"] = Json::number(l.unread.to_double())
    v["at"] = Json::number(l.unread.to_double())
  }
  v["asks"] = Json::array(l.asks.map(fn(s) { { "seq": Json::number(s.to_double()) } }))
  if l.asks.length() > 0 {
    v["askClear"] = Json::boolean(true)
  }
  Json::object(v)
}

///|
/// The long chat's made-up core over the fixture `mode`'s, read as the app's client asks it: what it is told before the
/// chat is asked (sfbase's chats_told_before, as @core.Client tells it) told first.
fn long_source(l : LongChat, mode? : String = "chat") -> Source {
  let base = fixture(mode)
  let answer = fn(f : () -> Unit) {
    l.held.push(fn() {
      @ui.came_from_outside()
      f()
    })
  }
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "chat" && !l.asked.contains("sub") {
        let topic = params.copy()
        topic["topic"] = Json::string("chat")
        for told in @sfbase.chats_told_before("chat", Json::object(topic)) {
          (base.call)(told.0, told.1, @sfbase.answer_unread)
          match told.1 {
            Object(p) =>
              match p.get("rows") {
                Some(Number(r, ..)) => {
                  l.asked.push("window \{r.to_int()}")
                  if l.unread == 0 {
                    l.first.set(long_count - r.to_int() + 1)
                  }
                }
                _ => ()
              }
            _ => ()
          }
        }
        l.asked.push("sub")
      }
      let got = base.topic(name, params).get().snapshot()
      guard name == "chat" && got.value is Some(v) else { return got }
      let value = long_value(v, l)
      { ..got, value: Some(value), version: l.first.get() * 1000 + l.last.get() }
    },
    call: fn(name, params, done) {
      match name {
        "chat.older" => {
          // (as many messages more as asked, else the core's page)
          let rows = match params {
            Object(p) if p.get("rows") is Some(Number(n, ..)) => n.to_int()
            _ => long_page
          }
          l.asked.push("older \{rows}")
          answer(fn() {
            l.first.set(long_max(1, l.first.get() - rows))
            done(Ok(Json::boolean(l.first.get() > 1)))
          })
        }
        "chat.newer" => {
          l.asked.push("newer")
          answer(fn() {
            l.last.set(long_min(long_count, l.last.get() + long_page))
            done(Ok(Json::boolean(true)))
          })
        }
        "chat.around" => {
          let seq = number(Some(params), "seq").to_int()
          l.asked.push("around \{seq}")
          answer(fn() {
            l.first.set(long_max(1, seq - long_page))
            l.last.set(long_min(long_count, seq + long_page - 1))
            done(Ok(Json::null()))
          })
        }
        // (what ⌘F finds: message 20's words, there alone)
        "chat.find" =>
          done(Ok({ "words": ["第20条"], "hits": [{ "seq": 20, "count": 1 }], "held": long_count, "of": long_count, "whole": true }))
        "chat.find.go" => done(Ok({ "at": { "seq": 20, "k": 0 }, "position": 1, "total": 1 }))
        _ => (base.call)(name, params, done)
      }
    },
  }
}

///|
/// A long chat that opens at its end (`unread`: about that message, unread), its asks.
fn long_chat(unread? : Int = 0, asks? : Array[Int] = [], notices? : Bool = false) -> LongChat {
  let at = if unread > 0 { unread } else { long_count - long_page + 1 }
  {
    first: @signals.signal(if unread > 0 { long_max(1, at - long_page) } else { at }),
    last: @signals.signal(if unread > 0 { long_min(long_count, at + long_page - 1) } else { long_count }),
    asked: [],
    held: [],
    unread,
    asks,
    notices,
  }
}

///|
fn long_max(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn long_min(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// The long chat's answers held so far given, between frames, as the core's come.
fn long_answered(l : LongChat) -> Unit {
  let now = l.held.copy()
  l.held.clear()
  for f in now {
    f()
  }
}

///|
/// A frame of `t`, and the long chat's answers given after it.
fn long_frame(t : @ui.Tester, l : LongChat) -> Unit {
  t.run_for(@ui.frame_period_default)
  long_answered(l)
}

///|
/// `ms` of frames, the long chat answering between them.
fn long_run(t : @ui.Tester, l : LongChat, ms : Double) -> Unit {
  let from = t.time()
  while t.time() - from < ms - 1.0e-6 {
    long_frame(t, l)
  }
}

///|
/// Whether message `n` of the long chat is drawn in the window's height `h` now (its number's words).
fn long_drawn(t : @ui.Tester, n : Int, h : Double) -> Bool {
  let said = "第\{n}条："
  t.words().iter().any(fn(w) { w.2 + w.4 > 0.0 && w.2 < h && w.5 > 0.0 && w.0.has_prefix(said) })
}

///|
/// The long chat's chat (s-c1 of the fixture's).
let long_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }

///|
/// The screens a chat is held on: its name, its window, its platform (小屏 a phone's, with a finger; 大屏 a desktop's,
/// with a mouse).
let long_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
/// How long a chat is let open before a test looks: its slide in, what it asks answered.
let long_opened_ms : Double = @ui.move_most_ms * 2.0

///|
/// How long the list is let be after a stroke of the finger or the wheel's turns: its glide comes to rest within it.
let long_rest_ms : Double = @ui.move_most_ms * 2.0

///|
/// The long chat opened on screen `s`.
fn long_open(l : LongChat, s : (String, Double, Double, Int), mode? : String = "chat") -> @ui.Tester {
  let (_, w, h, platform) = s
  new_run()
  let src = long_source(l, mode~)
  open_chat(long_ref)
  // (the window's height known as the chat is asked, as it is where a chat is opened in the app once its first frame
  // is laid out: one opened as the app starts, before that, opens on the core's untold page)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  long_run(t, l, long_opened_ms)
  t
}

///|
test "a chat's first ask on 小屏 and 大屏: how many of its last messages it opens on told before it, what fills the window at the least height a row has; nothing more asked while it sits at its end" {
  let said : Array[String] = []
  for notices in [false, true] {
    for s in long_screens {
      let l = long_chat(notices~)
      let t = long_open(l, s)
      let drawn = long_places(t.words(), s.2).length()
      said.push("\{s.0}\{if notices { " notices" } else { "" }}: \{@ui.list_text(l.asked)} held \{long_count - l.first.get() + 1}, drawn \{drawn}, bones \{t.bones_drawn()}")
    }
  }
  // (30 fill the window, notices joined at 38 points each too; at its end nothing more is asked, as it opens: the page
  // before only once the reader moves it off its end)
  assert_eq(said, [
    "小屏: [window 30, sub] held 30, drawn 10, bones 0",
    "大屏: [window 30, sub] held 30, drawn 11, bones 0",
    "小屏 notices: [window 30, sub] held 30, drawn 19, bones 0",
    "大屏 notices: [window 30, sub] held 30, drawn 18, bones 0",
  ])
}

///|
/// The heights of the long chat's rows drawn in `t`'s window `h` high, at rest: from the top of each message's words to
/// the next's (a row and the room over the next, the same room over each).
fn long_row_heights(t : @ui.Tester, h : Double) -> Array[Double] {
  let at = long_places(t.words(), h)
  let out : Array[Double] = []
  for n, y in at {
    match at.get(n + 1) {
      Some(next) => out.push(next - y)
      None => ()
    }
  }
  out
}

///|
test "a row the core counts is never shorter than the least a chat's first window is worked out by, a station's notices joined the shortest; a window of them fills the screen it is told for" {
  let said : Array[String] = []
  for s in long_screens {
    let l = long_chat()
    let t = long_open(l, s)
    let least = long_row_heights(t, s.2).fold(init=1.0e9, fn(a, h) { if h < a { h } else { a } })
    assert_true(least >= @sfbase.chat_row_least, msg="\{s.0}: a message \{least} high")
    let n = long_chat(notices=true)
    let t = long_open(n, s)
    let notice = long_row_heights(t, s.2).fold(init=1.0e9, fn(a, h) { if h < a { h } else { a } })
    assert_true(notice >= @sfbase.chat_row_least, msg="\{s.0}: a notice \{notice} high")
    let rows = @sfbase.chat_first_window(s.2)
    said.push("\{s.0}: message \{least.floor().to_int()}, notice \{notice.floor().to_int()}, told \{rows}")
    assert_true(rows.to_double() * notice >= s.2, msg="\{s.0}: \{rows} notices \{notice} high")
  }
  assert_eq(said, ["小屏: message 55, notice 38, told 30", "大屏: message 57, notice 38, told 30"])
}

///|
/// Where each of the long chat's messages drawn in the window's height `h` is, by its number (its words' top), of
/// `words` (a Tester's `words()`).
fn long_places(words : Array[(String, Double, Double, Double, Double, Double)], h : Double) -> Map[Int, Double] {
  let out : Map[Int, Double] = Map([])
  for w in words {
    guard w.2 + w.4 > 0.0 && w.2 < h && w.5 > 0.0 && w.0.has_prefix("第") else { continue }
    let digits = w.0.exact_view(start=1).to_owned()
    let mut n = 0
    let mut any = false
    for c in digits {
      guard c >= '0' && c <= '9' else { break }
      n = n * 10 + (c.to_int() - '0'.to_int())
      any = true
    }
    if any && !out.contains(n) {
      out[n] = w.2
    }
  }
  out
}

///|
test "a chat read back on 小屏 with a finger and on 大屏 with a mouse: a screen kept laid out above what shows, its messages there every frame, no bones, every row at its least too" {
  let faults : Array[String] = []
  let said : Array[String] = []
  let fastests : Array[Double] = []
  for notices in [false, true] {
    for s in long_screens {
      let (name, _, h, platform) = s
      let name = if notices { name + " notices" } else { name }
      let l = long_chat(notices~)
      let t = long_open(l, s)
      let frames = Ref(0)
      let fastest = Ref(0.0)
      let was : Ref[Map[Int, Double]] = Ref(long_places(t.words(), h))
      // (each frame: no bones, and while the core has more before it, the first message held not drawn: the top never
      // comes down empty; how far what shows moved since the frame before, the most of it kept)
      let look = fn() {
        frames.val += 1
        if t.bones_drawn() > 0 {
          faults.push("\{name} frame \{frames.val}: bones")
        }
        let now = long_places(t.words(), h)
        if l.first.get() > 1 && now.contains(l.first.get()) {
          faults.push("\{name} frame \{frames.val}: its first message of \{long_count - l.first.get() + 1} drawn with more before it")
        }
        let mut most = 0.0
        for n, y in now {
          match was.val.get(n) {
            Some(y0) => {
              let moved = (y - y0).abs()
              if moved > most {
                most = moved
              }
            }
            None => ()
          }
        }
        if most > fastest.val {
          fastest.val = most
        }
        was.val = now
      }
      // (the list at rest after a stroke: the time said, every frame of it looked at, never till it is seen to stand)
      let resting = fn(rest : Double) { t.time() - rest < long_rest_ms - 1.0e-6 }
      // (read back through two growths after it opened, what came as it opened aside)
      let olders = fn() { l.asked.filter(fn(a) { a.has_prefix("older") }).length() }
      let opened = olders()
      if platform == 2 {
        // strokes of a finger down the chat, 40 points a move (2400 points a second at 60 frames a second, 4800 at
        // 120), let go moving (a fling), the list at rest after each: every frame looked at, the core's answers given
        // between them
        for _ in 0..<12 {
          if olders() - opened >= 2 {
            break
          }
          t.hold_drag(195.0, 160.0, 195.0, 175.0, steps=1)
          long_answered(l)
          look()
          let mut y = 175.0
          while y < 640.0 {
            y += 40.0
            t.hold_move(195.0, y)
            long_answered(l)
            look()
          }
          t.release(195.0, y)
          long_answered(l)
          look()
          let rest = t.time()
          while resting(rest) {
            long_frame(t, l)
            look()
          }
        }
      } else {
        // the wheel of a trackpad over the chat, five turns of 30 points at one moment (each looked at), then the list
        // at rest, every frame of it looked at
        for _ in 0..<40 {
          if olders() - opened >= 2 {
            break
          }
          for _ in 0..<5 {
            t.wheel(800.0, 400.0, -30.0)
            long_answered(l)
            look()
          }
          let rest = t.time()
          while resting(rest) {
            long_frame(t, l)
            look()
          }
        }
      }
      said.push("\{name}: \{@ui.list_text(l.asked)} held \{long_count - l.first.get() + 1}")
      fastests.push(fastest.val)
    }
  }
  assert_eq(faults, [])
  assert_eq(fastests.map(fn(f) { f.round().to_int() }), [41, 30, 41, 30])
  // (20 more each time less than a screen was above what showed: 760 points at the least, while what shows moved 40.5
  // points a frame at the most under the finger and 30 a turn of the wheel, the core answering in a frame; read back
  // through two of them, from the first frame the list left its end: nothing asked while it sat there as it opened)
  assert_eq(said, [
    "小屏: [window 30, sub, older 20, older 20] held 70",
    "大屏: [window 30, sub, older 20, older 20] held 70",
    "小屏 notices: [window 30, sub, older 20, older 20, older 20] held 90",
    "大屏 notices: [window 30, sub, older 20, older 20] held 70",
  ])
}

///|
test "a chat opened at a message before the window it is told (a notification's): the pages before brought in till it is there, in view" {
  for s in long_screens {
    let l = long_chat()
    let (_, w, h, platform) = s
    new_run()
    let src = long_source(l)
    open_chat_at(long_ref, 20.0)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
      @sfbase.window_tall.val = h
    })
    for _ in 0..<6 {
      long_run(t, l, @ui.move_most_ms)
    }
    assert_true(l.first.get() <= 20, msg="\{s.0}: \{@ui.list_text(l.asked)}")
    assert_true(long_drawn(t, 20, h), msg="\{s.0}: \{Repr(t.words().map(fn(w) { w.0 }))}")
  }
}

///|
test "⌘F in a chat opened on its told window: a message found before it has the window moved about it, in view" {
  let l = long_chat()
  let t = long_open(l, long_screens[1])
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  long_run(t, l, @ui.move_most_ms)
  t.type_text("第20条")
  long_run(t, l, @sfpages.find_typing_ms)
  for _ in 0..<4 {
    long_run(t, l, @ui.move_most_ms)
  }
  assert_true(l.asked.contains("around 20"), msg=@ui.list_text(l.asked))
  assert_true(long_drawn(t, 20, 800.0), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}

///|
test "what waits to be decided before a chat's told window: the bell to it shows, and pressed, the pages before come in till its post is in view" {
  for s in long_screens {
    let l = long_chat(asks=[20])
    let t = long_open(l, s)
    let bell = @sf.t("web-main.chat.asks.go")
    t.click(Button, label=bell)
    for _ in 0..<6 {
      long_run(t, l, @ui.move_most_ms)
    }
    assert_true(l.first.get() <= 20, msg="\{s.0}: \{@ui.list_text(l.asked)}")
    assert_true(long_drawn(t, 20, s.2), msg="\{s.0}: \{Repr(t.words().map(fn(w) { w.0 }))}")
  }
}

///|
test "a chat with something unread further back than its told window opens at its unread line, as wide as the core's window about it" {
  for s in long_screens {
    let l = long_chat(unread=60)
    let t = long_open(l, s)
    assert_eq(l.first.get(), 10, msg=s.0)
    assert_true(t.find(@sf.t("web-main.chat.unreadLine")) is Some(_), msg="\{s.0}: \{Repr(t.words().map(fn(w) { w.0 }))}")
    assert_true(long_drawn(t, 60, s.2), msg="\{s.0}: \{Repr(t.words().map(fn(w) { w.0 }))}")
  }
}

///|
test "对话目录 of a chat opened on its told window: a row said before it pressed, the list goes to its message" {
  new_run()
  let mode = "chat-outline-away"
  let base = fixture(mode)
  let asked : Array[String] = []
  // (what is told before the chat, as the app's client tells it)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "chat" && !asked.contains("sub") {
        let topic = params.copy()
        topic["topic"] = Json::string("chat")
        for told in @sfbase.chats_told_before("chat", Json::object(topic)) {
          asked.push(told.0)
          (base.call)(told.0, told.1, @sfbase.answer_unread)
        }
        asked.push("sub")
      }
      (base.topic_read)(name, params)
    },
  }
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, begun=fn() {
    @sfbase.window_tall.val = 844.0
  })
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_eq(asked, ["chat.window", "sub"])
  t.click(Button, label="对话目录")
  t.run_for(@ui.move_most_ms)
  // a row above the reader's: 设计说头图周一给 (Ana's, 星期日 17:30, seq 18), not in the list now
  let row = "设计说头图周一给，到时候我直接换上去，不用再走一遍审核流程了吧？"
  assert_true(t.find(row) is Some(_))
  t.tap_text(row)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(row) is Some(_))
  // (lit as it is gone to)
  assert_true(lit_over(t, row) > 0.0)
}

///|
test "a chat read back a step at a time inside the rows it shows, a screen above them: no row built or laid out for a step, nothing more asked" {
  let said : Array[String] = []
  // (小屏, a finger's: 大屏's wheel steps lay its rows out on their own, as much with the rows' rule from before this
  // one, first in view among the first three: the list moved by its stick to the end and its bar's watch)
  for s in [long_screens[0]] {
    let (name, _, _, platform) = s
    let x = if platform == 2 { 195.0 } else { 800.0 }
    let l = long_chat()
    let t = long_open(l, s)
    t.check_looks(false)
    t.set_rows_on_pixels(true)
    // (read back some way, its growths come and at rest)
    for _ in 0..<4 {
      if platform == 2 {
        t.drag(195.0, 300.0, 195.0, 600.0, steps=20)
      } else {
        for _ in 0..<10 {
          t.wheel(x, 400.0, -30.0)
        }
      }
      long_run(t, l, long_rest_ms)
    }
    // (a finger on it, moving it: what its moving sets off built once; then steps of 3 points under the finger, each
    // within the rows it shows)
    t.hold_drag(x, 300.0, x, 320.0, steps=4)
    t.hold_move(x, 323.0)
    long_answered(l)
    let asked = l.asked.length()
    let mut laid = 0
    let mut painted = ""
    let mut y = 323.0
    for _ in 0..<3 {
      y += 3.0
      t.hold_move(x, y)
      long_answered(l)
      laid += t.frame_perf().laid
      painted = t.painted_why()
    }
    t.release(x, y)
    long_run(t, l, long_rest_ms)
    said.push("\{name}: away \{l.first.get() < long_count - 30}, laid \{laid}, asked \{l.asked.length() - asked}, \{painted}")
  }
  assert_eq(said, ["小屏: away true, laid 0, asked 0, a list scrolled without changing its rows"])
}

///|
test "a chat whose window grows taller than its first window fills, a station's notices joined: the page before asked while what it lays out does not fill the window, never a hole" {
  // (30 notices, 38 points each, are 1140 points, told for an 800 high window: grown to 1600, the list shows less than
  // it could and, at its end and shorter than its window, can not be moved off it; what does not fill the window asks
  // too, by the same Bool, chat_list.mbt chat_short_above)
  let l = long_chat(notices=true)
  let t = long_open(l, long_screens[1])
  let before = @ui.list_text(l.asked)
  t.resize(1280.0, 1600.0)
  long_run(t, l, long_opened_ms)
  let drawn = long_places(t.words(), 1600.0)
  let first = l.first.get()
  assert_eq(
    "\{before} then \{@ui.list_text(l.asked)} held \{long_count - first + 1}, its first drawn \{drawn.contains(first)}, bones \{t.bones_drawn()}",
    "[window 30, sub] then [window 30, sub, older 20] held 50, its first drawn false, bones 0",
  )
}

///|
test "a chat gone to a message with less than a screen above it and more in the core: nothing asked while it stands there; the first step back (a finger on 小屏, the wheel on 大屏) asks the page before; read on by a finger, its top never shown with more before it" {
  let said : Array[String] = []
  let faults : Array[String] = []
  for s in long_screens {
    let (name, _, h, platform) = s
    let l = long_chat()
    let t = long_open(l, s)
    let olders = fn() { l.asked.filter(fn(a) { a.has_prefix("older") }).length() }
    // (the window's third message, two above it: less than a screen, 170 more in the core; gone to as a link to it
    // does, from outside the frames)
    let to = l.first.get() + 2
    @sfbase.go_to(long_ref, to.to_double())
    @ui.came_from_outside()
    long_run(t, l, long_rest_ms)
    // (standing where the go-to put it: nothing asked; the reader's first step back asks)
    let standing = olders()
    if platform == 2 {
      t.drag(195.0, 300.0, 195.0, 340.0, steps=4)
    } else {
      t.wheel(800.0, 400.0, -30.0)
    }
    long_run(t, l, long_rest_ms)
    let stepped = olders()
    let look = fn(when : String) {
      if l.first.get() > 1 && long_places(t.words(), h).contains(l.first.get()) {
        faults.push("\{name} \{when}: its first message of \{long_count - l.first.get() + 1} drawn with more before it")
      }
    }
    look("gone to")
    // (read on by a finger, on 小屏; 大屏's reading back by the wheel is the test of the window's growths above)
    for k in 0..<(if platform == 2 { 3 } else { 0 }) {
      t.drag(195.0, 300.0, 195.0, 600.0, steps=20)
      let rest = t.time()
      while t.time() - rest < long_rest_ms - 1.0e-6 {
        long_frame(t, l)
        look("stroke \{k}")
      }
    }
    said.push("\{name}: \{to} reached \{long_drawn(t, to, h) || l.first.get() < to}, the page before asked \{standing} while it stands, \{stepped} at the first step back, \{olders()} read back")
  }
  assert_eq(faults, [])
  // (nothing asked from where the app put it; the reader's first step from there asks, and again each time less than a
  // screen is above what shows: 小屏's first stroke of 40 points twice, the first page leaving less than a screen still)
  assert_eq(said, [
    "小屏: 173 reached true, the page before asked 0 while it stands, 2 at the first step back, 2 read back",
    "大屏: 173 reached true, the page before asked 0 while it stands, 1 at the first step back, 1 read back",
  ])
}

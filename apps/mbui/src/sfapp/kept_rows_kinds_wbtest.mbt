// Every kind of message the fixtures hold, with its rows kept (mbui's kept_nodes.mbt): left still, what goes on in them
// as time goes (a ring stepping round an agent at work, a spinner under a message waiting, a clock's seconds, words
// coming after a moment), and scrolled, what comes into view and what reads the layout (a table's width, a picture's,
// the list's end for the way to the newest), drawn at each moment as building every row draws it.

///|
/// The fixtures' chats, each with kinds of messages of its own.
let kept_rows_kinds : Array[String] = [
  "chat", "chat-md", "chat-viz", "chat-file-links", "chat-table-images", "chat-peeks", "chat-cards", "chat-agent-card",
  "chat-attach", "chat-attach-pic", "chat-download", "chat-failed", "chat-letters", "chat-need", "chat-quote", "chat-screens",
  "chat-sending", "chat-station-file", "chat-station-files", "chat-station-ref", "chat-station-tag", "chat-uploading",
  "chat-vault", "chat-working", "chat-jobs", "chat-publish", "chat-flash", "chat-update", "chat-answering", "chat-agent",
  "chat-done",
]

///|
/// How far apart the moments are that a chat left still is looked at (no step of a clock's falls on one).
let kept_rows_still_ms : Double = 70.0

///|
/// Chat `mode` opened `w` by `h`: on 小屏 (a phone's width), on 中屏's tape (the page brought over the sidebar), or on
/// 大屏 (a desktop's window, 1000 wide or more: with a mouse).
fn kept_rows_open(mode : String, w : Double, h : Double) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let large = w >= 1000.0
  // (two ways of drawing compared: the corner rule is held where the chats' pictures are tested)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=if large { 0 } else { 2 }, corners_held=false)
  let tape = w > 600.0 && !large
  if tape {
    say_room(t, "medium", "medium")
  }
  t.run_for(@ui.move_most_ms)
  if tape {
    t.tap(w - @sfdesk.tape_shows / 2.0, h / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// Chat `mode` opened and left as it is: what is drawn at each moment after (its instances, kept_rows_inst), the rows
/// drawn again where they can be (`again`) or built every frame; `a11y`: something reading the widgets out.
fn kept_rows_kind(mode : String, again : Bool, w : Double, h : Double, a11y? : Bool = false) -> Array[Array[String]] {
  let t = kept_rows_open(mode, w, h)
  t.keep_parts(true)
  t.drawn_again(again)
  t.set_a11y(a11y)
  t.said() |> ignore
  let out = []
  for _ in 0..<24 {
    t.run_for(kept_rows_still_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_read_out(t, a11y) + kept_rows_said(t))
  }
  out
}

///|
/// Chat `mode` dragged back and let go, then dragged on: what is drawn at each moment after, the rows drawn again where
/// they can be (`again`) or built every frame.
fn kept_rows_kind_scrolled(mode : String, again : Bool, w : Double, h : Double) -> Array[Array[String]] {
  let t = kept_rows_open(mode, w, h)
  t.keep_parts(true)
  t.drawn_again(again)
  t.said() |> ignore
  let out = []
  let x = w * 0.7
  t.drag(x, h * 0.3, x, h * 0.7, steps=8)
  for _ in 0..<5 {
    t.run_for(kept_rows_step_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_said(t))
  }
  t.drag(x, h * 0.7, x, h * 0.35, steps=8)
  for _ in 0..<5 {
    t.run_for(kept_rows_step_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_said(t))
  }
  out
}

///|
/// Each chat drawn the same with its rows drawn again and built (`scrolled`, or left still): the chats that are not,
/// said with where.
fn kept_rows_kinds_apart(w : Double, h : Double, a11y? : Bool = false, scrolled? : Bool = false) -> Array[String] {
  let apart = []
  for mode in kept_rows_kinds {
    let kept = if scrolled {
      kept_rows_kind_scrolled(mode, true, w, h)
    } else {
      kept_rows_kind(mode, true, w, h, a11y~)
    }
    let built = if scrolled {
      kept_rows_kind_scrolled(mode, false, w, h)
    } else {
      kept_rows_kind(mode, false, w, h, a11y~)
    }
    let mut said = false
    for i in 0..<kept.length() {
      if said {
        break
      }
      let a = kept[i]
      let b = built[i]
      for j in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
        if a[j] != b[j] {
          apart.push("\{mode} moment \{i} instance \{j}:\n  again \{a[j]}\n  built \{b[j]}")
          said = true
          break
        }
      }
      if !said && a.length() != b.length() {
        apart.push("\{mode} moment \{i}: \{a.length()} instances drawn again, \{b.length()} built")
        said = true
      }
    }
  }
  apart
}

///|
test "every kind of message left still on 小屏: what goes on in it drawn as building it draws it" {
  let apart = kept_rows_kinds_apart(390.0, 844.0)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
test "every kind of message left still on 中屏's tape: what goes on in it drawn as building it draws it" {
  let apart = kept_rows_kinds_apart(720.0, 800.0)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
test "every kind of message left still on 中屏's tape, read out: what goes on in it drawn as building it draws it" {
  let apart = kept_rows_kinds_apart(720.0, 800.0, a11y=true)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
test "every kind of message scrolled on 小屏: drawn again as building it draws it" {
  let apart = kept_rows_kinds_apart(390.0, 844.0, scrolled=true)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
test "every kind of message scrolled on 中屏's tape: drawn again as building it draws it" {
  let apart = kept_rows_kinds_apart(720.0, 800.0, scrolled=true)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
test "every kind of message left still on 大屏: what goes on in it drawn as building it draws it" {
  let apart = kept_rows_kinds_apart(1280.0, 800.0)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
test "every kind of message scrolled on 大屏: drawn again as building it draws it" {
  let apart = kept_rows_kinds_apart(1280.0, 800.0, scrolled=true)
  if apart.length() > 0 {
    fail(apart.join("\n"))
  }
}

///|
/// Words sent in chat `mode` opened `w` by `h` (kept_rows_open), then left: what is drawn at each moment from the send
/// on (the words flying to their row, the rows above moving up, an avatar held at the list's top as its message goes
/// up past it), the rows drawn again where they can be (`again`) or built every frame.
fn kept_rows_sent(mode : String, again : Bool, w : Double, h : Double) -> (Array[Array[String]], Int) {
  let t = kept_rows_open(mode, w, h)
  t.keep_parts(true)
  t.drawn_again(again)
  t.tap_text("发消息")
  t.type_text("刚发的这一句")
  t.said() |> ignore
  tap_send(t)
  let out = []
  let mut kept = 0
  for _ in 0..<12 {
    t.run_for(kept_rows_still_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_said(t))
    kept = kept + t.rows_kept()
  }
  (out, kept)
}

///|
/// Words sent in chat `mode` `w` by `h`: drawn the same with the rows kept as their nodes as built.
fn kept_rows_sent_same(mode : String, w : Double, h : Double) -> Unit raise {
  let (kept, _) = kept_rows_sent(mode, true, w, h)
  let (built, _) = kept_rows_sent(mode, false, w, h)
  kept_rows_same(kept, built)
}

///|
test "words sent on 大屏: the messages drawn again as building them draws them, the words flying to their row and the rows above moving up" {
  kept_rows_sent_same("chat", 1280.0, 800.0)
}

///|
test "words sent in a long chat on 小屏: drawn again as building them draws them, what is held at the top too" {
  kept_rows_sent_same("chat-long", 390.0, 844.0)
}

///|
test "words sent in a long chat on 中屏's tape: drawn again as building them draws them, what is held at the top too" {
  kept_rows_sent_same("chat-long", 720.0, 800.0)
}

///|
test "words sent in a long chat on 大屏: drawn again as building them draws them, what is held at the top too" {
  kept_rows_sent_same("chat-long", 1280.0, 800.0)
}

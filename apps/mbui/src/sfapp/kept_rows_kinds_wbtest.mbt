// Every kind of message the fixtures hold, with its rows kept (mbui's kept_rows.mbt): left still, what goes on in them
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
]

///|
/// How far apart the moments are that a chat left still is looked at (no step of a clock's falls on one).
let kept_rows_still_ms : Double = 70.0

///|
/// Chat `mode` opened and left as it is: what is drawn at each moment after (its instances, kept_rows_inst), the rows
/// drawn again where they can be (`again`) or built every frame; `a11y`: something reading the widgets out.
fn kept_rows_kind(mode : String, again : Bool, w : Double, h : Double, a11y? : Bool = false) -> Array[Array[String]] {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // (two ways of drawing compared: the corner rule is held where the chats' pictures are tested)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=2, corners_held=false)
  if w > 600.0 {
    say_room(t, "medium", "medium")
  }
  t.run_for(@ui.nav_push_ms)
  if w > 600.0 {
    t.tap(w - @sfdesk.tape_shows / 2.0, h / 2.0)
    t.run_for(@sfdesk.side_move_ms)
  }
  t.keep_parts(true)
  t.drawn_again(again)
  t.set_a11y(a11y)
  let out = []
  for _ in 0..<24 {
    t.run_for(kept_rows_still_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_read_out(t, a11y))
  }
  out
}

///|
/// Chat `mode` dragged back and let go, then dragged on: what is drawn at each moment after, the rows drawn again where
/// they can be (`again`) or built every frame.
fn kept_rows_kind_scrolled(mode : String, again : Bool, w : Double, h : Double) -> Array[Array[String]] {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=2, corners_held=false)
  if w > 600.0 {
    say_room(t, "medium", "medium")
  }
  t.run_for(@ui.nav_push_ms)
  if w > 600.0 {
    t.tap(w - @sfdesk.tape_shows / 2.0, h / 2.0)
    t.run_for(@sfdesk.side_move_ms)
  }
  t.keep_parts(true)
  t.drawn_again(again)
  let out = []
  let x = w * 0.7
  t.drag(x, h * 0.3, x, h * 0.7, steps=8)
  for _ in 0..<5 {
    t.run_for(kept_rows_step_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst))
  }
  t.drag(x, h * 0.7, x, h * 0.35, steps=8)
  for _ in 0..<5 {
    t.run_for(kept_rows_step_ms)
    out.push(drawn_from(t, -1000.0).map(kept_rows_inst))
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

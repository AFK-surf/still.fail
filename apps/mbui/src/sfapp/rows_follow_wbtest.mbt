// A chat's rows as the reader scrolls away from its end and back while what is in it changes (a message coming while
// away and while at the end, one leaving and coming back by the same key, one waiting to be sent): what is drawn at
// each moment is what working the rows out anew each frame draws, at 60 Hz and 120 Hz and at the Tester's own frames (no
// display period: those due, owed and of each drag step). Each run is compared with its own anew run, not the runs with each
// other.

///|
/// How long after each step the list is looked at.
let rows_follow_step_ms : Double = 400.0

///|
/// The steps, each moment's drawing after it; the rows each frame made of the chat's entries as the last frame left
/// them where they can be (`made`), or worked out anew every frame; frames every `period` ms (at 0 the
/// Tester's own: those due, owed and of each drag step).
fn rows_follow_run(made : Bool, period : Double) -> Array[Array[String]] {
  new_run()
  let base = fixture("chat")
  let messages = Array::makei(60, fn(i) { said(i + 1, "第 \{i + 1} 句") })
  let outbox : Array[Json] = []
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "chat" && params.get("session") == Some(Json::string("s-c1")) {
        changes.get() |> ignore
        let chat : Json = {
          "title": "整理发布清单",
          "thread": { "id": 1 },
          "messages": Json::array(messages.copy()),
          "outbox": Json::array(outbox.copy()),
          "agents": [],
          "people": [],
        }
        { value: Some(chat), error: None, version: version.val }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let changed = fn() {
    version.val += 1
    changes.set(version.val)
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(
    fn(c) {
      if !made {
        for _, rd in @sfbase.readings {
          rd.rows_made = None
        }
      }
      view(c, src)
    },
    tree=app_tree(src),
    w=390.0,
    h=844.0,
    platform=2,
    corners_held=false,
  )
  if period > 0.0 {
    t.set_frame_period(period)
  }
  t.run_for(@ui.move_most_ms)
  let out : Array[Array[String]] = []
  let look = fn() {
    t.run_for(rows_follow_step_ms)
    out.push(drawn_from(t, -1000.0))
  }
  // (a finger pulling the list toward its start, and back to its end)
  let away = fn() {
    t.drag(195.0, 250.0, 195.0, 700.0, steps=8)
    look()
  }
  let back = fn() {
    for _ in 0..<3 {
      t.drag(195.0, 700.0, 195.0, 150.0, steps=8)
      t.run_for(rows_follow_step_ms)
    }
    look()
  }
  look()
  away()
  // a message coming while the reader is away from the end
  messages.push(said(61, "离开末尾时来的一句"))
  changed()
  look()
  back()
  // one coming at the end: in at once, its room opening
  messages.push(said(62, "在末尾时来的一句"))
  changed()
  t.run_for(@sf.enter_ms / 2.0)
  out.push(drawn_from(t, -1000.0))
  look()
  away()
  back()
  // one leaving, and coming back by the same key
  let gone = messages.remove(58)
  changed()
  look()
  away()
  messages.insert(58, gone)
  changed()
  look()
  back()
  // one waiting to be sent, then sent
  outbox.push({ "id": "pending-1", "text": "正在发送的一句" })
  changed()
  look()
  away()
  back()
  outbox.clear()
  messages.push(said(63, "正在发送的一句"))
  changed()
  look()
  away()
  back()
  out
}

///|
/// Each frame rate's run with the rows made as the last frame left them, and worked out anew, drawing the same.
fn rows_follow_same(period : Double) -> Unit raise {
  let kept = rows_follow_run(true, period)
  let anew = rows_follow_run(false, period)
  kept_rows_same(kept, anew)
}

///|
test "a chat scrolled away from its end and back as its rows change, at the Tester's own frames: drawn as working them out anew draws them" {
  rows_follow_same(0.0)
}

///|
test "a chat scrolled away from its end and back as its rows change, at 60 Hz: drawn as working them out anew draws them" {
  rows_follow_same(1000.0 / 60.0)
}

///|
test "a chat scrolled away from its end and back as its rows change, at 120 Hz: drawn as working them out anew draws them" {
  rows_follow_same(1000.0 / 120.0)
}

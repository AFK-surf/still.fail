// The two sends in the reported recording: the second while the first answer is pending. Watch the actual
// drawn words every display frame, including when each answer starts; a completed bubble must not jump.

///|
// Input times from the reported recording, not a wait for the app to become idle.
let rows_record_open_ms : Double = 600.0

///|
let rows_record_second_send_ms : Double = 1000.0

///|
test "two sends before the answers: the first bubble moves continuously as each answer takes its place" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, words_over_held=false)
  t.run_for(rows_record_open_ms)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":34,\"left\":0,\"right\":0}}")
  t.run_for(rows_record_open_ms)
  t.tap_text("发消息")
  let first = "看一下列表"
  t.type_text(first)
  tap_send(t)
  t.run_for(rows_record_second_send_ms)
  t.tap_text("发消息")
  t.type_text("帮我看一下登录按钮在深色模式下的颜色是不是不对，还有注册页输入框的边框也要再核对一遍")
  tap_send(t)
  let em = emits_of("ws1/st1\u{1}s-c1")
  let steps : Array[String] = []
  let mut before : Double? = None
  let mut last : Double? = None
  let until = t.time() + fix_answer_ms + 2.0 * emit_all_ms()
  while t.time() < until {
    t.frame()
    let now = t.words().iter().find_first(fn(w) { w.0 == first }).map(fn(w) { w.2 })
    assert_true(now is Some(_), msg="the first bubble disappeared at \{t.time()}")
    match (before, last, now) {
      (Some(a), Some(b), Some(n)) => {
        let (v0, v1) = (b - a, n - b)
        let off = ((v1 - v0) / 2.0).abs()
        if off > way_step_most && off > dmax(v0.abs(), v1.abs()) / 2.0 {
          let words = sent_words_node(first)
          let scroll = words.scroll_holding().unwrap()
          steps.push("at \{t.time()} y=\{(a,b,n)} scroll=\{scroll.at(words.tree)}/\{scroll.most()} pose=\{em.current.map(fn(x) { (x.seq, x.pose) })}")
        }
      }
      _ => ()
    }
    before = last
    last = now
  }
  assert_eq(steps, [])
  assert_true(t.words_over_frames().is_empty(), msg="\{t.words_over_frames()}")
}

///|
test "a new chat's first bubble stays continuous through the answer and the activity leaving" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, words_over_held=false)
  t.run_for(rows_record_open_ms)
  let words = "把发布说明写一下"
  new_chat_sent(t, words) |> ignore
  let r = match app.nav.top() { Chat(r) => r; _ => fail("not the new chat") }
  let em = emits_of(r.station + "\u{1}" + r.session)
  let steps : Array[String] = []
  let mut before : Double? = None
  let mut last : Double? = None
  let until = t.time() + fix_answer_ms + emit_all_ms() + linger_ms + @ui.move_most_ms
  while t.time() < until {
    t.frame()
    let now = t.words().iter().find_first(fn(w) { w.0 == words }).map(fn(w) { w.2 })
    assert_true(now is Some(_), msg="the first bubble disappeared at \{t.time()}")
    match (before, last, now) {
      (Some(a), Some(b), Some(n)) => {
        let (v0, v1) = (b - a, n - b)
        let off = ((v1 - v0) / 2.0).abs()
        if off > way_step_most && off > dmax(v0.abs(), v1.abs()) / 2.0 {
          steps.push("at \{t.time()} y=\{(a,b,n)} pose=\{em.current.map(fn(x) { (x.seq, x.pose) })}")
        }
      }
      _ => ()
    }
    before = last
    last = now
  }
  assert_eq(steps, [])
  assert_true(t.words_over_frames().is_empty(), msg="\{t.words_over_frames()}")
}

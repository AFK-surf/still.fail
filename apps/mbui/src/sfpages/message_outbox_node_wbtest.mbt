// What was sent from here and is not in the chat yet, as nodes (message_outbox_node.mbt), set beside the old view's
// (chat_rows.mbt outbox_row out of a list) on the same fixture: sending (before 正在发送 shows and after, what it waits
// on with how far), sent, followed, not sent (重试, or refused: 编辑), one being sent again, one failed again, with a
// file; wide and narrow, at 1.3, under a mouse; and what each press asks of the core. Harness: message_decision_node's
// (dec_old, dec_new, dec_src).

///|
/// The fixture's entry of the outbox: `state` (sending, sent, failed); refused as it is (`refused`); why; what it waits
/// on and how far; followed by the viewer's next; with a file, or a picture 800 × 600 (`picture`); quoting `quotes`
/// (as the core gives them).
fn out_entry(
  state : String,
  refused? : Bool = false,
  error? : String = "",
  waits? : String = "",
  progress? : Double,
  followed? : Bool = false,
  file? : Bool = false,
  picture? : Bool = false,
  quotes? : Array[Json] = [],
) -> Outgoing {
  let o : Map[String, Json] = {
    "id": "o-1",
    "text": "这条还在路上，晚点再看结果",
    "state": Json::string(state),
    "final": Json::boolean(refused),
    "error": Json::string(error),
    "waits": Json::string(waits),
    "followed": Json::boolean(followed),
    "createdAt": 0,
    "time": { "createdAt": { "at": 0, "ago": "刚刚", "full": "10/19 06:40:00", "until": "", "past": true } },
  }
  match progress {
    Some(p) => o["progress"] = Json::number(p)
    None => ()
  }
  if file {
    o["attachments"] = [{ "name": "发布说明.pdf", "path": "/tmp/发布说明.pdf", "size": 24680 }]
  }
  if picture {
    o["attachments"] = [{ "name": "here.png", "path": "/tmp/here.png", "size": 24680, "width": 800, "height": 600 }]
  }
  if quotes.length() > 0 {
    o["quotes"] = Json::array(quotes)
  }
  let view = @sfbase.chat_view_made({ "title": "发布", "messages": [], "outbox": [Json::object(o)] })
  view.outbox[0]
}

///|
/// The core's doing with `call` (chat.retry, chat.discard) for the fixture's entry under way, or failed saying why.
fn out_doing(call : String, failed? : String = "") -> Json {
  let d : Map[String, Json] = {
    "call": Json::string(call),
    "stage": Json::string(if failed == "" { "running" } else { "failed" }),
    "params": { "station": "ws1/st1", "id": "o-1" },
  }
  if failed != "" {
    d["error"] = Json::string(failed)
  }
  { "doing": [Json::object(d)] }
}

///|
/// The fixture's states by name, each with what the core's doing says.
fn out_cases() -> Array[(String, Outgoing, Json?)] {
  [
    ("sending", out_entry("sending"), None),
    ("waiting on its files", out_entry("sending", waits="正在上传 2 个文件", progress=0.4), None),
    ("sent", out_entry("sent"), None),
    ("followed", out_entry("sent", followed=true), None),
    ("not sent", out_entry("failed", error="连不上 Willow"), None),
    ("refused", out_entry("failed", refused=true, error="Willow 上没有这个文件"), None),
    ("sent again", out_entry("failed", error="连不上 Willow"), Some(out_doing("chat.retry"))),
    ("failed again", out_entry("failed", error="连不上 Willow"), Some(out_doing("chat.retry", failed="还是连不上"))),
    ("with a file", out_entry("sent", file=true), None),
  ]
}

///|
/// The entry as the old view draws it in its row (outbox_row, out of a list).
fn out_old(w : Double, src : Source, o : Outgoing, platform? : Int = 0) -> @ui.Tester {
  dec_old(w, dec_view(), platform~, fn(c, here) {
    row_box(c, row_side(w), 0.0, fn() { outbox_row(c, src, here, o) }) |> ignore
  })
}

///|
/// The same as the nodes draw it (outbox_said_node), `o` as it changes, sent at the start of the run.
fn out_new(w : Double, src : Source, o : () -> Outgoing, view? : () -> ChatView = fn() { dec_view() }, platform? : Int = 0) -> @ui.Tester {
  dec_new(w, view, platform~, fn(f, here) {
    let since = f.cause_at()
    outbox_said_node(f, src, here, "o:o-1", fn() { row_side(w) }, fn() { 0.0 }, o, fn() { since }) |> ignore
  })
}

///|
test "what was sent from here, made once as nodes, is drawn as the old view drew it: sending, waiting on its files, sent, followed, not sent, refused, sent again, failed again, with a file; wide and narrow, at 1.3" {
  for c in out_cases() {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      let old = out_old(w, dec_src(@signals.signal(c.2), []), c.1)
      old.run_for(sending_shows_ms)
      let was = head_drawn(old)
      let t = out_new(w, dec_src(@signals.signal(c.2), []), fn() { c.1 })
      t.run_for(sending_shows_ms)
      assert_eq(head_drawn(t), was, msg=at)
      dec_audit(t, at)
    }
  }
  for k in [0, 4] {
    let c = out_cases()[k]
    let old = out_old(390.0, dec_src(@signals.signal(c.2), []), c.1)
    old.set_font_scale(1.3)
    old.run_for(sending_shows_ms)
    let was = head_drawn(old)
    let t = out_new(390.0, dec_src(@signals.signal(c.2), []), fn() { c.1 })
    t.set_font_scale(1.3)
    t.run_for(sending_shows_ms)
    assert_eq(head_drawn(t), was, msg=c.0 + " at 1.3")
    dec_audit(t, c.0 + " at 1.3")
  }
}

///|
test "正在发送 is not seen before it has been on its way sending_shows_ms, as the old view's" {
  let o = out_entry("sending")
  let old = out_old(760.0, dec_src(@signals.signal(None), []), o)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = out_new(760.0, dec_src(@signals.signal(None), []), fn() { o })
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was)
  dec_audit(t, "before")
}

///|
test "under a mouse, as the old view's: 重试 on the hover ground in the text's ink" {
  let o = out_entry("failed", error="连不上 Willow")
  let old = out_old(760.0, dec_src(@signals.signal(None), []), o)
  old.run_for(@ui.move_most_ms)
  let (x, y, w, h) = old.rect_of(@sf.t("common.retry")).unwrap()
  old.move_to(x + w / 2.0, y + h / 2.0)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = out_new(760.0, dec_src(@signals.signal(None), []), fn() { o })
  t.run_for(@ui.move_most_ms)
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was)
  dec_audit(t, "under a mouse")
}

///|
test "not sent: 重试 asks the core to send it again and 删除 to drop it, by the chat's thread, felt; while one is done none is pressed; the station not reached, 重试 is not pressed, 删除 is" {
  let calls : Array[(String, Json)] = []
  let doing : @signals.Signal[Json?] = @signals.signal(None)
  let view = @signals.signal(dec_view())
  let t = out_new(760.0, dec_src(doing, calls), fn() { out_entry("failed", error="连不上 Willow") }, view=fn() {
    view.get()
  })
  t.run_for(@ui.move_most_ms)
  let felt = t.haptics().length()
  t.click(Button, label=@sf.t("common.retry"))
  t.run_for(@ui.move_most_ms)
  let named_ = fn(n : String) { calls.filter(fn(c) { c.0 == n }) }
  assert_eq(named_("chat.retry").length(), 1)
  let p = Some(named_("chat.retry")[0].1)
  assert_eq(text(p, "id"), "o-1")
  assert_eq(number(p, "thread"), 7.0)
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(t.haptics().get(felt), Some(@ui.Confirm))
  // being sent again, as the core says: turning, nothing pressed
  doing.set(Some(out_doing("chat.retry")))
  t.run_for(@ui.move_most_ms)
  assert_true(t.get(Button, label=@sf.t("common.retry")).disabled)
  assert_true(t.get(Button, label=@sf.t("common.delete")).disabled)
  assert_true(t.drawn_lines().length() > 0)
  dec_audit(t, "being sent again")
  // its station not reached
  doing.set(None)
  view.set(@sfbase.chat_view_made({ "title": "发布", "messages": [], "thread": { "id": 7 }, "offline": true }))
  t.run_for(@ui.move_most_ms)
  assert_true(t.get(Button, label=@sf.t("common.retry")).disabled)
  assert_false(t.get(Button, label=@sf.t("common.delete")).disabled)
  t.click(Button, label=@sf.t("common.delete"))
  t.run_for(@ui.move_most_ms)
  assert_eq(named_("chat.discard").length(), 1)
  dec_audit(t, "offline")
}

///|
test "refused as it is: 编辑 puts its words back in the composer and drops it" {
  let calls : Array[(String, Json)] = []
  let src = dec_src(@signals.signal(None), calls)
  let t = out_new(760.0, src, fn() { out_entry("failed", refused=true, error="Willow 上没有这个文件") })
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label=@sf.t("common.retry")) is None)
  t.click(Button, label=@sf.t("common.edit"))
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.filter(fn(c) { c.0 == "chat.discard" }).length(), 1)
  assert_eq(@sfbase.writing(src, "ws1/st1:s1").text.get(), "这条还在路上，晚点再看结果")
  dec_audit(t, "edited")
}

///|
test "the station takes it: 正在发送 in its time's place; not sent after all, 未发送 in their place" {
  let o = @signals.signal(out_entry("sending"))
  let t = out_new(760.0, dec_src(@signals.signal(None), []), fn() { o.get() })
  t.run_for(sending_shows_ms)
  assert_true(t.find(@sf.t("web-main.chat.sending")) is Some(_))
  o.set(out_entry("sent"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-main.chat.sending")) is None)
  assert_true(t.find("刚刚") is Some(_))
  o.set(out_entry("failed", error="连不上 Willow"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("刚刚") is None)
  assert_true(t.find(@sf.t("web-main.chat.unsent")) is Some(_))
  dec_audit(t, "failed")
}


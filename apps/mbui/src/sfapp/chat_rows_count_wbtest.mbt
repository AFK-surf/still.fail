// A chat's messages read by index (sfbase ChatMessages over stillfail/rows' TopicList, mbui docs/retained.md rule 12):
// one message come costs the chat page the same with 30 messages and with 3000. Counted: the messages made of their
// JSON, and what the list did (found, copied, put together whole: TopicList::work, to_json's included).

///|
/// A message `seq` of the core's.
fn said_json(seq : Int) -> Json {
  {
    "seq": Json::number(seq.to_double()),
    "thread": Json::number(1.0),
    "ts": Json::string("t\{seq}"),
    "authorKind": Json::string("person"),
    "author": Json::string("alice@example.test"),
    "text": Json::string("第 \{seq} 句"),
  }
}

///|
/// What a message come costs the page of a chat that holds `n`: messages made, the list's work.
fn one_come_costs(n : Int) -> (Int, Int, Int, Int) raise {
  let all : Json = { "messages": Json::array(Array::makei(n, fn(i) { said_json(i + 1) })) }
  let rows = @rows.TopicList::new(["messages"], ["seq", "outgoing"], Some(all))
  // (the rest of the chat's value, its messages left out as the core's source gives it: Sub::rest)
  let rest : Json = { "title": Json::string("对话"), "thread": { "id": Json::number(1.0) }, "messages": Json::null() }
  let version = Ref(1)
  let changes = @signals.signal(1)
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        changes.get() |> ignore
        { value: Some(rest), error: None, version: version.val }
      } else {
        (base.topic)(name, params)
      }
    },
    list: fn(name, _, _, _) { if name == "chat" { Some(rows) } else { None } },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-count", title: "", station_name: "" }
  let seen = Ref(0)
  // (its rows as the list reads them: one for each message, Top over them, Foot under)
  let chat_rows : Ref[@sfbase.ChatRows?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {
    seen.val = match @sfbase.chat_view_now(src, r) {
      Some(v) => {
        let cr = match chat_rows.val {
          Some(cr) => cr
          None => {
            let cr = @sfbase.ChatRows::new(v.messages, fn(m) { "m:" + m.ts })
            chat_rows.val = Some(cr)
            cr
          }
        }
        cr.take(v, [Foot])
        v.messages.length()
      }
      None => -1
    }
  })
  t.draw()
  assert_eq(seen.val, n)
  let cr = chat_rows.val.unwrap()
  assert_eq(@signals.untracked(fn() { cr.length() }), n + 2)
  // (a row read by its key, as a row shows what it is: not told of another come)
  let w = @signals.watch(fn() {  })
  assert_eq(w.read(fn() { cr.version_of("m:t\{n / 2}") }), Some(0))
  let shapes = @signals.untracked(fn() { cr.changed() })
  let made = @sfbase.messages_made()
  let work = rows.work()
  let row_work = cr.work()
  // (one come at the end, as the core puts it: its subscription told with it)
  @signals.start_batch()
  rows.take({
    "path": Json::array([Json::string("messages")]),
    "key": Json::array([Json::string("seq"), Json::string("outgoing")]),
    "why": Json::string("came"),
    "put": said_json(n + 1),
  })
  |> ignore
  rows.come_in()
  version.val += 1
  changes.set(version.val)
  @signals.end_batch()
  t.draw()
  assert_eq(seen.val, n + 1)
  assert_eq(@signals.untracked(fn() { cr.length() }), n + 3)
  assert_eq(cr.key(n + 1), "m:t\{n + 1}")
  assert_eq(cr.key(n + 2), "foot")
  assert_eq(@signals.untracked(fn() { cr.changed() }), shapes + 1)
  assert_true(!w.is_stale())
  (@sfbase.messages_made() - made, rows.work() - work, seen.val, cr.work() - row_work)
}

///|
test "one message come costs the chat page the same with 30 messages and with 3000" {
  let (made30, work30, _, rows30) = one_come_costs(30)
  let (made3000, work3000, _, rows3000) = one_come_costs(3000)
  // (its rows: the one come taken, the ends compared, none of the messages gone through)
  assert_eq(rows3000, rows30)
  // (the one come made, none else: the others as they were made)
  assert_eq(made3000, made30)
  assert_eq(made30, 1)
  // (the list: the one put in, nothing gone through, nothing put together whole)
  assert_eq(work3000, work30)
}

///|
test "reading a chat's view without its list does not make its messages" {
  new_run()
  let count = 3000
  let all : Json = { "messages": Json::array(Array::makei(count, fn(i) { said_json(i + 1) })) }
  let rows = @rows.TopicList::new(["messages"], ["seq", "outgoing"], Some(all))
  let rest : Json = { "title": Json::string("对话"), "messages": Json::null() }
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" { { value: Some(rest), error: None, version: 1 } }
      else { (base.topic)(name, params) }
    },
    list: fn(name, _, _, _) { if name == "chat" { Some(rows) } else { None } },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-view-only", title: "", station_name: "" }
  let made = @sfbase.messages_made()
  let work = rows.work()
  let view = @sfbase.chat_view_now(src, r).unwrap()
  assert_eq(view.messages.length(), count)
  assert_eq(@sfbase.messages_made() - made, 0, msg="the view did not make the history")
  assert_eq(rows.work() - work, 0, msg="the view did not copy or search the history")
  let entries = view_of_chat(src, r).1
  assert_eq(entries.length(), count + 2)
  assert_true(physical_equal(entries, view_of_chat(src, r).1), msg="the requested entries are kept for this view")
  rows.take({
    "path": Json::array([Json::string("messages")]),
    "key": Json::array([Json::string("seq"), Json::string("outgoing")]),
    "why": Json::string("came"),
    "put": said_json(count + 1),
  }) |> ignore
  rows.come_in()
  assert_eq(view_of_chat(src, r).1.length(), count + 3, msg="a later request sees the new message")
}

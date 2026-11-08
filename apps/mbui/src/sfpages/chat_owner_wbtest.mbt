// A chat row's real press callbacks over a Client and a view-owned Source.

///|
fn row_client_source(client : @core.Client) -> Source {
  let base = @sfbase.made_source()
  let params_for = fn(name : String, p : Map[String, Json]) { @sfbase.core_topic_params(name, p) }
  {
    ..base,
    topic_key: fn(name, params) { @sfbase.wire_topic_key(name, params_for(name, params)) },
    topic_read: fn(name, params) {
      if name != "chat" { return (base.topic_read)(name, params) }
      let sub = client.follow_topic(name, params=params_for(name, params))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "chat" { client.follow_topic(name, params=params_for(name, params)).waiting } else { false }
    },
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "chat" { client.leave_topic(name, params=params_for(name, params)) } },
    release: fn(name, params) { if name == "chat" { client.release_topic(name, params=params_for(name, params)) } },
  }
}

///|
fn owned_row_test(node : Bool) -> (@ui.Tester, @core.Client, Array[String], ChatItem, Ref[Source?], @signals.Signal[Bool], Ref[Bool], Ref[Int], Ref[Source?], Ref[@view.View?]) {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = row_client_source(client)
  let item = { ..sample_chat(0), title: "Owned row", station: "ws1/st1" }
  let page_source : Ref[Source?] = Ref(None)
  let page_entry : Ref[@view.View?] = Ref(None)
  let row_source : Ref[Source?] = Ref(None)
  let page_shows = @signals.signal(true)
  let page_disposed = Ref(0)
  let opened = Ref(false)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=240.0, platform=2, pointing=Finger, native=Finger)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let row_src = src.owned_by(root)
    row_source.val = Some(row_src)
    if node {
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      chat_row_node(root, row_src, tips, fn() { item }, "agents", fn() { false }, Whole, fn() { 0 }) |> ignore
    } else {
      @ui.old(root, fn(c) {
        chat_row(c, row_src, item, "agents", at=Whole, opened=fn(r) { opened.val = true; @sfbase.open_page(Chat(r)) }) |> ignore
      })
      .height(Is(Some(100.0)))
      |> ignore
    }
    root.show(fn() { page_shows.get() }, fn(page) {
      page.laid_nowhere(Is(true)) |> ignore
      page_entry.val = Some(page)
      page_source.val = Some(src.owned_by(page))
      page.owns(fn() { page_disposed.val += 1 }) |> ignore
    })
  })
  t.draw()
  (t, client, sent, item, page_source, page_shows, opened, page_disposed, row_source, page_entry)
}

///|
fn cancelled_owned_row(node : Bool) -> Unit raise {
    let (t, client, sent, item, _, _, _, _, _, _) = owned_row_test(node)
    let params = @sfbase.core_topic_params("chat", chat_params(row_ref(item)))
    let (x, y) = t.find(item.title).unwrap()
    t.press_at(x, y)
    if node {
      assert_true(client.peek_topic("chat", params~) is None, msg="the retained row waits for its press to show")
      t.run_for(@ui.tap_indication_ms)
    }
    assert_true(client.peek_topic("chat", params~) is Some(_), msg="the row prefetched, node=\{node}")
    t.touch(3, x, y)
    t.draw()
    assert_true(client.peek_topic("chat", params~) is None, msg="cancel released, node=\{node}")
    assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
    assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
    @ui.run_let_go()
}

///|
test "an old chat row releases its cancelled prefetch" {
  cancelled_owned_row(false)
}

///|
test "a retained chat row releases its cancelled prefetch" {
  cancelled_owned_row(true)
}

///|
fn opening_owned_row(node : Bool, release_row : Bool) -> Unit raise {
    let (t, client, sent, item, page_source, page_shows, opened, page_disposed, row_source, page_entry) = owned_row_test(node)
    let raw = chat_params(row_ref(item))
    let params = @sfbase.core_topic_params("chat", raw)
    let (x, y) = t.find(item.title).unwrap()
    t.press_at(x, y)
    if node {
      assert_true(client.peek_topic("chat", params~) is None, msg="the retained row waits for its press to show")
      t.run_for(@ui.tap_indication_ms)
    }
    let sub = client.peek_topic("chat", params~).unwrap()
    page_source.val.unwrap().topic("chat", raw).get() |> ignore
    assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()))
    t.release(x, y)
    assert_true(if node { app.nav.top() is Chat(_) } else { opened.val }, msg="the row opened, node=\{node}")
    assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
    let (serial, _) = app.nav.top_stay()
    let page_reads = @sfbase.page_chat_reader(page_source.val.unwrap(), page_entry.val.unwrap(), serial)
    page_reads(Chat(row_ref(item)))
    assert_false(@sfbase.chat_open_is_pending(serial), msg="the page has taken over the row's prefetch")
    if release_row {
      // An independent read by the row continues after the prefetch has moved to the page.
      row_source.val.unwrap().topic("chat", raw).get() |> ignore
      assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()))
    }
    page_shows.set(false)
    assert_eq(page_disposed.val, 1, msg="the simulated page was disposed")
    if release_row {
      assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="the row still has the same subscription")
      (row_source.val.unwrap().leave)("chat", raw, @sfbase.TopicLeave::Legacy)
    }
    assert_true(client.peek_topic("chat", params~) is None, msg="the page left and no view reads it, node=\{node}")
    assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
    assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
    let ended = sent.filter(fn(s) {
      let message = try Some(@json.parse(s)) catch { _ => None }
      @sfbase.flag(message, "unsubscribe") && @sfbase.number(message, "id") == sub.id.to_double()
    })
    assert_eq(ended.length(), 1, msg="the original subscription was released once")
    @ui.run_let_go()
}

///|
test "an old chat row hands prefetch to a page that later leaves" {
  opening_owned_row(false, false)
}

///|
test "a retained chat row hands prefetch to a page that later leaves" {
  opening_owned_row(true, false)
}

///|
test "the old row's independent read remains until its explicit leave" {
  opening_owned_row(false, true)
}

///|
test "the retained row's independent read remains until its explicit leave" {
  opening_owned_row(true, true)
}

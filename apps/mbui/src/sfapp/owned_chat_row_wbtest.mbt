// Exercise the real row callbacks and chat_left with independent view sources over a real Client. The page owner is
// attached by the fixture; the application does not yet make these sources itself.

///|
fn owned_row_left_case(
  node : Bool,
  another_owner : Bool,
  row_owned : Bool,
  cancel? : Bool = false,
  page_after_release? : Bool = false,
  page_already_open? : Bool = false,
  long_hold? : Bool = false,
  release_row_after? : Bool = false,
  legacy_owner? : Bool = false,
  row_view_ends_after_up? : Bool = false,
  row_view_ends_during_open? : Bool = false,
) -> Unit raise {
  new_run()
  @sfpages.reset()
  @sf.set_words(@sfbase.fill)
  let sent : Array[String] = []
  let cancels : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = @sfbase.made_source()
  let normalize = fn(name : String, params : Map[String, Json]) { @sfbase.core_topic_params(name, params) }
  let src : Source = {
    ..base,
    topic_key: fn(name, params) { @sfbase.wire_topic_key(name, normalize(name, params)) },
    topic_read: fn(name, params) {
      if name != "chat" { return (base.topic_read)(name, params) }
      let sub = client.follow_topic(name, params=normalize(name, params))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "chat" { client.follow_topic(name, params=normalize(name, params)).waiting } else { false }
    },
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) {
        if name == "chat" { cancels.push(Json::object(params).stringify()) }
        __stop()
        return
      }
      if name == "chat" { client.leave_topic(name, params=normalize(name, params)) } },
    release: fn(name, params) { if name == "chat" { client.release_topic(name, params=normalize(name, params)) } },
  }
  let item = { ..@sfpages.sample_chat(0), title: "Owned row", station: "ws1/st1" }
  let chat : ChatRef = { station: item.station, session: item.session, title: item.title, station_name: item.station_name }
  let raw = @sfbase.chat_params(chat)
  let params = normalize("chat", raw)
  let row_source : Ref[Source?] = Ref(None)
  let page_source : Ref[Source?] = Ref(None)
  let page_entry : Ref[@view.View?] = Ref(None)
  let page_shows = @signals.signal(!page_after_release)
  let page_disposed = Ref(0)
  let opened = Ref(false)
  let disposed_during_open = Ref(false)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=240.0, platform=2, pointing=Finger, native=Finger)
  let external_source : Ref[Source?] = Ref(None)
  let external_tree = if row_view_ends_after_up || row_view_ends_during_open {
    Some(@view.Tree::new(fn(v) { external_source.val = Some(src.owned_by(v)) }))
  } else { None }
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let row_src = if row_view_ends_after_up || row_view_ends_during_open { external_source.val.unwrap() } else if row_owned { src.owned_by(root) } else { src }
    row_source.val = Some(row_src)
    if node {
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      @sfpages.chat_row_node(root, row_src, tips, fn() { item }, "agents", fn() { false }, Whole, fn() { 0 }) |> ignore
    } else {
      @ui.old(root, fn(c) {
        @sfpages.chat_row(c, row_src, item, "agents", at=Whole, opened=fn(r) { opened.val = true; @sfbase.open_page(Chat(r)) }) |> ignore
      }).height(Is(Some(100.0))) |> ignore
    }
    root.show(fn() { page_shows.get() }, fn(page) {
      page.laid_nowhere(Is(true)) |> ignore
      page_entry.val = Some(page)
      page_source.val = Some(src.owned_by(page))
      page.owns(fn() { page_disposed.val += 1 }) |> ignore
    })
  })
  let extra : Ref[Source?] = Ref(None)
  let extra_tree = @view.Tree::new(fn(root) { extra.val = Some(src.owned_by(root)) })
  extra_tree.frame(300.0, 300.0) |> ignore
  t.draw()
  let legacy = if legacy_owner {
    Some(@signals.untracked(fn() { client.follow_topic("chat", params~) }))
  } else {
    None
  }
  if page_already_open {
    page_source.val.unwrap().topic("chat", raw).get() |> ignore
    @sfbase.reading_of(chat.station + "\u{1}" + chat.session) |> ignore
  }
  let (x, y) = t.find(item.title).unwrap()
  let before_press = sent.filter(fn(s) { s.contains("\"subscribe\":") }).length()
  t.press_at(x, y)
  if node {
    assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), before_press, msg="the retained row waits for its press to show")
    t.run_for(@ui.tap_indication_ms)
  }
  guard client.peek_topic("chat", params~) is Some(sub) else {
    let asked = sent.filter(fn(s) { s.contains("\"subscribe\":") }).length()
    let ended = sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length()
    fail("the row did not keep its prefetch, node=\{node}, subscribe=\{asked}, unsubscribe=\{ended}")
  }
  if legacy is Some(old) { assert_true(physical_equal(old, sub), msg="the row shared the legacy reader's subscription") }
  if cancel {
    if another_owner { extra.val.unwrap().topic("chat", raw).get() |> ignore }
    if long_hold {
      t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms + 30.0)
      t.release(x, y)
    } else {
      t.touch(3, x, y)
      t.draw()
    }
    assert_eq(cancels, [Json::object(raw).stringify()], msg="the row reports exactly its own cancelled prefetch")
    if page_already_open {
      assert_true(@sfbase.readings.contains(chat.station + "\u{1}" + chat.session), msg="the chat page is registered as open")
      assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="the open page still owns the chat")
      chat_left(page_source.val.unwrap(), chat)
      page_shows.set(false)
      assert_eq(page_disposed.val, 1, msg="the open page was disposed")
    } else if another_owner {
      assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="cancel leaves the independent reader")
      assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
      client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "still following" } })
      assert_eq(@sfbase.text(extra.val.unwrap().topic("chat", raw).get().value, "text"), "still following")
    }
    extra_tree.dispose()
    if release_row_after {
      assert_true(client.peek_topic("chat", params~) is None, msg="the row has already released its prefetch")
    }
    if legacy is Some(old) {
      assert_true(client.peek_topic("chat", params~) is Some(s) && physical_equal(old, s), msg="cancelling the row preserves the independent legacy reader")
      assert_eq(lease_ended(sent, old.id), 0)
      client.receive_json({ "id": Json::number(old.id.to_double()), "value": { "text": "legacy still following" } })
      assert_eq(@sfbase.text(old.value, "text"), "legacy still following")
      client.leave_topic("chat", params~)
    }
    assert_true(client.peek_topic("chat", params~) is None, msg="the row and all page readers have left")
    assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
    assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
    assert_eq(lease_ended(sent, sub.id), 1, msg="the original subscription ended exactly once")
    @ui.run_let_go()
    return
  }
  let after_page : Ref[@view.Tree?] = Ref(None)
  if another_owner { extra.val.unwrap().topic("chat", raw).get() |> ignore }
  if page_after_release {
    // Dispatch the up event with no app frame; construct the new page and read only after that event.
    if row_view_ends_during_open {
      let original_shell = @sfbase.shell.val
      @sfbase.shell.val = {
        ..original_shell,
        open: fn(page) { disposed_during_open.val = true; external_tree.unwrap().dispose(); (original_shell.open)(page) },
      }
    }
    t.touch(2, x, y)
    if row_view_ends_during_open { assert_true(disposed_during_open.val, msg="the row owner ended inside the open callback") }
    if external_tree is Some(row_owner) {
      let (serial, _) = app.nav.top_stay()
      assert_true(@sfbase.chat_open_is_pending(serial), msg="the row registered a pending handover")
      row_owner.dispose()
      let current = client.peek_topic("chat", params~)
      assert_true(current is Some(s) && physical_equal(s, sub), msg="the pending handover outlives the row's view; current_id=\{Repr(current.map(fn(s) { s.id }))}, original_id=\{sub.id}, original_unsubscribes=\{lease_ended(sent, sub.id)}, messages=\{Repr(sent)}")
      assert_eq(lease_ended(sent, sub.id), 0, msg="the original subscription stayed active")
    }
    after_page.val = Some(@view.Tree::new(fn(page) {
      page_entry.val = Some(page)
      page_source.val = Some(src.owned_by(page))
      page.owns(fn() { page_disposed.val += 1 }) |> ignore
    }))
    page_source.val.unwrap().topic("chat", raw).get() |> ignore
    t.draw()
  } else {
    page_source.val.unwrap().topic("chat", raw).get() |> ignore
    t.release(x, y)
  }
  let (serial, _) = app.nav.top_stay()
  let page_reads = @sfbase.page_chat_reader(page_source.val.unwrap(), page_entry.val.unwrap(), serial)
  page_reads(Chat(chat))
  assert_true(if node { app.nav.top() is Chat(_) } else { opened.val }, msg="the real row opened")
  chat_left(row_source.val.unwrap(), chat)
  assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="the page still owns the prefetched subscription")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
  match after_page.val {
    Some(page) => page.dispose()
    None => page_shows.set(false)
  }
  assert_eq(page_disposed.val, 1, msg="the fixture page was disposed")
  if another_owner {
    assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="the independent owner still follows")
  } else {
    assert_true(client.peek_topic("chat", params~) is None, msg="the final owner released the chat")
  }
  extra_tree.dispose()
  assert_true(client.peek_topic("chat", params~) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  let ended = sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.flag(message, "unsubscribe") && @sfbase.number(message, "id") == sub.id.to_double()
  })
  assert_eq(ended.length(), 1, msg="the original subscription ended exactly once")
  @ui.run_let_go()
}

///|
test "an old row can hand over after its own view ends before the page starts" {
  owned_row_left_case(false, false, true, page_after_release=true, row_view_ends_after_up=true)
}

///|
test "a retained row can hand over after its own view ends before the page starts" {
  owned_row_left_case(true, false, true, page_after_release=true, row_view_ends_after_up=true)
}

///|
test "an old row can hand over when its view ends inside the open callback" {
  owned_row_left_case(false, false, true, page_after_release=true, row_view_ends_during_open=true)
}

///|
test "a retained row can hand over when its view ends inside the open callback" {
  owned_row_left_case(true, false, true, page_after_release=true, row_view_ends_during_open=true)
}

///|
test "the old row and chat_left hand prefetch to the page" {
  owned_row_left_case(false, false, true)
}

///|
test "the retained row and chat_left hand prefetch to the page" {
  owned_row_left_case(true, false, true)
}

///|
test "the old row leaves another chat owner in place" {
  owned_row_left_case(false, true, true)
}

///|
test "the retained row leaves another chat owner in place" {
  owned_row_left_case(true, true, true)
}

///|
test "the old row's base source hands prefetch to the page" {
  owned_row_left_case(false, false, false)
}

///|
test "the retained row's base source hands prefetch to the page" {
  owned_row_left_case(true, false, false)
}

///|
test "the old row's base leave keeps another owner" {
  owned_row_left_case(false, true, false)
}

///|
test "the retained row's base leave keeps another owner" {
  owned_row_left_case(true, true, false)
}

///|
test "the old row cancels a view-owned prefetch" {
  owned_row_left_case(false, false, true, cancel=true)
}

///|
test "the retained row cancels a view-owned prefetch" {
  owned_row_left_case(true, false, true, cancel=true)
}

///|
test "the old row cancels a base source prefetch" {
  owned_row_left_case(false, false, false, cancel=true)
}

///|
test "the retained row cancels a base source prefetch" {
  owned_row_left_case(true, false, false, cancel=true)
}

///|
test "the old row cancels without releasing another view" {
  owned_row_left_case(false, true, true, cancel=true)
}

///|
test "the retained row cancels without releasing another view" {
  owned_row_left_case(true, true, true, cancel=true)
}

///|
test "the old row's base cancellation keeps another view" {
  owned_row_left_case(false, true, false, cancel=true)
}

///|
test "the retained row's base cancellation keeps another view" {
  owned_row_left_case(true, true, false, cancel=true)
}

///|
test "the old row's page takes the prefetch after release with no frame" {
  owned_row_left_case(false, false, true, page_after_release=true)
}

///|
test "the retained row's page takes the prefetch after release with no frame" {
  owned_row_left_case(true, false, true, page_after_release=true)
}

///|
test "the old row's base prefetch is taken after release with no frame" {
  owned_row_left_case(false, false, false, page_after_release=true)
}

///|
test "the retained row's base prefetch is taken after release with no frame" {
  owned_row_left_case(true, false, false, page_after_release=true)
}

///|
test "an old row cancelled while its chat is open releases after that page leaves" {
  owned_row_left_case(false, false, true, cancel=true, page_already_open=true)
}

///|
test "a retained row cancelled while its chat is open releases after that page leaves" {
  owned_row_left_case(true, false, true, cancel=true, page_already_open=true)
}

///|
test "an old row's base prefetch cancelled while its chat is open releases after that page leaves" {
  owned_row_left_case(false, false, false, cancel=true, page_already_open=true)
}

///|
test "a retained row's base prefetch cancelled while its chat is open releases after that page leaves" {
  owned_row_left_case(true, false, false, cancel=true, page_already_open=true)
}

///|
test "a held old row releases its prefetch without releasing another view" {
  owned_row_left_case(false, true, true, cancel=true, long_hold=true)
}

///|
test "a held retained row releases its prefetch without releasing another view" {
  owned_row_left_case(true, true, true, cancel=true, long_hold=true)
}

///|
test "the old row's cancelled owned read needs no later release" {
  owned_row_left_case(false, false, true, cancel=true, page_already_open=true, release_row_after=true)
}

///|
test "the retained row's cancelled owned read needs no later release" {
  owned_row_left_case(true, false, true, cancel=true, page_already_open=true, release_row_after=true)
}

///|
test "the old row's cancelled base read needs no later release" {
  owned_row_left_case(false, false, false, cancel=true, page_already_open=true, release_row_after=true)
}

///|
test "the retained row's cancelled base read needs no later release" {
  owned_row_left_case(true, false, false, cancel=true, page_already_open=true, release_row_after=true)
}

///|
test "the held old row's cancelled read needs no later release" {
  owned_row_left_case(false, true, true, cancel=true, long_hold=true, release_row_after=true)
}

///|
test "an old row's base prefetch cancellation preserves an independent legacy reader" {
  owned_row_left_case(false, false, false, cancel=true, legacy_owner=true)
}

///|
test "a retained row's base prefetch cancellation preserves an independent legacy reader" {
  owned_row_left_case(true, false, false, cancel=true, legacy_owner=true)
}

///|
test "an old row's view prefetch cancellation preserves an independent legacy reader" {
  owned_row_left_case(false, false, true, cancel=true, legacy_owner=true)
}

///|
test "a retained row's view prefetch cancellation preserves an independent legacy reader" {
  owned_row_left_case(true, false, true, cancel=true, legacy_owner=true)
}

///|
test "an old row with an open page cancels independently of a legacy reader" {
  owned_row_left_case(false, false, true, cancel=true, page_already_open=true, legacy_owner=true)
}

///|
test "a retained row with an open page cancels independently of a legacy reader" {
  owned_row_left_case(true, false, true, cancel=true, page_already_open=true, legacy_owner=true)
}

///|
test "an old row's base prefetch with an open page cancels independently of a legacy reader" {
  owned_row_left_case(false, false, false, cancel=true, page_already_open=true, legacy_owner=true)
}

///|
test "a retained row's base prefetch with an open page cancels independently of a legacy reader" {
  owned_row_left_case(true, false, false, cancel=true, page_already_open=true, legacy_owner=true)
}

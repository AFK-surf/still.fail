// A chat's paging follows its data and its list's completed visible range, without a page building it.

///|
test "paging follows signals without a page and stops with its owner" {
  let asked : Array[String] = []
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let src = @sfbase.made_source(call=fn(name, _, answer) {
    asked.push(name)
    answers.push(answer)
  })
  let r : ChatRef = { station: "station", session: "paging-signal", title: "", station_name: "" }
  let rd = @sfbase.reading_of("paging-signal")
  let retries = Ref(0)
  let stop_retries = @signals.effect(fn() { retries.val = rd.paging_retry_version() })
  let data : @signals.Signal[@sfbase.ChatPagingInput] = @signals.signal({
    thread: Some(7.0),
    placed: true,
    more: true,
    newer: true,
    first_entry: Some(10.0),
    first_message: None,
    last_entry: 20.0,
    retry: 0,
  }, same=fn(a, b) { a == b })
  let position : @signals.Signal[@sfbase.ChatPagingWindow?] = @signals.signal(
    Some({ first: 5, last: 9, count: 20 }),
    same=fn(a, b) { a == b },
  )
  let input = @signals.computed(fn(_) { data.get() }, same=fn(a, b) { a == b })
  let window = @signals.computed(fn(_) { position.get() }, same=fn(a, b) { a == b })
  let stop = @sfbase.chat_paging_follow(src, r, rd, input, window)
  assert_eq(asked, [])
  // Moving to the edge calls the core without a build; a position change on the same page cannot call it twice.
  position.set(Some({ first: 3, last: 9, count: 20 }))
  position.set(Some({ first: 2, last: 9, count: 20 }))
  assert_eq(asked, ["chat.older"])
  // Even an immediate failure must not create a retry loop; retry is a new action of the owner.
  (answers[0])(Err({ "message": "offline" }))
  assert_eq(asked, ["chat.older"])
  assert_eq(retries.val, 1)
  data.set({ ..data.get(), retry: 1 })
  assert_eq(asked, ["chat.older", "chat.older"])
  // A new model and its new window are one change: a stale edge cannot request the new page.
  @signals.start_batch()
  data.set({ ..data.get(), first_entry: Some(11.0) })
  position.set(Some({ first: 5, last: 9, count: 20 }))
  @signals.end_batch()
  assert_eq(asked, ["chat.older", "chat.older"])
  position.set(Some({ first: 5, last: 17, count: 20 }))
  assert_eq(asked, ["chat.older", "chat.older", "chat.newer"])
  data.set({ ..data.get(), last_entry: 21.0 })
  assert_eq(asked, ["chat.older", "chat.older", "chat.newer", "chat.newer"])
  stop()
  position.set(Some({ first: 0, last: 19, count: 20 }))
  data.set({ ..data.get(), first_entry: Some(12.0), last_entry: 22.0 })
  assert_eq(asked, ["chat.older", "chat.older", "chat.newer", "chat.newer"])
  stop_retries()
  input.dispose()
  window.dispose()
}

///|
test "an old paging failure cannot reset a newer request or a stopped owner" {
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let src = @sfbase.made_source(call=fn(_, _, answer) { answers.push(answer) })
  let r : ChatRef = { station: "station", session: "paging-late", title: "", station_name: "" }
  let rd = @sfbase.reading_of("paging-late")
  let data : @signals.Signal[@sfbase.ChatPagingInput] = @signals.signal({
    thread: Some(7.0),
    placed: true,
    more: true,
    newer: false,
    first_entry: Some(10.0),
    first_message: None,
    last_entry: 20.0,
    retry: 0,
  }, same=fn(a, b) { a == b })
  let window : @signals.Computed[@sfbase.ChatPagingWindow?] = @signals.computed(
    fn(_) { Some({ first: 0, last: 9, count: 20 }) },
  )
  let input = @signals.computed(fn(_) { data.get() }, same=fn(a, b) { a == b })
  let stop = @sfbase.chat_paging_follow(src, r, rd, input, window)
  data.set({ ..data.get(), first_entry: Some(11.0) })
  data.set({ ..data.get(), first_entry: Some(10.0) })
  assert_eq(answers.length(), 3)
  (answers[0])(Err({ "message": "old request" }))
  data.set({ ..data.get(), retry: 1 })
  assert_eq(answers.length(), 3, msg="the newer request is still pending")
  assert_eq(rd.asked.get(), 10.0)
  stop()
  (answers[2])(Err({ "message": "after the owner left" }))
  assert_eq(rd.asked.get(), 10.0, msg="a stopped owner's answer changed its state")
  input.dispose()
  window.dispose()
}

///|
test "an old next-page failure cannot reset a newer request or a stopped owner" {
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let src = @sfbase.made_source(call=fn(_, _, answer) { answers.push(answer) })
  let r : ChatRef = { station: "station", session: "paging-next-late", title: "", station_name: "" }
  let rd = @sfbase.reading_of("paging-next-late")
  let data : @signals.Signal[@sfbase.ChatPagingInput] = @signals.signal({
    thread: Some(7.0),
    placed: true,
    more: false,
    newer: true,
    first_entry: Some(10.0),
    first_message: None,
    last_entry: 20.0,
    retry: 0,
  }, same=fn(a, b) { a == b })
  let input = @signals.computed(fn(_) { data.get() }, same=fn(a, b) { a == b })
  let window : @signals.Computed[@sfbase.ChatPagingWindow?] = @signals.computed(
    fn(_) { Some({ first: 5, last: 17, count: 20 }) },
  )
  let stop = @sfbase.chat_paging_follow(src, r, rd, input, window)
  data.set({ ..data.get(), last_entry: 21.0 })
  data.set({ ..data.get(), last_entry: 20.0 })
  assert_eq(answers.length(), 3)
  (answers[0])(Err({ "message": "old request" }))
  data.set({ ..data.get(), retry: 1 })
  assert_eq(answers.length(), 3, msg="the newer request is still pending")
  assert_eq(rd.asked_newer.get(), 20.0)
  stop()
  (answers[2])(Err({ "message": "after the owner left" }))
  assert_eq(rd.asked_newer.get(), 20.0, msg="a stopped owner's answer changed its state")
  input.dispose()
  window.dispose()
}

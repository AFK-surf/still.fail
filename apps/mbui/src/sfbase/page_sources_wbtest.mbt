///|
test "overlapping views of one navigation entry retain each other's source in either disposal order" {
  for last_first in [false, true] {
    page_sources.clear()
    page_source_seen.val = 0
    let base = made_source()
    let r : ChatRef = { station: "ws1/st1", session: "same-entry", title: "", station_name: "" }
    let first : Ref[Source?] = Ref(None)
    let second : Ref[Source?] = Ref(None)
    let a = @view.Tree::new(fn(v) {
      let src = page_entry_source(base, v, 101)
      first.val = Some(src)
    })
    let b = @view.Tree::new(fn(v) {
      let src = page_entry_source(base, v, 101)
      second.val = Some(src)
    })
    page_entry_read(101, first.val.unwrap(), Chat(r))
    page_entry_read(101, second.val.unwrap(), Chat(r))
    assert_true(physical_equal(page_source_for_chat(base, r), second.val.unwrap()))
    if last_first {
      b.dispose()
      assert_true(physical_equal(page_source_for_chat(base, r), first.val.unwrap()), msg="the earlier view is still registered")
      a.dispose()
    } else {
      a.dispose()
      assert_true(physical_equal(page_source_for_chat(base, r), second.val.unwrap()), msg="the later view is still registered")
      b.dispose()
    }
    assert_true(physical_equal(page_source_for_chat(base, r), base), msg="no view of the entry remains")
  }
}

///|
test "a page leaving callback retains its source even if view cleanup has already run" {
  page_sources.clear()
  left_page_sources.clear()
  left_pages.clear()
  let base = made_source()
  let r : ChatRef = { station: "ws1/st1", session: "ordered-cleanup", title: "", station_name: "" }
  let owned : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) {
    let src = page_entry_source(base, v, 102)
    owned.val = Some(src)
  })
  page_entry_read(102, owned.val.unwrap(), Chat(r))
  tree.dispose()
  assert_true(page_sources.get(102) is Some(saved) && !saved[0].active, msg="the view cleanup ran first")
  page_entry_left(102, Chat(r))
  assert_true(physical_equal(left_page_source(base, 0).0.unwrap(), owned.val.unwrap()), msg="entry leave uses the ended view's source")
  assert_true(page_sources.get(102) is None, msg="the entry's sources are removed at leave")
  left_pages.clear()
}

///|
test "equal chat entries associate leave sources by entry rather than page value" {
  page_sources.clear()
  left_page_sources.clear()
  left_pages.clear()
  let base = made_source()
  let r : ChatRef = { station: "ws1/st1", session: "equal-entries", title: "", station_name: "" }
  let owned : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { owned.val = Some(page_entry_source(base, v, 202)) })
  page_entry_read(202, owned.val.unwrap(), Chat(r))
  page_entry_left(201, Chat(r))
  page_entry_left(202, Chat(r))
  assert_eq(left_pages.length(), 2)
  assert_true(left_page_source(base, 0).0 is None, msg="the unseen entry did not take the other source")
  assert_true(physical_equal(left_page_source(base, 1).0.unwrap(), owned.val.unwrap()), msg="the rendered entry kept its own source")
  tree.dispose()
  left_pages.clear()
}

///|
test "an undrawn replacement view does not hide the source which read the page" {
  page_sources.clear()
  left_page_sources.clear()
  left_pages.clear()
  let base = made_source()
  let r : ChatRef = { station: "ws1/st1", session: "undrawn-view", title: "", station_name: "" }
  let read : Ref[Source?] = Ref(None)
  let a = @view.Tree::new(fn(v) { read.val = Some(page_entry_source(base, v, 303)) })
  page_entry_read(303, read.val.unwrap(), Chat(r))
  let b = @view.Tree::new(fn(v) { page_entry_source(base, v, 303) |> ignore })
  a.dispose()
  page_entry_left(303, Chat(r))
  assert_true(physical_equal(left_page_source(base, 0).0.unwrap(), read.val.unwrap()), msg="the leave uses the source that actually read the page")
  b.dispose()
  left_pages.clear()
}

///|
test "a source that ends before its entry leaves keeps its last live chat projection" {
  page_sources.clear()
  left_page_sources.clear()
  left_pages.clear()
  let base = made_source()
  let r : ChatRef = { station: "ws1/st1", session: "disposed-projection", title: "", station_name: "" }
  let owned : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { owned.val = Some(page_entry_source(base, v, 404)) })
  let source = owned.val.unwrap()
  page_entry_read(404, source, Chat(r))
  page_chat_view_read(source, r, Some(chat_view_made({ "thread": { "id": 101.0 }, "messages": [] })))
  tree.dispose()
  page_chat_view_read(source, r, None)
  page_entry_left(404, Chat(r))
  let (left_source, view) = left_page_source(base, 0)
  assert_true(left_source is Some(s) && physical_equal(s, source))
  assert_true(view is Some(v) && v.thread == Some(101.0), msg="ending the source must not erase the last live projection")
  left_pages.clear()
}

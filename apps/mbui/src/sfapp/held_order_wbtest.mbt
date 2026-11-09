// The chats' list held while a finger is on it (sfbase rows.mbt held_order): made again only as something comes, not
// each frame it is held (sfpages' sidebar.mbt lays out its days once for each order shown).

///|
/// A view of one day's chats, by their ids, in this order.
fn held_view(ids : Array[String]) -> @sfbase.ChatsView {
  let items = ids.map(fn(id) {
    Json::object({ "station": Json::string("s"), "id": Json::string(id), "session": Json::string(id), "title": Json::string(id) })
  })
  @sfbase.chats_view_made(Json::object({ "days": Json::array([Json::object({ "label": Json::string("今天"), "items": Json::array(items) })]) }))
}

///|
fn held_ids(days : Array[@sfbase.ChatDay]) -> Array[String] {
  let out = []
  for d in days {
    for item in d.items {
      out.push(item.id)
    }
  }
  out
}

///|
/// A day of chats given whole, in this order.
fn held_rows(items : Array[Json]) -> @sfbase.ChatsView {
  @sfbase.chats_view_made(Json::object({ "days": Json::array([Json::object({ "label": Json::string("今天"), "items": Json::array(items) })]) }))
}

///|
/// Chat `id`, its last message `seq` said by the viewer (`mine`) or by someone else.
fn held_row(id : String, seq : Int, mine : Bool) -> Json {
  let by = Json::object({ "kind": Json::string("person"), "name": Json::string(if mine { "你" } else { "小王" }), "mine": Json::boolean(mine) })
  let last = Json::object({ "seq": Json::number(seq.to_double()), "preview": Json::string("…"), "by": by })
  Json::object({ "station": Json::string("s"), "id": Json::string(id), "session": Json::string(id), "title": Json::string(id), "last": last })
}

///|
test "a chat the viewer writes in goes ahead at once, though a pointer rests on the list" {
  new_run()
  let key = "held/wrote"
  let first = held_rows([held_row("a", 3, false), held_row("b", 5, true)])
  ignore(@sfbase.held_order(key, first.days, false))
  // someone else's news while the pointer rests on the list: the rows keep their places
  let news = held_rows([held_row("b", 6, false), held_row("a", 3, false)])
  assert_true(!@sfbase.viewer_moved(key, news.days))
  assert_eq(held_ids(@sfbase.held_order(key, news.days, true)), ["a", "b"])
  // the viewer writes in b (its pointer still resting there, typing): b goes ahead
  let wrote = held_rows([held_row("b", 7, true), held_row("a", 3, false)])
  assert_true(@sfbase.viewer_moved(key, wrote.days))
  // nothing come since: not again
  let shown = @sfbase.held_order(key, wrote.days, !@sfbase.viewer_moved(key, wrote.days))
  assert_eq(held_ids(shown), ["b", "a"])
  assert_true(!@sfbase.viewer_moved(key, wrote.days))
}

///|
test "a held list's order is the very same while nothing comes, made again only as something does" {
  new_run()
  let key = "held/test"
  let first = held_view(["a", "b"])
  let shown = @sfbase.held_order(key, first.days, false)
  assert_true(physical_equal(shown, first.days))
  // held, nothing new: the order shown, not made again
  assert_true(!@sfbase.days_new(key, first.days))
  assert_true(physical_equal(@sfbase.held_order(key, first.days, true), shown))
  // a new version while held: its rows keep their places, the new one comes where it would be
  let next = held_view(["c", "b", "a"])
  assert_true(@sfbase.days_new(key, next.days))
  let held = @sfbase.held_order(key, next.days, true)
  assert_eq(held_ids(held), ["c", "a", "b"])
  // and held on, nothing more come: that very order
  assert_true(!@sfbase.days_new(key, next.days))
  assert_true(physical_equal(@sfbase.held_order(key, next.days, true), held))
  // let go: as the core has it
  assert_true(physical_equal(@sfbase.held_order(key, next.days, false), next.days))
}

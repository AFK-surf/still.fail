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

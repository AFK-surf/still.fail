///|
/// A chat's whole row as the made-up core gave it before it made that row alone: the first of the whole made-up list
/// `chats {scope, mine:false}` that is it, then of the same with `hidden`.
fn chat_row_of_lists(f : Fixture, station : String, session : String) -> Json {
  let scope = @settings.workspace_of(station)
  for hidden in [false, true] {
    let asked : Map[String, Json] = { "scope": Json::string(scope), "mine": Json::boolean(false) }
    if hidden {
      asked["hidden"] = Json::boolean(true)
    }
    match whole_row_in(fixture_chats(f, asked), station, session) {
      Some(row) => return row
      None => ()
    }
  }
  Json::null()
}

///|
/// The made-up core of `mode` as a run begins with it, `set` done to it: what a long account kept let go of, as
/// `fixture` does.
fn chat_row_fixture(mode : String, set : (Fixture) -> Unit) -> Fixture {
  paged_days.val = None
  paged_rows.clear()
  let f = made_fixture(mode)
  set(f)
  f
}

///|
/// Each chat's whole row (`chatRow`) the same as the lists made it, every field: each row of the made-up lists (`every`
/// in a mode of a few, else every `every`th and the first and last few) asked by its session, by its id and as another
/// station's, and what names none.
fn chat_rows_same(mode : String, every~ : Int = 1, set~ : (Fixture) -> Unit = fn(_) { () }) -> Unit raise {
  let f = chat_row_fixture(mode, set)
  let rows : Array[Json] = []
  for hidden in [false, true] {
    let asked : Map[String, Json] = { "scope": "ws1", "mine": Json::boolean(false) }
    if hidden {
      asked["hidden"] = Json::boolean(true)
    }
    for d in items(fixture_chats(f, asked), "days") {
      rows.append(items(Some(d), "items"))
    }
  }
  let asks : Array[(String, String)] = []
  for i, r in rows {
    if i % every == 0 || i < 12 || i >= rows.length() - 3 {
      let station = text(Some(r), "station")
      let other = if station == "ws1/st1" { "ws1/st2" } else { "ws1/st1" }
      asks.push((station, text(Some(r), "session")))
      asks.push((station, text(Some(r), "id")))
      asks.push((other, text(Some(r), "session")))
    }
  }
  // (and what names none, or a row archived)
  for session in [
    "c3", "s-c3", "c12", "s-c12", "c20", "s-c20", "c250", "c251", "s-c251", "c1210", "c1211", "c0", "c011", "s-c011", "s-s-c12",
    "c12x", "c-1", "c", "s-", "", "c99999999999",
  ] {
    asks.push(("ws1/st1", session))
    asks.push(("ws1/st2", session))
  }
  asks.push(("ws2/st1", "s-c1"))
  asks.push(("", "s-c1"))
  asks.push(("ws1", "s-c1"))
  let said : Array[String] = []
  for ask in asks {
    let (station, session) = ask
    let now = fixture_chat_row(f, { "station": Json::string(station), "session": Json::string(session) }).unwrap_or(
      Json::string("none"),
    )
    let before = chat_row_of_lists(f, station, session)
    if now != before {
      said.push("\{mode} \{station} \{session}: \{now.stringify()} where the lists made \{before.stringify()}")
    }
  }
  if !said.is_empty() {
    fail(said[:3].to_owned().join(" ;; "))
  }
}

///|
test "a chat's whole row is the row the lists make, in each mode with a few" {
  for mode in [
    "", "home", "signin", "loading", "empty", "webdemo", "chat", "home-pins", "chat-actions", "home-share", "chat-opener",
    "chat-opened", "share-card", "share-card-dark", "home-attention", "home-syncing", "archived", "search",
  ] {
    chat_rows_same(mode)
  }
  chat_rows_same("home", set=fn(f) {
    f.archived["c3"] = true
    f.archived["c8"] = true
  })
}

///|
test "a chat's whole row is the row the lists make, hidden ones and those of a list in motion" {
  chat_rows_same("home-hide")
  chat_rows_same("home-hide", set=fn(f) {
    f.hidden["c1"] = true
    f.muted["c1"] = true
  })
  chat_rows_same("home-hide", set=fn(f) { f.muted["c1"] = true })
  for step in 0..=4 {
    chat_rows_same("home-motion", set=fn(f) { f.step = step })
  }
}

///|
test "a chat's whole row is the row the lists make, in a long account" {
  chat_rows_same("long", every=17)
  chat_rows_same("long", every=23, set=fn(f) {
    f.archived["c12"] = true
    f.archived["c20"] = true
    f.archived["c250"] = true
  })
}

///|
test "a chat's whole row is the row the lists make, in a long account given a page at a time" {
  chat_rows_same("long-paged", every=97)
  chat_rows_same("long-paged", every=131, set=fn(f) {
    f.archived["c12"] = true
    f.archived["c1210"] = true
  })
}

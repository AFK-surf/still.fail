// What a chats list row is drawn from (sfbase's rows.mbt): its mark's tone, its agents by their mark, the list's filter.

///|
fn row_json(fields : Map[String, Json]) -> @sfbase.ChatItem {
  let o : Map[String, Json] = { "id": "c1", "session": "s-c1", "title": "整理发布清单", "station": "ws1/st1" }
  for k, v in fields {
    o[k] = v
  }
  @sfbase.chat_item(Json::object(o))
}

///|
test "a row's mark: the core's tone where it says one; else blocked or failed red (alert), at work yellow (busy), unread blue (done), none" {
  assert_eq(@sfbase.row_tone(row_json({ "tone": "wait", "state": "run" })), "wait")
  assert_eq(@sfbase.row_tone(row_json({ "tone": "other", "state": "block" })), "alert")
  assert_eq(@sfbase.row_tone(row_json({ "state": "failed" })), "alert")
  assert_eq(@sfbase.row_tone(row_json({ "state": "run", "unread": true })), "busy")
  assert_eq(@sfbase.row_tone(row_json({ "unread": true })), "done")
  assert_eq(@sfbase.row_tone(row_json({})), "")
}

///|
test "a row's agents by their mark: one maker's models once, a runtime with no maker by its runtime" {
  let item = row_json({
    "agents": [
      { "key": "a", "maker": { "id": "anthropic" }, "runtime": "claude" },
      { "key": "b", "maker": { "id": "anthropic" }, "runtime": "claude-code" },
      { "key": "c", "maker": { "id": "openai" }, "runtime": "codex" },
      { "key": "d", "runtime": "kimi" },
      { "key": "e", "runtime": "kimi" },
    ],
  })
  assert_eq(@sfbase.row_agent_groups(item).map(fn(a) { a.key }), ["a", "c", "d"])
}

///|
test "the list's filter as the prefs keep it where none is chosen here: listFilter by workspace, else onlyWatching, else onlyMine, else all; one unknown is all" {
  let with_prefs = fn(prefs : Json) -> Source {
    fresh_app()
    let base = fixture("home")
    {
      ..base,
      topic_read: fn(name, params) {
        let tp = base.topic(name, params).get().snapshot()
        if name == "prefs" { { ..tp, value: Some(prefs) } } else { tp }
      },
    }
  }
  assert_eq(@sfbase.filter_of(with_prefs({ "listFilter": { "ws1": "hidden" } }), "ws1"), "hidden")
  assert_eq(@sfbase.filter_of(with_prefs({ "listFilter": { "ws2": "mine" }, "onlyWatching": true }), "ws1"), "watching")
  assert_eq(@sfbase.filter_of(with_prefs({ "onlyMine": true }), "ws1"), "mine")
  assert_eq(@sfbase.filter_of(with_prefs({}), "ws1"), "all")
  assert_eq(@sfbase.filter_of(with_prefs({ "listFilter": { "ws1": "pinned" } }), "ws1"), "all")
}

///|
test "what a file added to a draft is, by its name's ending, case aside, for the core: pictures, videos, a PDF, words; else nothing said" {
  let cases = [
    ("a.PNG", "image/png"), ("b.jpg", "image/jpeg"), ("c.jpeg", "image/jpeg"), ("d.gif", "image/gif"),
    ("e.webp", "image/webp"), ("f.HEIC", "image/heic"), ("g.mp4", "video/mp4"), ("h.m4v", "video/mp4"),
    ("i.mov", "video/quicktime"), ("j.webm", "video/webm"), ("k.ogv", "video/ogg"), ("l.3gp", "video/3gpp"),
    ("m.3g2", "video/3gpp2"), ("n.pdf", "application/pdf"), ("o.txt", "text/plain"), ("p.zip", ""), ("png", ""),
  ]
  for c in cases {
    assert_eq(@sfbase.file_type(c.0), c.1, msg=c.0)
  }
}

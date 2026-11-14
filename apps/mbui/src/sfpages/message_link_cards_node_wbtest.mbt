// The cards over a message's links as nodes (message_link_cards_node.mbt, through the library's link_cards_node) set
// beside the old view's (peeks.mbt's link_peek over message_row's words) on the same fixtures, a mouse resting on the
// link: the same drawn a moment before it opens, once it is open (its card, where it is, what it holds), a moment
// before it closes once the pointer has left, and once it has gone. A person's web link; an agent's web link, chat's
// link and its file's path. What is drawn compared as a set (each word and rectangle where it is): the card is drawn
// in the layer over all of the window (after the row), the old view's overlay among the row's.

///|
/// What `t` draws as a mouse comes to rest on the middle of the words `s` (its first line's) and then leaves: a moment
/// before its card opens, once it has come in, a moment before it goes once the pointer is far off, once it has gone.
fn lc_seen(t : @ui.Tester, s : String) -> Array[String] {
  let short = 20.0
  let (x, y) = said_piece(t, s)
  t.run_for(@ui.move_most_ms)
  t.move_to(x, y)
  t.run_for(hover_open_ms - short)
  let before = lc_drawn(t)
  t.run_for(short + @ui.move_most_ms)
  let open = lc_drawn(t)
  t.move_to(756.0, 316.0)
  t.run_for(hover_close_ms - short)
  let leaving = lc_drawn(t)
  t.run_for(short + @ui.move_most_ms)
  [before, open, leaving, lc_drawn(t)]
}

///|
/// What `t` draws (ag_drawn's), each line in order of what it says: as a set.
fn lc_drawn(t : @ui.Tester) -> String {
  let lines = ag_drawn(t).split("\n").map(fn(l) { l.to_owned() }).collect()
  lines.sort()
  lines.join("\n")
}

///|
/// A message of a person's (`agent` false) or an agent's whose words are only a chat's link (the fixture's said_chat, which
/// its `chats` say is 发布), in a sentence: 见 … 。 (a person's its chip, 发布; an agent's its address).
fn lc_chat_msg(agent : Bool) -> Message {
  let m = if agent { ag_msg("links") } else { said_msg() }
  let s = fn(x : String) { Json::string(x) }
  let link = Json::array([s("a"), Json::array([s(said_chat)]), Json::object({ "href": s(said_chat), "bare": Json::boolean(true) })])
  let words = Json::array([
    Json::object({ "text": s("见 ") }),
    Json::object({ "text": s(said_chat), "link": s(said_chat), "ref": Json::boolean(true) }),
    Json::object({ "text": s(" 。") }),
  ])
  {
    ..m,
    text: "见 " + said_chat + " 。",
    md: if agent { Some(Json::array([Json::array([s("p"), Json::array([s("见 "), link, s(" 。")])])])) } else { None },
    words: if agent { None } else { Some(words) },
  }
}

///|
/// The fixture's cases: the message, whose (a person's, an agent's), the words of the link rested on.
fn lc_cases() -> Array[(String, Message, Bool, String)] {
  [
    ("a person's web link", said_msg(long=true), false, "https://example.com"),
    ("a person's chat's link", lc_chat_msg(false), false, "发布"),
    ("an agent's web link", ag_msg("prose"), true, "说明"),
    ("an agent's chat's link", lc_chat_msg(true), true, "https://still.fail/c/ws1"),
    ("an agent's file's path", ag_msg("links"), true, "place.mbt:12"),
  ]
}

///|
test "a link's card over a message's words, made once as nodes, is drawn as the old view's: not yet, open (what it holds, where), still a moment after the pointer left, gone" {
  for c in lc_cases() {
    let old = said_old_row(760.0, c.1)
    let was = lc_seen(old, c.3)
    let t = if c.2 { ag_new_row(760.0, fn() { c.1 }) } else { said_new_row(760.0, fn() { c.1 }) }
    let now = lc_seen(t, c.3)
    assert_true(was[1] != was[0], msg="\{c.0}: the old one's card opens")
    assert_eq(was[3], was[0], msg="\{c.0}: the old one's card gone")
    assert_eq(now, was, msg=c.0)
  }
}


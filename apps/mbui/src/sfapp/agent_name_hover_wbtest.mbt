// An agent's card under its name over its message (sfpages' agent_hover_node on message_name_node): the pointer rested
// on the name opens it, as on its picture; rested on the rest of the message's head (past its name and its time, where
// nothing is) opens nothing, as before the page was the window's tree's (723b5ba19c^: msg_name_room, as wide as the
// name). 2026-11-05: the card came up from anywhere along the head.

///|
/// The words drawn (the laid-out tree's lines that say words: Tester::drawn_text's), each once.
fn words_drawn(t : @ui.Tester) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for line in t.drawn_text().split("\n") {
    let l = line.to_string()
    if l.contains("\"") {
      // (where it is said apart: the same words at another place are the same words)
      let at = l.find("\"").unwrap_or(0)
      out[l.unsafe_substring(start=at, end=l.length())] = true
    }
  }
  out
}

///|
/// The words drawn once the pointer has rested at (x, y) for longer than a card takes to open that were not drawn as
/// it came there (a card's: its agent's name, its station, its state): how many.
fn rested_words(t : @ui.Tester, x : Double, y : Double) -> Array[String] {
  t.move(x, y)
  t.frame()
  let before = words_drawn(t)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  t.frame()
  let after = words_drawn(t)
  t.move(5.0, 5.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  after.keys().filter(fn(k) { !before.contains(k) }).collect()
}

///|
test "an agent's message head opens its card under its name alone, not from the rest of the head" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  // (the last agent message's head: its time, the name before it)
  let (tx, ty) = match t.find("5 分钟前") {
    Some(p) => p
    None => abort("no head")
  }
  let (nx, _) = match t.find("Claude") {
    Some(p) => p
    None => abort("no name")
  }
  ignore(nx)
  // (the name itself, a little before the time: its card, the check that a card does show)
  let on_name = rested_words(t, tx - 70.0, ty)
  // (past the time, along the head, where nothing is)
  let past = rested_words(t, tx + 220.0, ty)
  assert_eq((on_name.length() > 0, past), (true, []), msg="new words on the name \{on_name}, past the time \{past}")
}

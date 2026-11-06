// A chat's row arranged by the width its list is laid out at (chat_list_node's by_room): what a message's table scrolls
// out into (its row's way in from the pane's sides) worked out as the row is laid out, so a window of a width shows and
// presses the same whatever widths it was before (a wide window grown wider stays wide: its rows not made again).

///|
test "a chat's table at a width the same, the window grown to it from another wide width or opened at it" {
  for to in [1400.0, 1600.0] {
    let grown = wide_tester([], mode="chat-md", w=1100.0, h=800.0)
    grown.run_for(@ui.move_most_ms)
    grown.resize(to, 800.0)
    grown.run_for(@ui.move_most_ms)
    let grown_words = grown.words()
    let grown_said = grown.semantics().map(fn(s) { (s.label, s.rect) })
    let opened = wide_tester([], mode="chat-md", w=to, h=800.0)
    opened.run_for(@ui.move_most_ms)
    assert_true(opened.drawn_of("只排可见的行") is Some(_), msg="the table shows at \{to}")
    assert_eq(grown_words, opened.words(), msg="what is drawn at \{to}")
    assert_eq(grown_said, opened.semantics().map(fn(s) { (s.label, s.rect) }), msg="what is read out and pressed at \{to}")
  }
}

///|
/// A table six columns of long words wide, too wide for a wide chat's column: its words and its tree as the core reads
/// them (each cell's words by where they are in the text), with the copy's Markdown and CSV.
fn wide_table() -> (String, Json) {
  let heads = ["甲列", "乙列", "丙列", "丁列", "戊列", "己列"]
  let long = "一二三四五六七八九十一二三四五六七八九十"
  let text = StringBuilder()
  let mut at = 0
  let put = fn(s : String) {
    text.write_string(s)
    at = at + s.length()
  }
  let cell = fn(s : String) -> Json {
    put(" ")
    let from = at
    put(s)
    let span : Json = [[Json::number(from.to_double()), Json::number(at.to_double())]]
    put(" |")
    span
  }
  put("|")
  let head_cells = heads.map(fn(h) { cell(h) })
  put("\n|")
  for _ in heads {
    put("---|")
  }
  put("\n|")
  let row_cells = heads.map(fn(_) { cell(long) })
  put("\n")
  let md = text.to_string()
  let tree : Json = [
    [
      "table",
      [
        ["tr", Json::array(head_cells.map(fn(s) { ["th", s] }))],
        ["tr", Json::array(row_cells.map(fn(s) { ["td", s] }))],
      ],
      {
        "align": Json::array(heads.map(fn(_) { Json::null() })),
        "md": md,
        "csv": heads.join(",") + "\n" + heads.map(fn(_) { long }).join(","),
      },
    ],
  ]
  (md, tree)
}

///|
/// The made-up chat with wide_table as its last answer (chat-md's).
fn wide_table_tester(w : Double) -> @ui.Tester {
  let (text, md) = wide_table()
  wide_tester([], mode="chat-md", w~, h=800.0, platform=2, wrap=fn(base) {
    {
      ..base,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        guard name == "chat" && got.value is Some(value) else { return got }
        { ..got, value: Some(with_chat_message(value, 12.0, [("text", Json::string(text)), ("md", md)])) }
      },
    }
  })
}

///|
test "a wide chat's table scrolled across keeps where it is scrolled to as the window grows, its scroller not made again" {
  // (where 甲列 rests, at each width, from a window opened at it)
  let rest = fn(w : Double) {
    let t = wide_table_tester(w)
    t.run_for(@ui.move_most_ms)
    t.drawn_of("甲列").unwrap()
  }
  let rest_after = rest(1500.0)
  let t = wide_table_tester(1300.0)
  t.run_for(@ui.move_most_ms)
  let (x0, y) = t.drawn_of("甲列").unwrap()
  // (slid 240 to the left, held still before it is let go: no fling)
  t.drag(x0 + 400.0, y, x0 + 160.0, y)
  t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  let (x1, _) = t.drawn_of("甲列").unwrap()
  let scrolled = x0 - x1
  assert_true(scrolled > 100.0, msg="the table scrolled across: \{x0} -> \{x1}")
  t.resize(1500.0, 800.0)
  t.run_for(@ui.move_most_ms)
  let (x2, _) = t.drawn_of("甲列").unwrap()
  assert_eq(rest_after.0 - x2, scrolled, msg="scrolled as far after the window grew: rests at \{rest_after.0}, at \{x2}")
}

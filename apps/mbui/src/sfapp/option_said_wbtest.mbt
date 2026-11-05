// A card's options as read out: each a button named by what it says, its name and, where it has one, its line under it
// (main's options_card: the words in the button read in order), not its name alone.

///|
test "a card's options read out by their name and their line under it" {
  for platform in [0, 2, 1280] {
    let calls : Array[Made] = []
    // (390 by mouse and by touch; 1280 by mouse)
    let t = if platform == 1280 {
      let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, platform=0)
      t.run_for(@ui.move_most_ms * 2.0)
      t
    } else {
      cards_core(calls, platform~)
    }
    scroll_to_words(t, "把首页和聊天页的截图都更新")
    let said = t.semantics()
      .filter(fn(s) { !s.hidden && "\{s.role}" == "Button" && s.label.has_prefix("一起换") })
      .map(fn(s) { s.label })
    assert_eq(said, ["一起换 把首页和聊天页的截图都更新"], msg="platform \{platform}")
  }
}

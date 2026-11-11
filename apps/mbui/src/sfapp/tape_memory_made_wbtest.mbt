// 一台 station 的记忆 made once on the tape at any width of a medium screen (600 to 839: the page in its panel narrow or
// wide as its panel is, the panel's bar naming it), reached as a person does (设置 → 记忆 → Willow).

///|
test "on the tape 一台 station 的记忆 made once: its rows the tree's own; what it is for by one mark, the bar's" {
  for w in [600.0, 640.0, 700.0, 760.0, 800.0, 839.0] {
    let t = tape_station_memory(w~)
    let marks = t.semantics().filter(fn(n) { n.role == Button && n.label == @sf.t("web-main.about") }).length()
    assert_eq(marks, 1, msg="its mark at \{w}")
    let own = tree_words_drawn()
    for word in [@sf.t("web-main.memory.global"), "习惯", "发布流程", "周报", "pdf、xlsx"] {
      assert_true(own.iter().any(fn(o) { o.contains(word) }), msg="\{word} not the tree's own at \{w}: \{Repr(own)}")
    }
  }
}

// 一台 station 的记忆 made once on the tape (600 wide: the page in its panel, the panel's bar naming it), reached as a
// person does (设置 → 记忆 → Studio), as its old view is there.

///|
test "on the tape 一台 station 的记忆 made once: every instance and every word as its old view's; what it is for by one mark, the bar's" {
  let at = fn(made : Bool) raise {
    @sfdesk.pane_makes.val = made
    let t = tape_station_memory()
    let marks = t.semantics().filter(fn(n) { n.role == Button && n.label == @sf.t("web-main.about") }).length()
    let seen = (instances_sorted(t), words_where(t), marks)
    @sfdesk.pane_makes.val = true
    seen
  }
  let old = at(false)
  let made = at(true)
  same_drawn(made.1, old.1, "words")
  same_drawn(made.0, old.0, "instances")
  assert_eq((made.2, old.2), (1, 1), msg="its mark")
  let own = tree_words_drawn()
  assert_true(own.iter().any(fn(o) { o.contains("发布流程") }), msg="its rows the tree's: \{own}")
}

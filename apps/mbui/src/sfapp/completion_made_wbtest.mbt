// 归档建议 made once in the app's own frames (narrow_made, tape_made, pane_made), as a page of the settings and as a
// place of the bar's: what it holds the tree's own.

///|
test "归档建议 made once on each screen, as a page of the settings and as a place: the tree's own; its draft kept while 归档策略 is over it, dropped once as it is left" {
  for w in [390.0, 600.0, 800.0, 1000.0, 1280.0] {
    for entry in ["page", "place"] {
      let calls : Array[Made] = []
      let t = wide_tester(calls, mode="settings", w~, platform=if w < 600.0 { 2 } else { 0 })
      let at = "\{w} \{entry}"
      app.nav.replace(Settings)
      if entry == "page" {
        app.nav.push(Setting(@settings.Route::AutoCompletion))
      } else {
        app.nav.replace(Place("completion"))
      }
      @sfbase.show_chosen()
      t.run_for(@ui.move_most_ms)
      @sfdesk.bring_page()
      t.run_for(@ui.move_most_ms)
      let own = tree_words_drawn()
      for word in ["Willow", "GPT-6 mini", @sf.t("web-pages.automaticDecisions.enabled")] {
        assert_true(own.iter().any(fn(o) { o.contains(word) }), msg="\{word} not the tree's own at \{at}: \{Repr(own)}")
      }
      assert_eq(named(calls, "automaticDecisions.form.open").length(), 1, msg=at)
      // 归档策略 over it, as its row opens it: its draft kept; back to it, the same
      app.nav.push(Setting(@settings.Route::AutoPolicy("ws1/st1")))
      @sfbase.show_chosen()
      t.run_for(@ui.move_most_ms)
      assert_eq(named(calls, "automaticDecisions.form.drop").length(), 0, msg="\{at}: 归档策略 over it")
      app.nav.pop() |> ignore
      t.run_for(@ui.move_most_ms)
      assert_eq(named(calls, "automaticDecisions.form.open").length(), 1, msg="\{at}: back to it")
      assert_eq(named(calls, "automaticDecisions.form.drop").length(), 0, msg="\{at}: back to it")
      // left: dropped once
      app.nav.replace(Settings)
      t.run_for(@ui.move_most_ms)
      assert_eq(named(calls, "automaticDecisions.form.drop").length(), 1, msg="\{at}: left")
    }
  }
}

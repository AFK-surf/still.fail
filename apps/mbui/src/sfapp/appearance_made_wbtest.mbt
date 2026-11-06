// 外观 as a page of settings and as a place, made by each shell in the window's tree.

///|
test "外观 is the tree's own on each screen, from settings and as a place; its theme and haptics change the prefs" {
  for (w, platform) in [(390.0, 2), (390.0, 0), (600.0, 2), (800.0, 0), (1000.0, 2), (1280.0, 0)] {
    for entry in ["page", "place"] {
      let calls : Array[Made] = []
      let t = wide_tester(calls, mode="settings", w~, h=1600.0, platform~)
      app.nav.replace(Settings)
      if entry == "page" {
        app.nav.push(Setting(@settings.Route::Appearance))
      } else {
        app.nav.replace(Place("appearance"))
      }
      @sfbase.show_chosen()
      t.run_for(@ui.move_most_ms)
      @sfdesk.bring_page()
      t.run_for(@ui.move_most_ms)
      let at = "\{w} platform \{platform} \{entry}"
      let own = tree_words_drawn()
      for word in ["主题", "字体", "动画"] {
        assert_true(own.iter().any(fn(o) { o == word }), msg="\{at}: \{word} not the tree's own: \{own}")
      }
      let theme_title = tree_node_of("主题")
      t.click(Radio, label="浅色")
      t.frame()
      t.click(Radio, label="深色")
      t.frame()
      let set = named(calls, "prefs.set")
      assert_eq(text(Some(set[set.length() - 1].params), "appearance"), "dark", msg=at)
      assert_true(@sf.theme().dark, msg=at)
      assert_true(theme_title is Some(_) && tree_node_of("主题") == theme_title, msg="\{at}: the page stayed made")
      t.click(Switch, label="震动")
      t.frame()
      let set = named(calls, "prefs.set")
      assert_eq(text(Some(set[set.length() - 1].params), "haptics"), "off", msg=at)
    }
  }
}

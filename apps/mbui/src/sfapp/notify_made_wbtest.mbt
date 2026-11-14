// 通知 and 权限 made once in the app's own frames (narrow_made, tape_made, pane_made), as a page of the settings and as a
// place of the bar's: what each holds the tree's own; a kind's banner turned asks the core.

///|
test "通知 and 权限 made once on each screen, as a page of the settings and as a place: the tree's own; a kind's banner turned asks the core" {
  for w in [390.0, 600.0, 800.0, 1000.0, 1280.0] {
    for entry in ["page", "place"] {
      for name in ["notifications", "permissions"] {
        let route = if name == "notifications" { @settings.Route::Notifications } else { @settings.Route::Permissions }
        let calls : Array[Made] = []
        let t = wide_tester(calls, mode="settings", w~, platform=if w < 600.0 { 2 } else { 0 })
        let at = "\{w} \{entry} \{name}"
        // (opened as the settings' list opens it, or as the bar's place)
        app.nav.replace(Settings)
        if entry == "page" {
          app.nav.push(Setting(route))
        } else {
          app.nav.replace(Place(name))
        }
        @sfbase.show_chosen()
        t.run_for(@ui.move_most_ms)
        // (on the tape, the page brought over to be used: its cover pressed, bring_page)
        @sfdesk.bring_page()
        t.run_for(@ui.move_most_ms)
        let own = tree_words_drawn()
        let words = if route is Notifications {
          [@sf.t("web-pages.notifications.ways.title"), @sf.t("web-pages.notifications.kinds.wait")]
        } else {
          [@sf.t("web-pages.permissions.notify.purpose"), @sf.t("web-pages.permissions.state.granted")]
        }
        for word in words {
          assert_true(own.iter().any(fn(o) { o.contains(word) }), msg="\{word} not the tree's own at \{at}: \{Repr(own)}")
        }
        if route is Notifications {
          t.click(Button, label=@sf.t("web-pages.notifications.kinds.wait"))
          t.run_for(@ui.move_most_ms)
          t.click(Switch, label=@sf.t("web-pages.notifications.ways.banner"))
          t.frame()
          let set = named(calls, "notify.set")
          assert_eq(set.length(), 1, msg=at)
          assert_eq(field(field(Some(set[0].params), "kinds"), "wait"), Some(Json::boolean(false)), msg=at)
        }
      }
    }
  }
}

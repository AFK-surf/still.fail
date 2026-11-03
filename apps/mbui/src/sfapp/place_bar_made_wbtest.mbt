// A place's top bar over a page made once (place_top_bar_node): what the page does in it (用量's days and share), each
// its own as the workspace changes, none of a page gone; its name and settings.

///|
/// Place `place` on a phone (`w` × 900, a finger's), at the system's size of words `scale`.
fn place_bar_tester(
  place : String,
  wrap? : (Source) -> Source = fn(s) { s },
  w? : Double = 390.0,
  scale? : Double = 1.0,
) -> @ui.Tester {
  new_run()
  let src = wrap(fixture("settings"))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform=2)
  t.set_font_scale(scale)
  t.draw()
  app.nav.replace(Place(place))
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "用量 as a place on a phone: its days and its share in the place's top bar; 30 天 chosen there; another workspace, the share its; none, nothing of the one before" {
  let listed = @signals.signal(true)
  let shared : Array[String] = []
  @sfbase.share_card_of.val = fn(_, w) { shared.push(w.id) }
  let src : Ref[Source?] = Ref(None)
  let days : Array[String] = []
  let t = place_bar_tester("usage", wrap=fn(base) {
    let base = topic_asked(base, "usage", "days", days)
    let s : Source = {
      ..base,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name == "workspaces" && !listed.get() {
          return { ..got, value: Some(Json::array([])) }
        }
        got
      },
    }
    src.val = Some(s)
    s
  })
  // (the bar's: over what the page holds, under the status bar)
  guard t.rect_of("30 天") is Some((dx, dy, dw, dh)) else { fail("no days: \{t.drawn_text()}") }
  guard t.words().search_by(fn(w) { w.0 == place_label("usage") && w.5 > 0.5 }) is Some(i) else { fail("no name") }
  assert_true((t.words()[i].2 - dy).abs() < 20.0, msg="its days on the name's line")
  t.tap(dx + dw / 2.0, dy + dh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(days.last(), Some("30"), msg="\{days}")
  let share = fn() {
    t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == @sf.t("web-main.stations.shareCard") && !s.hidden })
  }
  guard share() is [b] else { fail("its share read out \{share().length()} times") }
  t.tap(b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  @sfbase.pick_workspace(src.val.unwrap(), "ws2")
  t.run_for(@ui.move_most_ms)
  guard share() is [b2] else { fail("its share read out \{share().length()} times in ws2") }
  t.tap(b2.rect.0 + b2.rect.2 / 2.0, b2.rect.1 + b2.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(shared, ["ws1", "ws2"])
  listed.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(share().length(), 0, msg="its share left over")
  assert_true(t.rect_of("30 天") is None, msg="its days left over")
  @sfbase.share_card_of.val = fn(_, _) {  }
}

///|
test "价目表 as a place on a phone: the place's name over it, settings in its top bar, its cards under it" {
  let t = place_bar_tester("prices:7")
  guard t.words().search_by(fn(w) { w.0 == place_label("prices:7") && w.5 > 0.5 }) is Some(i) else { fail("no name") }
  let settings = t.get(Button, label=tr("android-chat.home.settings"))
  assert_true(settings.rect.1 < 120.0 && (settings.rect.1 - t.words()[i].2).abs() < 30.0, msg="settings in the bar")
  t.tap(settings.rect.0 + settings.rect.2 / 2.0, settings.rect.1 + settings.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Settings, msg="settings opened")
}

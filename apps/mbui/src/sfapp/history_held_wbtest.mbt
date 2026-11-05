// What a history's details read (the station's `host`, sfbase held.mbt) is held while its page is on the stack, covered
// or not, and left once, as the last page of it leaves: never for a page pushed over it, nor for the same history
// pushed over itself and gone back from.

///|
test "a history's details hold the station's figures while a page covers it and the same history over it is gone back from, left as it leaves" {
  new_run()
  let base = fixture("chat")
  let left : Array[String] = []
  let src : Source = {
    ..base,
    leave: fn(name, params) {
      if name == "host" {
        left.push(name)
      }
      (base.leave)(name, params)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let details = fn() {
    t.tap_text(tr("android-chat.history.tab.details"))
    t.run_for(@ui.move_most_ms)
  }
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  details()
  // a page over it: it is still on the stack, what it read held
  app.nav.push(Settings)
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(left, [], msg="covered by settings and gone back to")
  // the same history over it, its details read too, gone back from: the one under it still shows them
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  details()
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(left, [], msg="the same history over it gone back from")
  // the last of it left: left, once
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_eq(left, ["host"])
}

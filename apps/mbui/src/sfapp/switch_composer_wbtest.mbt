// Another chat chosen in the sidebar on a large screen: the page changes, its composer is where the composer was, the
// same shape; nothing of it moves for the change (motion.md: a place or a size moves only for its cause, and choosing
// another chat is no cause of the composer's). 2026-11-05: on a desktop the composer played its motion as chats were
// switched.

///|
/// The composer's glass, send and placeholder, as each frame drew them.
fn switch_composer_seen(t : @ui.Tester) -> String {
  match t.query(Button, label=@sf.t("web-main.composer.send")) {
    Some(s) => {
      let cx = s.rect.0 + s.rect.2 / 2.0
      let cy = s.rect.1 + s.rect.3 / 2.0
      let glass = t.drawn_glass().filter(fn(g) { cx >= g.0 && cx <= g.0 + g.2 && cy >= g.1 && cy <= g.1 + g.3 })
      let g = glass.get(0).map(fn(g) { "\{(g.0, g.1, g.2, g.3)}" }).unwrap_or("none")
      let hint = t.words().filter(fn(w) { w.0 == "发消息" }).get(0).map(fn(w) { "\{(w.1, w.2)}" }).unwrap_or("none")
      "send \{s.rect}, glass \{g}, hint \{hint}"
    }
    None => "no send"
  }
}

///|
test "choosing another chat in a large screen's sidebar moves nothing of the composer, and choosing it back neither" {
  let out : Array[String] = []
  let (w, h) = (1280.0, 800.0)
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w~, h~, platform=0)
  t.set_frame_period(1000.0 / 60.0)
  t.run_for(@ui.move_most_ms)
  let before = switch_composer_seen(t)
  assert_true(before != "no send", msg="the starting chat has a composer")
  assert_true(!before.contains("hint none"), msg="the starting chat has its placeholder")
  assert_eq(t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none"), "TextField 发消息")
  for name in ["夜里的构建又失败了", "整理发布清单"] {
    let (x, y) = match t.find(name) {
      Some(p) => p
      None => abort("no \{name} in the sidebar")
    }
    let seen : Array[String] = []
    t.each_frame(Some(fn() { seen.push(switch_composer_seen(t)) }))
    t.touch_at(0, x, y, t.time())
    t.touch_at(2, x, y, t.time())
    t.run_as_host(@ui.move_most_ms)
    t.each_frame(None)
    assert_eq(t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none"), "TextField 发消息", msg="the chosen chat has the cursor")
    let moved = seen.filter(fn(s) { s != before })
    if !moved.is_empty() {
      let last = seen.last().unwrap_or("")
      out.push("\{name} chosen: \{moved.length()} of \{seen.length()} frames drew the composer otherwise than \{before}: first \{moved[0]}, last \{last}")
    }
  }
  assert_eq(out, [])
}

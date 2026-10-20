// Links in a message (messages.mbt open_link, link_menu.mbt): a tap hands an address to the system, a chat's own link
// opens it here; held, its menu.

///|
test "a bare address tapped is handed to the system; one to a chat opens it here" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.move(195.0, 400.0)
  for _ in 0..<8 {
    if t.run_rects("example.com/bench/list").length() > 0 {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_run("https://example.com/bench/list")
  assert_eq(t.opened(), ["https://example.com/bench/list"])
  let depth = app.nav.depth()
  t.tap_run("首页的列表改成按天分组")
  assert_eq(app.nav.depth(), depth + 1)
  assert_eq(t.opened().length(), 1)
}

///|
test "a link held still: its menu (打开链接, 复制链接), the link not followed" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.move(195.0, 400.0)
  for _ in 0..<8 {
    if t.run_rects("example.com/bench/list").length() > 0 {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  let (x, y, w, h) = t.run_rects("example.com/bench/list")[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq(t.opened().length(), 0)
  assert_true(t.find("打开链接") is Some(_))
  // no words picked by the same press
  assert_eq(pk.ts, "")
  t.tap_text("复制链接")
  assert_eq(t.clipboard(), "https://example.com/bench/list")
  assert_true(t.find("已复制链接") is Some(_))
  assert_true(!link_menu.open)
  // gone on the menus' spring
  t.run_for(@motion.menu_spring.duration(1.0, 0.0, 0.0))
  assert_true(t.find("打开链接") is None)
}

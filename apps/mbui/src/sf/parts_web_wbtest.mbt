// The parts as the web's parts.tsx and parts.css.ts make them: their sizes and what they do.

///|
/// A wide window's view of the library's parts, in still.fail's wide theme.
fn wide_view(body : (@ui.Ctx) -> Unit) -> (@ui.Ctx) -> Unit {
  fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() { c.box(w=Fill(1.0), h=Fill(1.0), fn() { body(c) }) |> ignore })
  }
}

///|
test "a switch: 36 by 22 (small 26 by 16), turned by a click, the accent on and the strong line's grey off" {
  let on = Ref(false)
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      c.box(dir=Row, fn() {
        on.val = switch(c, "s", on.val, label="提醒")
        switch(c, "small", false, label="小", small=true) |> ignore
      })
      |> ignore
    }),
    w=800.0,
    h=600.0,
  )
  t.draw()
  let s = t.get(Switch, label="提醒")
  assert_eq((s.rect.2, s.rect.3), (switch_w, switch_h))
  assert_eq((t.get(Switch, label="小").rect.2, t.get(Switch, label="小").rect.3), (switch_small_w, switch_small_h))
  t.click(Switch, label="提醒")
  assert_true(on.val)
  t.click(Switch, label="提醒")
  assert_true(!on.val)
}

///|
test "a switch's row: its words turn it as its switch does" {
  let on = Ref(false)
  let t = @ui.Tester::new(
    wide_view(fn(c) { on.val = switch_row(c, "preview", "预览", on.val, note="通知里显示消息的内容") }),
    w=800.0,
    h=600.0,
  )
  t.draw()
  match t.find("预览") {
    Some((x, y)) => t.tap(x, y)
    None => fail("no words")
  }
  assert_true(on.val)
  t.click(Switch, label="预览")
  assert_true(!on.val)
}

///|
test "a pill is 22 high; a status dot 7 round, online in the online green, offline a ring" {
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      c.box(dir=Row, gap=8.0, align=ACenter, fn() {
        pill(c, "在线", tone=Green)
        status_dot(c, "online")
        status_dot(c, "offline")
      })
      |> ignore
    }),
    w=800.0,
    h=600.0,
  )
  t.draw()
  match t.rect_of("在线") {
    Some((_, _, _, h)) => assert_true(h <= pill_h)
    None => fail("no pill")
  }
  let dots = t.drawn_rects().filter(fn(r) { r.2 == 7.0 && r.3 == 7.0 })
  assert_true(dots.iter().any(fn(r) { r.4 == wide_light.online }))
}

///|
test "a dialog: 520 wide, its title and its lead, what it holds; its close button closes it" {
  let open = Ref(true)
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      open.val = dialog(
        c,
        "d",
        open.val,
        "跳转到",
        fn() { c.text("路径", size=13.0) |> ignore },
        description="输入路径",
        close_label="关闭",
      )
    }),
    w=1280.0,
    h=800.0,
  )
  t.draw()
  let d = t.get(Dialog, label="跳转到")
  assert_eq(d.rect.2, dialog_w)
  assert_true(t.find("输入路径") is Some(_))
  assert_true(t.find("路径") is Some(_))
  // its title 24 under its top, in a row as high as the close button
  match t.rect_of("跳转到") {
    Some((_, ty, _, th)) => assert_true(ty >= d.rect.1 + 24.0 && ty + th <= d.rect.1 + 24.0 + 32.0 + 1.0)
    None => fail("no title")
  }
  t.click(Button, label="关闭")
  assert_true(!open.val)
}

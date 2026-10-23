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

///|
/// A column 240 wide by a window's height with its edge (ResizeHandle) on its right, its width as the edge says; what
/// the edge was done with, each time it was done with something.
fn edge_view(width : Ref[Double], said : Array[Resized]) -> (@ui.Ctx) -> Unit {
  wide_view(fn(c) {
    c.box(dir=Row, h=Fill(1.0), fn() {
      c.box(w=Px(width.val), h=Fill(1.0), fn() {
        let r = resize_handle(c, "column", width.val, min=160.0, max=640.0, label="调整列宽", over=true)
        match r {
          Dragging(w) | Dropped(w) => width.val = w
          _ => ()
        }
        if r != Untouched {
          said.push(r)
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
test "a column's edge: 7 wide, 4 past the column; dragged past 3, the width from where it was pressed, 160 to 640" {
  let width = Ref(240.0)
  let said : Array[Resized] = []
  let t = @ui.Tester::new(edge_view(width, said), w=1280.0, h=800.0)
  t.draw()
  let e = t.get(Separator, label="调整列宽")
  assert_eq((e.rect.0, e.rect.2, e.rect.3), (240.0 + handle_out - handle_w, handle_w, 800.0))
  let x = e.rect.0 + 3.0
  t.press_at(x, 400.0)
  t.move(x + 2.0, 400.0)
  assert_eq(width.val, 240.0)
  assert_eq(said.length(), 0)
  t.move(x + 50.0, 400.0)
  assert_eq(width.val, 290.0)
  // the edge under the pointer in the frame it moved in
  assert_eq(t.get(Separator, label="调整列宽").rect.0, x + 50.0 - 3.0)
  t.move(x + 1000.0, 400.0)
  assert_eq(width.val, 640.0)
  t.move(x - 500.0, 400.0)
  assert_eq(width.val, 160.0)
  t.move(x + 60.4, 400.0)
  assert_eq(width.val, 300.0)
  t.release(x + 60.4, 400.0)
  assert_eq(said[said.length() - 1], Dropped(300.0))
  assert_eq(t.get(Separator, label="调整列宽").rect.0, 300.0 + handle_out - handle_w)
}

///|
test "a column's edge pressed without moving is Pressed, the second of two clicks Twice" {
  let width = Ref(240.0)
  let said : Array[Resized] = []
  let t = @ui.Tester::new(edge_view(width, said), w=1280.0, h=800.0)
  t.draw()
  let e = t.get(Separator, label="调整列宽")
  t.tap(e.rect.0 + 3.0, 400.0)
  assert_eq(said, [Pressed])
  t.tap(e.rect.0 + 3.0, 400.0)
  assert_eq(said, [Pressed, Twice])
  assert_eq(width.val, 240.0)
}

///|
test "a column's edge: its bar 24 high over the column, 48 on the edge once its move is done; its words by the pointer" {
  let width = Ref(240.0)
  let said : Array[Resized] = []
  let t = @ui.Tester::new(edge_view(width, said), w=1280.0, h=800.0)
  let bar = fn() {
    t.drawn_rects().filter(fn(r) { r.2 == edge_bar_w }).map(fn(r) { r.3 })
  }
  t.move(100.0, 400.0)
  t.run_for(edge_bar_ms)
  assert_eq(bar(), [24.0])
  assert_true(t.find("调整列宽") is None)
  let e = t.get(Separator, label="调整列宽")
  t.move(e.rect.0 + 3.0, 300.0)
  t.run_for(edge_bar_ms)
  assert_eq(bar(), [48.0])
  // its words 300 ms after the pointer came (and in), 14 right of it, their middle level with it, following it down
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  match t.rect_of("调整列宽") {
    Some((wx, wy, _, wh)) => {
      assert_true(wx >= e.rect.0 + 3.0 + edge_tip_gap, msg=wx.to_string())
      assert_true((wy + wh / 2.0 - 300.0).abs() <= 1.0, msg=(wy + wh / 2.0).to_string())
    }
    None => fail("no tip")
  }
  t.move(e.rect.0 + 3.0, 500.0)
  t.frame()
  match t.rect_of("调整列宽") {
    Some((_, wy, _, wh)) => assert_true((wy + wh / 2.0 - 500.0).abs() <= 1.0, msg=(wy + wh / 2.0).to_string())
    None => fail("the tip went")
  }
}

///|
test "a column's edge's words go as it is pressed, and come again only once the pointer has left it and come back" {
  let width = Ref(240.0)
  let said : Array[Resized] = []
  let t = @ui.Tester::new(edge_view(width, said), w=1280.0, h=800.0)
  t.draw()
  let x = t.get(Separator, label="调整列宽").rect.0 + 3.0
  t.move(x, 300.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is Some(_))
  t.press_at(x, 300.0)
  t.move(x + 40.0, 300.0)
  t.release(x + 40.0, 300.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is None)
  t.move(100.0, 300.0)
  t.frame()
  t.move(x + 40.0, 300.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is Some(_))
}

///|
test "a column's edge's words stay away after it is dragged by many moves, the pointer resting on it" {
  let width = Ref(240.0)
  let said : Array[Resized] = []
  let t = @ui.Tester::new(edge_view(width, said), w=1280.0, h=800.0)
  t.draw()
  let x = t.get(Separator, label="调整列宽").rect.0 + 3.0
  t.move(x, 300.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is Some(_))
  t.drag(x, 300.0, x + 80.0, 300.0, steps=36)
  assert_eq(width.val, 320.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is None)
}

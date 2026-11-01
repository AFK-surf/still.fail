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
test "a switch: 36 by 22 (small 26 by 16), pressed within a finger's least round it, turned by a click, the accent on and the strong line's grey off" {
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
  // (drawn its size, pressed as high as a finger's least: the room it takes is its press's)
  let reach = theme().items.least
  let s = t.get(Switch, label="提醒")
  assert_eq((s.rect.2, s.rect.3), (switch_w, dmax(switch_h, reach)))
  let small = t.get(Switch, label="小")
  assert_eq((small.rect.2, small.rect.3), (switch_small_w, dmax(switch_small_h, reach)))
  t.click(Switch, label="提醒")
  assert_true(on.val)
  t.click(Switch, label="提醒")
  assert_true(!on.val)
}

///|
test "a switch held long by a finger is still its press: let go, turned" {
  let on = Ref(false)
  let t = @ui.Tester::new(
    wide_view(fn(c) { c.box(fn() { on.val = switch(c, "s", on.val, label="提醒") }) |> ignore }),
    w=800.0,
    h=600.0,
    platform=2,
  )
  t.draw()
  let (x, y, w, h) = t.get(Switch, label="提醒").rect
  t.press_at(x + w / 2.0, y + h / 2.0)
  // (held past a long press: a hold on it is still the switch's)
  t.run_for(@ui.long_press_ms * 2.0)
  t.release(x + w / 2.0, y + h / 2.0)
  assert_true(on.val)
  // (turned by a finger, felt: a light tick)
  assert_eq(t.haptics(), [@ui.TextHandleMove])
}

///|
test "a switch's row: its switch alone turns it, not its words" {
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
  assert_true(!on.val, msg="its words take no press (2026-10-27)")
  t.click(Switch, label="预览")
  assert_true(on.val)
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
  assert_true(dots.iter().any(fn(r) { r.4 == light_palette.online }))
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
test "a dialog taller than the window leaves: at most the window less 48, its buttons in it, what it holds scrolling" {
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      dialog(
        c,
        "long",
        true,
        "快捷键",
        fn() {
          for i in 0..<40 {
            c.text("第 \{i} 行", size=13.0) |> ignore
          }
        },
        footer=fn() { button(c, "修改", key="long/change") |> ignore },
      )
      |> ignore
    }),
    w=1280.0,
    h=600.0,
  )
  t.draw()
  let d = t.get(Dialog, label="快捷键")
  assert_true(d.rect.3 <= 600.0 - 48.0 + 0.5, msg="\{d.rect.3} tall")
  match t.rect_of("修改") {
    Some((_, y, _, h)) => assert_true(y + h <= d.rect.1 + d.rect.3, msg="its button inside it")
    None => fail("no button")
  }
  // the first lines shown, the last not until it is scrolled
  assert_true(t.find("第 0 行") is Some(_))
  match t.rect_of("第 39 行") {
    Some((_, y, _, _)) => assert_true(y >= d.rect.1 + d.rect.3, msg="the last line under the dialog's end")
    None => ()
  }
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
test "a column's edge: 7 wide, 4 past the column; dragged past the slop, the width from where it was pressed, 160 to 640, felt at either" {
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
  assert_eq(t.haptics(), [])
  // at either end, felt as it gets there, once while it stays
  t.move(x + 1000.0, 400.0)
  assert_eq(width.val, 640.0)
  t.move(x + 1100.0, 400.0)
  assert_eq(t.haptics(), [@ui.TextHandleMove])
  t.move(x - 500.0, 400.0)
  assert_eq(width.val, 160.0)
  assert_eq(t.haptics(), [@ui.TextHandleMove, @ui.TextHandleMove])
  t.move(x + 60.4, 400.0)
  assert_eq(width.val, 300.0)
  assert_eq(t.haptics().length(), 2)
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

///|
test "a list's row in a side column: what stands at its first line's end in one column with what stands in its foot's end corner" {
  let l = theme().chat_list
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      c.box(w=Px(280.0), fn() {
        list_row(
          c,
          c.id("row"),
          Side,
          0L,
          high=true,
          end_slot=16.0,
          // (an agent's mark last in the corner, 16 wide)
          corner=fn() { c.box(w=Px(16.0), h=Px(16.0), bg=0x00FF00FFL, fn() {  }) |> ignore },
          corner_w=16.0,
          corner_end=16.0,
          fn() {
            c.box(style=@ui.css("w=Full"), fn() {  }) |> ignore
            c.box(w=Px(16.0), h=Px(16.0), bg=0xFF0000FFL, fn() {  }) |> ignore
          },
          fn() {  },
        )
        |> ignore
      })
      |> ignore
    }),
    w=800.0,
    h=600.0,
    // (squares standing in for its marks: the corner rule not held of them)
    corners_held=false,
  )
  t.draw()
  let at = fn(color : Int64) {
    match t.drawn_rects().search_by(fn(r) { r.4 == color }) {
      Some(i) => {
        let r = t.drawn_rects()[i]
        r.0 + r.2 / 2.0
      }
      None => -1.0
    }
  }
  let end = at(0xFF0000FFL)
  let corner = at(0x00FF00FFL)
  assert_true(end > 0.0 && corner > 0.0, msg="\{t.drawn_rects()}")
  assert_true((end - corner).abs() < 0.5, msg="the first line's end at \{end}, the corner's at \{corner}")
}

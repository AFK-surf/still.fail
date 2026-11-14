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
test "a long status stays a one-line pill" {
  let words = "A very long status that does not fit in the row"
  let t = @ui.Tester::new(
    wide_view(fn(c) { c.box(w=Px(120.0), fn() { pill(c, words) }) |> ignore }),
    w=800.0,
    h=600.0,
  )
  t.draw()
  let lines = t.lines_of(words)
  assert_eq(lines.length(), 1, msg="\{Repr(lines)}")
  assert_true(lines[0].has_suffix("…"), msg="\{Repr(lines)}")
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
        on_close=fn() { open.val = false },
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
        let r = resize_handle(c, "column", width.val, min=160.0, max=640.0, label="调整列宽", over=true, pressed=fn() {
          said.push(Pressed)
        }, twice=fn() { said.push(Twice) })
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
  t.move_to(x + 2.0, 400.0)
  assert_eq(width.val, 240.0)
  assert_eq(said.length(), 0)
  t.move_to(x + 50.0, 400.0)
  assert_eq(width.val, 290.0)
  // the edge under the pointer in the frame it moved in
  assert_eq(t.get(Separator, label="调整列宽").rect.0, x + 50.0 - 3.0)
  assert_eq(t.haptics(), [])
  // at either end, felt as it gets there, once while it stays
  t.move_to(x + 1000.0, 400.0)
  assert_eq(width.val, 640.0)
  t.move_to(x + 1100.0, 400.0)
  assert_eq(t.haptics(), [@ui.TextHandleMove])
  t.move_to(x - 500.0, 400.0)
  assert_eq(width.val, 160.0)
  assert_eq(t.haptics(), [@ui.TextHandleMove, @ui.TextHandleMove])
  t.move_to(x + 60.4, 400.0)
  assert_eq(width.val, 300.0)
  assert_eq(t.haptics().length(), 2)
  t.release(x + 60.4, 400.0)
  assert_eq(said[said.length() - 1], Dropped(300.0))
  assert_eq(t.get(Separator, label="调整列宽").rect.0, 300.0 + handle_out - handle_w)
}

///|
test "a column's edge pressed without moving does `pressed`, the second of two clicks `twice` in its place" {
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
  t.move_to(100.0, 400.0)
  t.run_for(edge_bar_ms)
  assert_eq(bar(), [24.0])
  assert_true(t.find("调整列宽") is None)
  let e = t.get(Separator, label="调整列宽")
  t.move_to(e.rect.0 + 3.0, 300.0)
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
  t.move_to(e.rect.0 + 3.0, 500.0)
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
  t.move_to(x, 300.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is Some(_))
  t.press_at(x, 300.0)
  t.move_to(x + 40.0, 300.0)
  t.release(x + 40.0, 300.0)
  t.run_for(edge_tip_ms)
  t.run_for(edge_tip_ms)
  assert_true(t.find("调整列宽") is None)
  t.move_to(100.0, 300.0)
  t.frame()
  t.move_to(x + 40.0, 300.0)
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
  t.move_to(x, 300.0)
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
  assert_true(end > 0.0 && corner > 0.0, msg="\{Repr(t.drawn_rects())}")
  assert_true((end - corner).abs() < 0.5, msg="the first line's end at \{end}, the corner's at \{corner}")
}

///|
test "a list's row as a node in a side column: what stands at its first line's end in one column with what stands in its foot's end corner" {
  // (a mouse's and a finger's sizes; in the corner last an agent's mark, 16 wide, or a face)
  for platform in [0, 2] {
    for last in [16.0, 0.0] {
      let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=800.0, h=600.0, platform~, corners_held=false)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(ui_theme_now)
        root.box(fn(holder) {
          holder.width(Is(Some(280.0))) |> ignore
          holder.box(fn(row) {
            let square = fn(s : @view.View, color : Int64, side : Double) {
              s.width(Is(Some(side))).height(Is(Some(side))).ground(Is(color)) |> ignore
            }
            list_row_node(
              row,
              Side,
              high=true,
              end_slot=16.0,
              corner=fn(k) { k.box(fn(s) { square(s, 0x00FF00FFL, if last > 0.0 { last } else { theme().chat_list.face_d }) }) |> ignore },
              corner_w=fn() { 16.0 },
              corner_end=fn() { last },
              fn(h) {
                h.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
                h.box(fn(s) { square(s, 0xFF0000FFL, 16.0) }) |> ignore
              },
              fn(_) {  },
            )
          })
          |> ignore
        })
        |> ignore
      })
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
      assert_true(end > 0.0 && corner > 0.0, msg="\{Repr(t.drawn_rects())}")
      assert_true((end - corner).abs() < 0.5, msg="platform \{platform}, last \{last}: the first line's end at \{end}, the corner's at \{corner}")
    }
  }
}

///|
test "a list's row as a node: its lines as high as their words' lines at the system's size of words, nothing over another, its mark across its first line's middle, a chat's row higher by as much as they are" {
  // (a mouse's and a finger's sizes; the default size of words and a phone's set larger; a row as high as what it
  // holds, its mark beside its first line, and a chat's row, as high as the theme says)
  let rows : Map[String, Double] = Map([])
  for platform in [0, 2] {
    for high in [false, true] {
      for scale in [1.0, 1.3] {
        let at = "platform \{platform}, high \{high}, at \{scale}"
        let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=800.0, h=600.0, platform~, corners_held=false)
        if scale != 1.0 {
          t.set_font_scale(scale)
        }
        @ui.set_view_app(fn(root) {
          @ui.set_tree_theme(ui_theme_now)
          root.box(fn(holder) {
            holder.width(Is(Some(280.0))) |> ignore
            holder.box(fn(row) {
              list_row_node(
                row,
                Whole,
                high~,
                ground=fn() { 0x00FF00FFL },
                mark?=if high {
                  None
                } else {
                  Some(fn(k : @view.View) {
                    k.box(fn(s) { s.width(Is(Some(8.0))).height(Is(Some(8.0))).ground(Is(0xFF0000FFL)) |> ignore })
                    |> ignore
                  })
                },
                fn(h) { words_node(h, fn() { "整理发布清单" }, fn() { theme().chat_list.title }) |> ignore },
                fn(u) {
                  list_row_line_node(u, fn(l) { words_node(l, fn() { "正在核对第三项" }, fn() { theme().chat_list.last }) |> ignore })
                },
              )
            })
            |> ignore
          })
          |> ignore
        })
        t.run_for(@ui.move_most_ms)
        assert_eq(t.squeeze_faults(), [], msg="\{at}: \{Repr(t.squeeze_faults())}")
        let word = fn(s : String) {
          match t.words().search_by(fn(w) { w.0 == s }) {
            Some(i) => t.words()[i]
            None => ("", 0.0, 0.0, 0.0, 0.0, 0.0)
          }
        }
        let title = word("整理发布清单")
        let under = word("正在核对第三项")
        assert_true(title.4 > 0.0 && under.4 > 0.0, msg="\{at}: \{Repr(t.words())}")
        // (the line under it starts no higher than where its title's line ends)
        assert_true(under.2 >= title.2 + title.4 - 0.5, msg="\{at}: its title at \{Repr(title)}, the line under it at \{Repr(under)}")
        guard t.drawn_rects().search_by(fn(r) { r.4 == 0x00FF00FFL }) is Some(g) else { fail("\{at}: no row") }
        let ground = t.drawn_rects()[g]
        rows["\{platform} \{high} \{scale}"] = ground.3
        if high {
          // (as high as the theme says at the default size of words)
          if scale == 1.0 {
            assert_eq(ground.3, theme().chat_list.row_h, msg=at)
          }
        } else {
          // (its mark across its title's middle)
          guard t.drawn_rects().search_by(fn(r) { r.4 == 0xFF0000FFL }) is Some(i) else { fail("\{at}: no mark") }
          let mark = t.drawn_rects()[i]
          assert_true(
            (mark.1 + mark.3 / 2.0 - (title.2 + title.4 / 2.0)).abs() < 0.5,
            msg="\{at}: its mark at \{Repr(mark)}, its title at \{Repr(title)}",
          )
        }
      }
      // (higher at 1.3, by as much as its two lines' words are)
      let (lo, hi) = (rows.get("\{platform} \{high} 1").unwrap_or(0.0), rows.get("\{platform} \{high} 1.3").unwrap_or(0.0))
      assert_true(hi > lo + 4.0, msg="platform \{platform}, high \{high}: \{lo} at the default size, \{hi} at 1.3")
    }
  }
}

///|
test "a chat's rows as nodes: as high as each other whatever their second lines say, following the system's size of words as it changes" {
  // (a mouse's and a finger's sizes; a row whose second line says something and one whose says nothing, at the default
  // size, then the system's set to 1.3, then back)
  for platform in [0, 2] {
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=800.0, h=600.0, platform~, corners_held=false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(holder) {
        holder.width(Is(Some(280.0))) |> ignore
        for said in [("正在核对第三项", 0x00FF00FFL), ("", 0x0000FFFFL)] {
          holder.box(fn(row) {
            list_row_node(
              row,
              Whole,
              high=true,
              ground=fn() { said.1 },
              fn(h) { words_node(h, fn() { "整理发布清单" }, fn() { theme().chat_list.title }) |> ignore },
              fn(u) {
                list_row_line_node(u, fn(l) { words_node(l, fn() { said.0 }, fn() { theme().chat_list.last }) |> ignore })
              },
            )
          })
          |> ignore
        }
      })
      |> ignore
    })
    let heights = fn(at : String) -> (Double, Double) raise {
      t.run_for(@ui.move_most_ms)
      assert_eq(t.squeeze_faults(), [], msg="\{at}: \{Repr(t.squeeze_faults())}")
      let high = fn(color : Int64) -> Double raise {
        match t.drawn_rects().search_by(fn(r) { r.4 == color }) {
          Some(i) => t.drawn_rects()[i].3
          None => fail("\{at}: no row of \{color}")
        }
      }
      (high(0x00FF00FFL), high(0x0000FFFFL))
    }
    let row_h = theme().chat_list.row_h
    let at = "platform \{platform}"
    let (said, none) = heights("\{at} at the default size")
    assert_eq(said, row_h, msg=at)
    assert_eq(none, row_h, msg=at)
    t.set_font_scale(1.3)
    let (said, none) = heights("\{at} at 1.3")
    assert_true(said > row_h + 4.0, msg="\{at} at 1.3: \{said}, the theme's \{row_h}")
    assert_eq(none, said, msg="\{at} at 1.3: what says nothing under its title as high as what says something")
    t.set_font_scale(1.0)
    let (said, none) = heights("\{at} back at the default size")
    assert_eq(said, row_h, msg=at)
    assert_eq(none, row_h, msg=at)
  }
}

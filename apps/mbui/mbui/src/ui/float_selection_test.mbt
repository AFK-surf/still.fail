// A floating bar covers selectable words in the same layer, without covering its own words or words beside it.

///|
test "a floating bar only lets a press pick its own words" {
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.selectable(fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          c.column(gap=40.0, fn() {
            c.rich([@ui.plain("covered words here")], size=15.0) |> ignore
            c.rich([@ui.plain("free words here")], size=15.0) |> ignore
          })
          |> ignore
          c.layer(fn() {
            let id = c.id("floating-bar")
            let bar = c.box(w=Px(260.0), h=Px(30.0), id~, fn() {
              c.row(w=Fill(1.0), h=Fill(1.0), fn() {
                c.box(w=Px(140.0), h=Px(30.0), fn() {  }) |> ignore
                c.rich([@ui.plain("bar words")], size=15.0) |> ignore
              })
              |> ignore
            })
            c.semantics(bar, Button, id~, label="floating bar")
            c.floats_over(bar)
          })
          |> ignore
        })
        |> ignore
      })
    },
    w=300.0,
    h=180.0,
  )
  t.draw()
  let (x, y, _, h) = t.run_rects("covered words here")[0]
  let (bx, by, bw, bh) = t.get(Button, label="floating bar").rect
  assert_true(x + 2.0 >= bx && x + 2.0 < bx + bw && y + h / 2.0 >= by && y + h / 2.0 < by + bh, msg="the bar covers the words")
  let made = t.ctx().selection_made()
  t.press_at(x + 2.0, y + h / 2.0)
  assert_eq(t.ctx().selection_made(), made, msg="a press on the bar cannot begin picking the covered words")
  t.release(x + 2.0, y + h / 2.0)
  let (fx, fy, fw, fh) = t.run_rects("free words here")[0]
  t.drag(fx + 1.0, fy + fh / 2.0, fx + fw - 1.0, fy + fh / 2.0)
  assert_eq(t.ctx().selected_text(), "free words here")
  let (tx, ty, tw, th) = t.run_rects("bar words")[0]
  t.drag(tx + 1.0, ty + th / 2.0, tx + tw - 1.0, ty + th / 2.0)
  assert_eq(t.ctx().selected_text(), "bar words")
  t.drag(fx + 1.0, fy + fh / 2.0, tx + tw - 1.0, ty + th / 2.0)
  assert_false(t.ctx().selected_text().contains("bar words"), msg="a drag from the page does not pick the bar's words")
}

///|
test "a finger's hold on a floating bar cannot pick the words behind it" {
  let t = @ui.Tester::new(
    fn(c) {
      c.selectable(fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          c.rich([@ui.plain("covered words here")], size=15.0) |> ignore
          c.layer(fn() {
            let bar = c.box(w=Px(260.0), h=Px(30.0), fn() {
              c.row(fn() {
                c.box(w=Px(140.0), h=Px(30.0), fn() {  }) |> ignore
                c.rich([@ui.plain("bar words")], size=15.0) |> ignore
              }) |> ignore
            })
            c.floats_over(bar)
          }) |> ignore
        }) |> ignore
      })
    },
    w=300.0,
    h=180.0,
    platform=2,
  )
  t.draw()
  let (x, y, _, h) = t.run_rects("covered words here")[0]
  let made = t.ctx().selection_made()
  t.press_at(x + 2.0, y + h / 2.0)
  t.run_for(@ui.long_press_ms)
  assert_eq(t.ctx().selection_made(), made)
  assert_eq(t.ctx().selected_text(), "")
  t.release(x + 2.0, y + h / 2.0)
  let (tx, ty, _, th) = t.run_rects("bar words")[0]
  t.press_at(tx + 2.0, ty + th / 2.0)
  t.run_for(@ui.long_press_ms)
  assert_eq(t.ctx().selected_text(), "bar")
  t.release(tx + 2.0, ty + th / 2.0)
}

///|
test "a floating bar keeps its selection when something is inserted before it" {
  let inserted = @signals.signal(false)
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.selectable(fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          c.rich([@ui.plain("behind")], key="behind", size=15.0) |> ignore
          if inserted.get() {
            c.box(w=Px(0.0), h=Px(0.0), fn() {  }) |> ignore
          }
          c.layer(fn() {
            let bar = c.box(w=Px(260.0), h=Px(30.0), fn() {
              c.rich([@ui.plain("bar words")], key="bar", size=15.0) |> ignore
            })
            c.floats_over(bar)
          }) |> ignore
        }) |> ignore
      })
    },
    w=300.0,
    h=180.0,
  )
  t.draw()
  let (x, y, w, h) = t.run_rects("bar words")[0]
  t.press_at(x + 1.0, y + h / 2.0)
  inserted.set(true)
  t.draw()
  t.move(x + w - 1.0, y + h / 2.0)
  t.release(x + w - 1.0, y + h / 2.0)
  assert_eq(t.ctx().selected_text(), "bar words")
}

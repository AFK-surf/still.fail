// What scrolls shows where it is with one bar (scroll_bar.mbt): its look and place, when it shows, the pointer at it
// and on its thumb, none for a finger, and the boxes that scroll inside a list.

///|
/// A list of 200 rows 40 high (8000 in all), each row pressable: what was pressed, the rows' presses.
fn bar_rows(pressed : Array[Int], over_foot? : Double = 0.0, corner? : Double = 0.0) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), radius=corner, clip=corner > 0.0, fn() {
      c.list("list", 200, 40.0, fn(i) {
        let id = c.id("row")
        if c.clicked(id) {
          pressed.push(i)
        }
        c.box(w=Fill(1.0), h=Px(40.0), id~, fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
      // what floats over its foot (a composer)
      if over_foot > 0.0 {
        c.layer(fn() {
          c.spacer()
          let b = c.box(w=Fill(1.0), h=Px(over_foot), fn() {  })
          c.floats_over(b)
        })
        |> ignore
      }
    })
    |> ignore
  }
}

///|
/// The thumbs drawn (3 wide, or 3 high along a foot): x, y, w, h, colour.
fn thumbs(t : @ui.Tester) -> Array[(Double, Double, Double, Double, Int64)] {
  t.drawn_rects().filter(fn(r) { r.2 == @ui.scroll_bar_size || r.3 == @ui.scroll_bar_size })
}

///|
test "scroll bar: a list scrolled shows a thumb 3 wide, 2 in from its right, in the words' colour at 26%, and goes" {
  let t = @ui.Tester::new(bar_rows([]), w=300.0, h=400.0)
  assert_eq(thumbs(t).length(), 0)
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, 300.0)
  // come in over its fade
  t.run_for(@ui.scrollbar_fade_ms)
  let shown = thumbs(t)
  assert_eq(shown.length(), 1, msg="\{shown}")
  let (x, y, w, h, colour) = shown[0]
  assert_eq(x, 300.0 - 2.0 - 3.0)
  assert_eq(w, 3.0)
  // as long as the view is of the rows, at least 28 (less its insets); as far down its track as the view is
  assert_eq(h, 28.0 - 4.0)
  let room = 400.0 - 4.0 - h
  assert_true((y - (2.0 + room * t.list_offset() / (8000.0 - 400.0))).abs() < 0.01, msg="\{y} \{t.list_offset()}")
  let fg = t.ctx().theme().fg
  assert_eq(colour >> 8, fg >> 8)
  assert_eq(colour & 0xFFL, ((fg & 0xFFL).to_double() * 0.26).round().to_int64())
  // there till its hold after the scroll, then fading, then gone; at rest then
  t.run_for(@ui.scrollbar_hold_ms - @ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 1)
  t.run_for(@ui.scrollbar_fade_ms / 2.0)
  let fading = thumbs(t)
  assert_true(fading.length() == 1 && (fading[0].4 & 0xFFL) < (colour & 0xFFL), msg="\{fading}")
  t.run_for(@ui.scrollbar_fade_ms / 2.0)
  assert_eq(thumbs(t).length(), 0)
  t.assert_idle()
}

///|
test "scroll bar: its track keeps clear of what floats over the list's foot, and of the corners it is cut by" {
  let t = @ui.Tester::new(bar_rows([], over_foot=100.0, corner=20.0), w=300.0, h=400.0)
  t.move(295.0, 100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  // at the top: below the corner's rounding
  assert_eq(thumbs(t)[0].1, 20.0 + 2.0)
  // at the end: over what floats over the foot, and its clearance
  t.wheel(100.0, 100.0, 10000.0)
  t.run_for(@ui.scrollbar_fade_ms)
  let (_, y, _, h, _) = thumbs(t)[0]
  assert_eq(y + h, 400.0 - 100.0 - @ui.scroll_bar_clear - 2.0)
}

///|
test "scroll bar: the pointer along a list's right brings its bar out, and it goes a while after the pointer leaves" {
  let t = @ui.Tester::new(bar_rows([]), w=300.0, h=400.0)
  t.move(200.0, 100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 0)
  t.move(300.0 - @ui.scroll_bar_near + 1.0, 100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 1)
  // as long as it stays there
  t.run_for(@ui.scrollbar_hold_ms * 2.0)
  assert_eq(thumbs(t).length(), 1)
  t.assert_idle()
  t.move(200.0, 100.0)
  t.run_for(@ui.scrollbar_hold_ms)
  assert_eq(thumbs(t).length(), 1)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 0)
  t.assert_idle()
}

///|
test "scroll bar: its thumb dragged scrolls the list as far as it moves, darker meanwhile; nothing under it is pressed" {
  let pressed : Array[Int] = []
  let t = @ui.Tester::new(bar_rows(pressed), w=300.0, h=400.0)
  // along the edge, off the thumb: out, light
  t.move(296.0, 200.0)
  t.run_for(@ui.scrollbar_fade_ms)
  let (_, y0, _, _, light) = thumbs(t)[0]
  // on it: darker
  t.move(296.0, 10.0)
  let lit = thumbs(t)[0].4
  assert_true((lit & 0xFFL) > (light & 0xFFL), msg="\{lit} \{light}")
  t.press_at(296.0, 10.0)
  t.move(296.0, 10.0 + 93.0)
  let (_, y1, _, _, held) = thumbs(t)[0]
  assert_true((y1 - y0 - 93.0).abs() < 0.01, msg="\{y0} \{y1}")
  // the view as far down the rows as the thumb its track
  assert_true((t.list_offset() - 93.0 * (8000.0 - 400.0) / (400.0 - 4.0 - 24.0)).abs() < 0.01, msg="\{t.list_offset()}")
  assert_eq(held, lit)
  t.release(296.0, 10.0 + 93.0)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(pressed.length(), 0)
}

///|
test "scroll bar: a finger sees none, its list scrolled or flung, and presses what is along the edge" {
  let pressed : Array[Int] = []
  let t = @ui.Tester::new(bar_rows(pressed), w=300.0, h=400.0, platform=2)
  t.drag(150.0, 300.0, 150.0, 100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 0)
  // to the fling's end: at rest then, no bar to fade
  t.run_for(t.ctx().list_info("list").unwrap().rest - t.time())
  t.tap(296.0, 200.0)
  assert_eq(pressed.length(), 1)
  t.assert_idle()
}

///|
test "scroll bar: a list put at a row as it is first shown shows none; sent to one once shown, it scrolls and shows it" {
  let go = Ref(50)
  let t = @ui.Tester::new(
    fn(c) {
      bar_rows([])(c)
      if go.val >= 0 {
        c.list_scroll_to("list", go.val)
        go.val = -1
      }
    },
    w=300.0,
    h=400.0,
  )
  assert_eq(t.list_offset(), 50.0 * 40.0)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 0)
  t.assert_idle()
  go.val = 100
  t.draw()
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 1)
}

///|
test "scroll bar: a box kept to a height has one along its right, a box scrolled sideways along its foot" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.capped("tall", 200.0, fn() { c.box(w=Fill(1.0), h=Px(1000.0), fn() {  }) |> ignore }) |> ignore
        c.sideways("wide", fn() { c.box(w=Px(1000.0), h=Px(100.0), fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, 100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  let tall = thumbs(t)
  assert_eq(tall.length(), 1)
  assert_eq(tall[0].0, 300.0 - 2.0 - 3.0)
  assert_true(tall[0].1 > 2.0 && tall[0].1 + tall[0].3 <= 200.0 - 2.0, msg="\{tall}")
  t.move(100.0, 250.0)
  t.wheel_with(100.0, 250.0, 100.0, 0.0, 0)
  t.run_for(@ui.scrollbar_fade_ms)
  let wide = thumbs(t).filter(fn(r) { r.3 == 3.0 })
  assert_eq(wide.length(), 1, msg="\{thumbs(t)}")
  // (under what it holds (200 to 300), not over it: the box keeps its foot clear for it)
  assert_eq(wide[0].1, 300.0 + 2.0)
  assert_true(wide[0].0 > 2.0, msg="\{wide}")
}

///|
test "scroll bar: a box scrolled sideways out past the view it is for has its bar under that view only" {
  // (a table out 40 across a margin either side of a message 220 wide)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.sideways("wide", padx=40.0, bar_in=40.0, fn() { c.box(w=Px(1000.0), h=Px(100.0), fn() {  }) |> ignore })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.move(150.0, 50.0)
  t.wheel_with(150.0, 50.0, 100.0, 0.0, 0)
  t.run_for(@ui.scrollbar_fade_ms)
  let at_start = thumbs(t)
  assert_eq(at_start.length(), 1, msg="\{at_start}")
  assert_true(at_start[0].0 >= 40.0 + 2.0, msg="\{at_start}")
  // (scrolled to its end: at the view's end, not the screen's)
  t.wheel_with(150.0, 50.0, 2000.0, 0.0, 0)
  t.run_for(@ui.scrollbar_fade_ms)
  let at_end = thumbs(t)
  assert_eq(at_end.length(), 1, msg="\{at_end}")
  assert_true((at_end[0].0 + at_end[0].2 - (300.0 - 40.0 - 2.0)).abs() < 0.01, msg="\{at_end}")
}

///|
test "scroll bar: a box scrolled sideways keeps room at its foot for its bar while it can scroll, none once what it holds fits" {
  let content = Ref::new(1000.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.sideways("wide", fn() { c.box(w=Px(content.val), h=Px(100.0), fn() {  }) |> ignore }) |> ignore
        c.text("under", wrap=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.draw()
  let under = fn() { t.rect_of("under").unwrap().1 }
  assert_eq(under(), 100.0 + @ui.scroll_bar_room)
  content.val = 200.0
  t.draw()
  assert_eq(under(), 100.0)
  // (wider again: the room again)
  content.val = 1000.0
  t.draw()
  assert_eq(under(), 100.0 + @ui.scroll_bar_room)
}

///|
/// A field three lines high holding twelve (20 a line: 180 more than it shows), its caret at their end.
fn field_rows(f : @ui.Field) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.editor("f", field=f, max_lines=3, plain=true, font_size=10.0, line=20.0) |> ignore
    })
    |> ignore
  }
}

///|
fn twelve_lines() -> String {
  (0).until(12).map(fn(i) { "line \{i}" }).collect().join("\n")
}

///|
/// How far the field's words are scrolled up in it.
fn field_scrolled(t : @ui.Tester) -> Double {
  let ((_, oy), (_, y, _, _)) = t.ctx().field_words("f").unwrap()
  y - oy
}

///|
test "scroll bar: a field of more lines than it shows scrolls by the wheel, its caret where it was, its bar out; typing brings the caret back" {
  let f = @ui.Field::new(text=twelve_lines())
  let t = @ui.Tester::new(field_rows(f), w=300.0, h=400.0)
  // its end shown, where the caret is
  assert_eq(field_scrolled(t), 180.0)
  t.move(100.0, 30.0)
  t.wheel(100.0, 30.0, -100.0)
  assert_eq(field_scrolled(t), 80.0)
  assert_eq(f.selection(), (twelve_lines().length(), twelve_lines().length()))
  t.run_for(@ui.scrollbar_fade_ms)
  let shown = thumbs(t)
  assert_eq(shown.length(), 1, msg="\{shown}")
  assert_true(shown[0].0 == 300.0 - 2.0 - 3.0 && shown[0].1 + shown[0].3 <= 60.0, msg="\{shown}")
  // past its top the wheel goes no further
  t.wheel(100.0, 30.0, -500.0)
  assert_eq(field_scrolled(t), 0.0)
  // the words changed where the caret is: in view again
  t.tap(100.0, 30.0)
  f.set(twelve_lines() + "!")
  t.draw()
  assert_eq(field_scrolled(t), 180.0)
}

///|
/// A field six lines high holding twelve (20 a line), 10 inside a box 200 by 140 whose corners are `r` round and cut
/// what it holds, scrolled by the wheel: its bar's thumbs as drawn.
fn inset_field_thumbs(r : Double) -> Array[(Double, Double, Double, Double, Int64)] {
  let f = @ui.Field::new(text=twelve_lines())
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Px(200.0), h=Px(140.0), pad=10.0, radius=r, clip=true, bg=0xEEEEEEFFL, fn() {
        c.editor("f", field=f, max_lines=6, plain=true, font_size=10.0, line=20.0) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 40.0)
  t.wheel(100.0, 40.0, -100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  thumbs(t)
}

///|
test "scroll bar: a field inset in a box cut round, its corners clear of the field's: its thumb where it is in a box cut square" {
  let square = inset_field_thumbs(0.0)
  assert_eq(square.length(), 1, msg="its thumb out: \{square}")
  assert_eq(inset_field_thumbs(30.0), square, msg="cut round: the same thumb")
}

///|
test "scroll bar: a finger dragging a field of more lines than it shows scrolls it, the caret put nowhere" {
  let f = @ui.Field::new(text=twelve_lines())
  let t = @ui.Tester::new(field_rows(f), w=300.0, h=400.0, platform=2)
  assert_eq(field_scrolled(t), 180.0)
  t.drag(100.0, 5.0, 100.0, 55.0)
  assert_true(field_scrolled(t) < 180.0 - 30.0, msg="\{field_scrolled(t)}")
  assert_eq(f.selection(), (twelve_lines().length(), twelve_lines().length()))
  assert_eq(t.ctx().field_focused(), false)
  t.run_for(@ui.scrollbar_fade_ms)
  assert_eq(thumbs(t).length(), 0)
}

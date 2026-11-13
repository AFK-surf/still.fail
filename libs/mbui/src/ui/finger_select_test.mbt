///|
/// Words that are picked with the pointer in a list a finger drags, and words that are not.
fn finger_words() -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.selectable(fn() {
        c.list("finger/list", 2, 60.0, fn(i) {
          if i == 0 {
            c.rich([@ui.plain("hello wide world")], size=15.0) |> ignore
          } else {
            c.rich([@ui.plain("second line here")], size=15.0) |> ignore
          }
        })
        |> ignore
      })
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
}

///|
test "finger: words that are picked with the pointer are picked by a finger held still on them: the word under it, the menu over it once lifted" {
  let t = finger_words()
  let (x, y, _, h) = t.rect_of("hello wide world").unwrap()
  // (on "wide")
  let at = x + 60.0
  t.press_at(at, y + h / 2.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "")
  t.run_for(@ui.long_press_ms)
  assert_eq(t.ctx().selected_text(), "wide")
  assert_true(t.ctx().selection_by_finger())
  t.release(at, y + h / 2.0)
  t.draw()
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(can, @hostapi.text_menu_copy | @hostapi.text_menu_select_all)
  // the menu's copy (the host's key): copied, let go
  t.key(13)
  assert_eq(t.clipboard(), "wide")
  assert_eq(t.ctx().selected_text(), "")
  t.draw()
  assert_false(t.text_menu().0)
}

///|
test "finger: a press shorter than a long press picks nothing, and a finger that moves first scrolls, picking nothing" {
  let t = finger_words()
  let (x, y, _, h) = t.rect_of("hello wide world").unwrap()
  t.tap(x + 60.0, y + h / 2.0)
  t.run_for(@ui.long_press_ms)
  assert_eq(t.ctx().selected_text(), "")
  t.press_at(x + 60.0, y + h / 2.0)
  t.draw()
  t.move_to(x + 60.0, y + h / 2.0 + 40.0)
  t.run_for(@ui.long_press_ms)
  assert_eq(t.ctx().selected_text(), "")
  t.release(x + 60.0, y + h / 2.0 + 40.0)
}

///|
test "finger: sliding on from the word held widens it by words, either way; a tap elsewhere lets it go" {
  let t = finger_words()
  let (x, y, w, h) = t.rect_of("hello wide world").unwrap()
  t.press_at(x + 60.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.move_to(x + w - 2.0, y + h / 2.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "wide world")
  t.move_to(x + 2.0, y + h / 2.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "hello wide")
  t.release(x + 2.0, y + h / 2.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "hello wide")
  let (_, y2, _, h2) = t.rect_of("second line here").unwrap()
  t.tap(200.0, y2 + h2 / 2.0 + 60.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "")
}

///|
test "finger: the end's handle moved takes the end to the finger, the start staying; the menu's select all picks all of them" {
  let t = finger_words()
  let (x, y, _, h) = t.rect_of("hello wide world").unwrap()
  t.press_at(x + 60.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(x + 60.0, y + h / 2.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "wide")
  // the end's handle: under the end of "wide", its knob under the line
  let (sx, sy, sw, sh) = t.ctx().selection_box().unwrap()
  let hx = sx + sw
  let hy = sy + sh + 6.0
  let (x2, y2, w2, h2) = t.rect_of("second line here").unwrap()
  t.press_at(hx, hy)
  t.draw()
  t.move_to(hx + 10.0, hy + 10.0)
  t.draw()
  t.move_to(x2 + w2 - 2.0, y2 + h2 / 2.0 + 6.0 + sh / 2.0)
  t.draw()
  t.release(x2 + w2 - 2.0, y2 + h2 / 2.0 + 6.0 + sh / 2.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "wide world\nsecond line here")
  t.key(12)
  t.draw()
  assert_eq(t.ctx().selected_text(), "hello wide world\nsecond line here")
}

///|
test "finger: a mouse's press and drag picks as it did; a finger's hold on what takes the hold itself picks nothing" {
  let held : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.selectable(fn() {
        let row = c.id("row")
        if c.menu_asked(row) is Some(_) {
          held.push("menu")
        }
        c.box(id=row, w=Fill(1.0), fn() { c.rich([@ui.plain("a row with a menu")], size=15.0) |> ignore }) |> ignore
      })
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
  let (x, y, _, h) = t.rect_of("a row with a menu").unwrap()
  t.press_at(x + 10.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(x + 10.0, y + h / 2.0)
  assert_eq(held, ["menu"])
  assert_eq(t.ctx().selected_text(), "")
}

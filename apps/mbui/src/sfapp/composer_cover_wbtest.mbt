// A composer's floating capsule covers the messages scrolled beneath it. A press in that capsule must not start a
// selection in those messages (and the selection's edge scrolling), while the messages remain selectable beside it.

///|
/// The pointer held in the composer's padding, long enough for selection edge scrolling to be visible.
let cover_mouse_hold_ms : Double = 500.0

///|
fn composer_cover_tester(pointing? : @ui.Pointing = Mouse, platform? : Int = 0) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(
    fn(c) {
      @sf.set_words(fill)
      let _ = @sf.begin(c)
      let ws : Workspace = { id: "ws1", name: "Acme", emoji: "", icon: "", email: "" }
      c.mouse_drags_lists(false)
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.selectable(fn() {
          c.list("messages", 40, 40.0, fn(i) {
            c.box(h=Px(40.0), w=Fill(1.0), fn() {
              c.rich([@ui.plain("Message \{i} words behind the floating composer for this test")], size=15.0, line=40.0) |> ignore
            }) |> ignore
          }) |> ignore
        })
        c.layer(fn() {
          c.spacer()
          c.box(style=@ui.css("w=Full p=S4"), fn() {
            @sfpages.composer(c, src, ws, default_spec({ station: "ws1/st1", key: "ws1/st1:s-c1" }), fn(_) {  })
          }) |> ignore
        }) |> ignore
      }) |> ignore
      @sf.presented(c)
    },
    w=600.0,
    h=500.0,
    platform~,
    pointing~,
  )
  t.draw()
  t.ctx().blur()
  t.run_for(@sfpages.let_go_ms + @ui.move_most_ms)
  t
}

///|
test "composer over messages: pressing its capsule does not pick or scroll words under it" {
  let t = composer_cover_tester()
  // Its top padding is over a message and above the field's own hit target.
  let (_, top, _, _, _, _) = t.drawn_glass()[0]
  let y = top + 4.0
  let before = t.list_offset()
  t.press_at(200.0, y)
  t.move_to(300.0, y)
  t.run_for(cover_mouse_hold_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_eq(t.list_offset(), before)
  t.release(300.0, y)
}

///|
test "composer over messages: its padding takes the focus and clears a selection; uncovered words and the wheel still work" {
  let t = composer_cover_tester()
  t.drag(1.0, 55.0, 300.0, 55.0)
  assert_true(t.ctx().selected_text() != "")
  let (_, top, _, _, _, _) = t.drawn_glass()[0]
  t.tap(200.0, top + 4.0)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(composer_focused())
  let before = t.list_offset()
  t.wheel(200.0, top + 4.0, 160.0)
  t.run_for(@ui.wheel_ease_ms)
  assert_true(t.list_offset() > before)
}

///|
test "composer over messages: a finger held on its padding takes the field, not the words behind it" {
  let t = composer_cover_tester(pointing=Finger, platform=2)
  let (_, top, _, _, _, _) = t.drawn_glass()[0]
  let y = top + 4.0
  let before = t.list_offset()
  t.touch(0, 200.0, y)
  t.run_for(@ui.long_press_ms * 2.0)
  assert_eq(t.ctx().selected_text(), "")
  t.touch(2, 200.0, y)
  t.draw()
  assert_true(t.ime().0)
  assert_eq(t.list_offset(), before)
}

///|
test "composer over messages: clicking inside its field clears a previous message selection" {
  let t = composer_cover_tester()
  t.drag(1.0, 55.0, 300.0, 55.0)
  assert_true(t.ctx().selected_text() != "")
  let (x, y, _, h) = t.rect_of("按空格输入").unwrap()
  t.tap(x + 100.0, y + h / 2.0)
  assert_true(composer_focused())
  assert_eq(t.ctx().selected_text(), "")
}

// A sheet and the keyboard's focus: none of what it holds given it as it opens (a field in it would bring the keyboard
// up over it), and none of the page under it left with it (what is typed would go on into a field it hides): its own
// ground has it while it is up, given back as it goes.

///|
test "sheet: a field under it keeps neither the focus, what is typed nor its input method while it is up; one in it is not given them; all of it given back as it goes" {
  for platform in [0, 2] {
    let at = "platform \{platform}"
    let open = Ref(false)
    let page = @ui.Field::new()
    let inner = @ui.Field::new()
    let t = @ui.Tester::new(
      fn(c) {
        c.editor("page", placeholder="Page field", field=page) |> ignore
        open.val = @kit.sheet(c, "s", open.val, h=300.0, label="Chat info", fn() {
          c.editor("inner", placeholder="Sheet field", field=inner) |> ignore
          @kit.button(c, "Pin") |> ignore
        }).open
      },
      platform~,
    )
    t.tap_text("Page field")
    t.draw()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Page field"), msg=at)
    assert_true(t.ime().0, msg="\{at}: the page's field told the host")
    // up: the focus on its ground, the host told no field has it, the one in it not given it
    open.val = true
    to_rest(t, "s")
    assert_eq(t.focused().map(fn(s) { s.label }), None, msg=at)
    assert_false(t.ime().0, msg="\{at}: no field while it is up: \{Repr(t.ime())}")
    assert_false(t.get(@ui.Role::TextField, label="Sheet field").focused, msg=at)
    t.type_text("a")
    t.draw()
    assert_eq((page.text(), inner.text()), ("", ""), msg="\{at}: typed while it is up")
    // gone: the page's field has the focus and its input method back, what is typed its
    t.press("Escape")
    assert_false(open.val, msg=at)
    to_rest(t, "s")
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Page field"), msg=at)
    assert_true(t.ime().0, msg="\{at}: given back: \{Repr(t.ime())}")
    t.type_text("b")
    t.draw()
    assert_eq((page.text(), inner.text()), ("b", ""), msg=at)
  }
}

///|
test "sheet: opened with nothing focused, nothing is (no field in it, none under it); closed, still nothing" {
  let open = Ref(false)
  let page = @ui.Field::new()
  let t = @ui.Tester::new(fn(c) {
    c.editor("page", placeholder="Page field", field=page) |> ignore
    open.val = @kit.sheet(c, "s", open.val, h=300.0, label="Chat info", fn() {
      c.editor("inner", placeholder="Sheet field") |> ignore
    }).open
  })
  t.draw()
  open.val = true
  to_rest(t, "s")
  assert_eq(t.focused().map(fn(s) { s.label }), None)
  assert_false(t.ime().0)
  t.press("Escape")
  to_rest(t, "s")
  assert_eq(t.focused().map(fn(s) { s.label }), None)
  assert_eq(t.ctx().focused_id(), 0)
  t.type_text("c")
  t.draw()
  assert_eq(page.text(), "")
}

///|
test "sheet: opened over a focused field with a soft keyboard, it rises from the screen's foot as the keyboard leaves, holds the host's input method away while sinking, and rides above the keyboard when a field in it is pressed" {
  let open = Ref(false)
  let shown = Ref(false)
  let page = @ui.Field::new()
  let inner = @ui.Field::new()
  let parked = Ref(false)
  let kept = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      parked.val = page.parked()
      kept.val = page.focused() || parked.val
      c.editor("page", placeholder="Page field", field=page) |> ignore
      let r = @kit.sheet(c, "s", open.val, share=0.5, label="Chat info", fn() {
        c.editor("inner", placeholder="Sheet field", field=inner) |> ignore
        @kit.button(c, "Pin") |> ignore
      })
      open.val = r.open
      shown.val = r.shown
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  t.tap_text("Page field")
  t.draw()
  t.set_ime_inset(300.0)
  t.resize(390.0, 544.0)
  assert_true(t.ime().0)
  assert_false(parked.val)
  // opened while the keyboard is still up: full screen-share height from the first frame, rising monotonically
  open.val = true
  t.draw()
  assert_false(t.ime().0, msg="host told at once to put the keyboard away")
  assert_true(parked.val, msg="the page's field parked while the sheet covers it")
  let (_, y0, _, h0) = t.get(@ui.Role::Dialog, label="Chat info").rect
  assert_true((h0 - 422.0).abs() < 0.01, msg="sheet height \{h0} is screen's 0.5, not squeezed above keyboard")
  let mut prev_y = y0
  for i in 1..=6 {
    let kb = 300.0 - i.to_double() * 50.0
    t.set_ime_inset(kb)
    t.resize_next(390.0, 844.0 - kb)
    t.run_for(@ui.frame_period_default)
    let (_, y, _, h) = t.get(@ui.Role::Dialog, label="Chat info").rect
    assert_true((h - 422.0).abs() < 0.01, msg="step \{i}: sheet height \{h}")
    assert_true(y <= prev_y + 0.01, msg="step \{i}: sheet top \{y} after \{prev_y}")
    assert_true(parked.val, msg="step \{i}: page field stays parked")
    prev_y = y
  }
  to_rest(t, "s")
  assert_eq(t.get(@ui.Role::Dialog, label="Chat info").rect.1, 422.0)
  assert_false(t.ime().0)
  assert_true(parked.val)
  // dismissed by a backdrop tap: the host's input method stays off on every sinking frame until the sheet is gone
  t.tap(195.0, 100.0)
  assert_false(open.val)
  assert_true(shown.val, msg="still sinking")
  assert_false(t.ime().0, msg="held off as it starts to sink")
  assert_true(kept.val, msg="page field stays focused or parked while sinking")
  let early_ime = Ref(0)
  let early_lost = Ref(0)
  t.each_frame(Some(fn() {
    if shown.val && t.ime().0 {
      early_ime.val += 1
    }
    if !kept.val {
      early_lost.val += 1
    }
  }))
  to_rest(t, "s")
  t.each_frame(None)
  assert_eq((early_ime.val, early_lost.val), (0, 0))
  assert_false(shown.val)
  assert_true(t.ime().0, msg="input method given back once the sheet has sunk off")
  assert_false(parked.val, msg="page field unparked once the sheet has sunk off")
  assert_true(kept.val)
  // a field inside the open sheet: brings the keyboard up, rides above it, and sinks smoothly without jumping when closed
  open.val = true
  to_rest(t, "s")
  t.tap_text("Sheet field")
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Sheet field"))
  assert_true(t.ime().0, msg="the sheet's own field asks for the keyboard")
  assert_true(parked.val, msg="the page's field under it remains parked")
  t.set_ime_inset(300.0)
  t.resize(390.0, 544.0)
  to_rest(t, "s")
  let (_, y_in, _, h_in) = t.get(@ui.Role::Dialog, label="Chat info").rect
  assert_eq((y_in, h_in), (272.0, 272.0))
  t.tap(195.0, 100.0)
  assert_false(open.val)
  let y_close = @kit.sheet_top(t.ctx()).unwrap()
  assert_true(y_close >= y_in - 1.0 && y_close < y_in + 90.0, msg="smooth sink from \{y_in}, got \{y_close}")
  assert_false(t.ime().0, msg="keyboard dismissed as the sheet closes")
  t.set_ime_inset(0.0)
  t.resize_next(390.0, 844.0)
  to_rest(t, "s")
  assert_false(shown.val)
  assert_true(t.ime().0, msg="page field's input method restored at rest")
  assert_false(parked.val)
}

///|
test "a field tapped through a sinking sheet takes the input method at once; stacked sibling sheets keep the page field parked" {
  let open1 = Ref(false)
  let open2 = Ref(false)
  let shown1 = Ref(false)
  let parked = Ref(false)
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) {
      c.editor("msg", field~, placeholder="Message") |> ignore
      parked.val = field.parked()
      let s1 = @kit.sheet(c, "s1", open1.val, share=0.5, label="First sheet", fn() {
        c.text("First sheet") |> ignore
      })
      open1.val = s1.open
      shown1.val = s1.shown
      let s2 = @kit.sheet(c, "s2", open2.val, share=0.4, label="Second sheet", fn() {
        c.text("Second sheet") |> ignore
      })
      open2.val = s2.open
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  // 1) With nothing focused before s1 opens, tapping Message through s1 as it sinks raises the keyboard at once.
  t.ctx().blur()
  t.draw()
  open1.val = true
  to_rest(t, "s1")
  assert_false(t.ime().0)
  assert_false(parked.val)
  t.tap_once(195.0, 100.0)
  t.frame()
  assert_false(open1.val)
  assert_true(shown1.val, msg="s1 still sinking")
  let (fx, fy, fw, fh) = t.get(@ui.Role::TextField, label="Message").rect
  t.tap_once(fx + fw / 2.0, fy + fh / 2.0)
  assert_true(t.ime().0, msg="explicit tap through sinking sheet activates IME immediately")
  to_rest(t, "s1")
  // 2) Stacked sibling sheets (s2 over s1 over focused Message) keep Message parked across the return chain.
  open1.val = true
  to_rest(t, "s1")
  assert_true(parked.val, msg="parked under s1")
  open2.val = true
  to_rest(t, "s2")
  t.draw()
  assert_true(parked.val, msg="still parked when sibling s2 opens over s1")
  t.tap(195.0, 100.0)
  to_rest(t, "s2")
  assert_true(parked.val, msg="still parked under s1 after s2 closes")
  t.tap(195.0, 100.0)
  to_rest(t, "s1")
  assert_false(parked.val)
  assert_true(t.ime().0)
}

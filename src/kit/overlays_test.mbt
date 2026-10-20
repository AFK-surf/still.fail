// The overlays (batch 2) driven as a person and a screen reader drive them, whether each is open kept by the test
// (the view's), the clock the tester's.

///|
test "dialog: opened by its trigger, the page hidden under it, the focus in it; Escape closes it, the focus goes back" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if button(c, "Edit profile").clicked {
      open.val = true
    }
    open.val = dialog(c, "edit", open.val, "Edit profile", description="Your name as others see it", fn() {
      c.editor("name", placeholder="Name") |> ignore
      button(c, "Save") |> ignore
    }).value
  })
  t.tab()
  t.press("Enter")
  assert_true(open.val)
  let d = t.get(@ui.Dialog, label="Edit profile")
  assert_eq(d.description, "Your name as others see it")
  assert_true(d.modal)
  // the page under it is out of the tree; the focus went to its first
  assert_true(t.query(@ui.Button, label="Edit profile") is None)
  assert_true(t.get(@ui.TextField, label="Name").focused)
  // Tab stays in it: the field, Save, the close button, round
  t.tab()
  t.tab()
  assert_eq(t.focused().unwrap().label, "关闭")
  t.tab()
  assert_eq(t.focused().unwrap().label, "Name")
  t.press("Escape")
  assert_false(open.val)
  t.draw()
  assert_true(t.query(@ui.Dialog) is None)
  assert_eq(t.focused().unwrap().label, "Edit profile")
}

///|
test "dialog: a press outside it closes it, as its close button does; one inside does not" {
  let open = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    open.val = dialog(c, "d", open.val, "Hello", fn() { c.text("Inside") |> ignore }).value
  })
  t.draw()
  t.tap_text("Inside")
  assert_true(open.val)
  t.tap(5.0, 5.0)
  assert_false(open.val)
  open.val = true
  t.frame()
  t.draw()
  t.click(@ui.Button, label="关闭")
  assert_false(open.val)
}

///|
test "alert dialog: opens on cancel (Enter does not do it), a press outside leaves it, its action confirms" {
  let open = Ref(true)
  let done = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    let a = alert_dialog(c, "del", open.val, "Delete the chat?", "Delete", description="It cannot be undone", danger=true)
    open.val = a.open
    if a.confirmed {
      done.val += 1
    }
  })
  t.draw()
  assert_eq(t.get(@ui.AlertDialog, label="Delete the chat?").description, "It cannot be undone")
  assert_eq(t.focused().unwrap().label, "取消")
  t.tap(5.0, 5.0)
  assert_true(open.val)
  t.press("Enter")
  assert_false(open.val)
  assert_eq(done.val, 0)
  open.val = true
  t.frame()
  t.draw()
  t.click(@ui.Button, label="Delete")
  assert_false(open.val)
  assert_eq(done.val, 1)
}

///|
test "popover: beside its trigger, the focus in it; its trigger toggles it, a press outside closes it" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "Filters", key="filters")
    if tr.clicked {
      open.val = !open.val
    }
    open.val = popover(c, "pop", open.val, tr.id, label="Filters", fn() { button(c, "Apply") |> ignore }).value
  })
  t.click(@ui.Button, label="Filters")
  assert_true(open.val)
  t.draw()
  let (_, ty, _, th) = t.get(@ui.Button, label="Filters").rect
  let (_, py, _, _) = t.get(@ui.Dialog, label="Filters").rect
  assert_true(py >= ty + th)
  // not modal: the page stays in the tree
  assert_true(t.query(@ui.Button, label="Filters") is Some(_))
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Apply"))
  // its trigger closes it (a press on it is not outside)
  t.click(@ui.Button, label="Filters")
  assert_false(open.val)
  t.click(@ui.Button, label="Filters")
  assert_true(open.val)
  t.tap(380.0, 800.0)
  assert_false(open.val)
}

///|
test "tooltip: shown once the pointer has rested on its trigger; at once by the keyboard; shut by a press" {
  let shown = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=40.0, pad=80.0, fn() {
      let r = button(c, "Bold", key="bold")
      shown.val = tooltip(c, "tip", r.id, "Bold (⌘B)")
      button(c, "Other", key="other") |> ignore
    })
    |> ignore
  })
  let (x, y, w, h) = t.get(@ui.Button, label="Bold").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame(ms=600.0)
  assert_false(shown.val)
  t.frame(ms=100.0)
  assert_true(shown.val)
  t.draw()
  ignore(t.get(@ui.Tooltip, label="Bold (⌘B)"))
  // a press shuts it until the pointer leaves
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_false(shown.val)
  t.frame(ms=1000.0)
  assert_false(shown.val)
  t.move(1.0, 1.0)
  assert_false(shown.val)
  // by the keyboard: at once; Escape shuts it
  t.tab()
  assert_true(shown.val)
  t.press("Escape")
  assert_false(shown.val)
}

///|
test "tooltip: one shown soon after another closed skips the wait" {
  let a = Ref(false)
  let b = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.row(gap=40.0, pad=80.0, fn() {
      let ra = button(c, "A", key="a")
      a.val = tooltip(c, "ta", ra.id, "First")
      let rb = button(c, "B", key="b")
      b.val = tooltip(c, "tb", rb.id, "Second")
    })
    |> ignore
  })
  let (ax, ay, aw, ah) = t.get(@ui.Button, label="A").rect
  let (bx, by, bw, bh) = t.get(@ui.Button, label="B").rect
  t.move(ax + aw / 2.0, ay + ah / 2.0)
  t.frame(ms=700.0)
  assert_true(a.val)
  t.move(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  t.frame()
  assert_false(a.val)
  assert_true(b.val)
  // long after: the wait again
  t.move(1.0, 1.0)
  t.frame(ms=1000.0)
  t.move(ax + aw / 2.0, ay + ah / 2.0)
  t.frame()
  assert_false(a.val)
}

///|
test "hover card: opened once the pointer rests on its trigger, kept while over it or the card, closed after" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=40.0, fn() {
      let r = button(c, "@ada", key="ada", variant=Ghost)
      open.val = hover_card(c, "card", r.id, fn() { c.text("Ada Lovelace, the first programmer") |> ignore })
    })
    |> ignore
  })
  let (x, y, w, h) = t.get(@ui.Button, label="@ada").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame(ms=699.0)
  assert_false(open.val)
  t.frame(ms=1.0)
  assert_true(open.val)
  t.draw()
  // onto the card: still open
  let (cx, cy, cw, ch) = t.rect_of("Ada Lovelace").unwrap()
  t.move(cx + cw / 2.0, cy + ch / 2.0)
  t.frame(ms=1000.0)
  assert_true(open.val)
  // off both: closed after its delay
  t.move(380.0, 800.0)
  t.frame(ms=200.0)
  assert_true(open.val)
  t.frame(ms=100.0)
  assert_false(open.val)
}

///|
test "toasts: each goes after its time, paused under the pointer; closed, acted on, swiped away" {
  let list : Ref[Array[Toast]] = Ref([])
  let acted : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let r = toaster(c, "toasts", list.val, duration=3000.0)
    list.val = r.open
    if r.acted is Some(_) {
      acted.val = r.acted
    }
  })
  list.val = [toast("a", "Saved"), toast("b", "Sent", description="To the team", action="Undo")]
  t.draw()
  assert_eq(t.all(@ui.Status).length(), 2)
  assert_eq(t.get(@ui.Status, label="Sent").description, "To the team")
  ignore(t.get(@ui.Region, label="通知"))
  // paused while the pointer is over them
  let (x, y, w, h) = t.get(@ui.Status, label="Saved").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame(ms=5000.0)
  assert_eq(list.val.length(), 2)
  // (none of their 3000 ms went by before the pointer came over them)
  t.move(1.0, 1.0)
  t.frame(ms=2000.0)
  assert_eq(list.val.length(), 2)
  t.frame(ms=1000.0)
  assert_eq(list.val.map(fn(x) { x.id }), [])
  // drawn while they go out (the frame after their time, at its moment), gone once they have
  t.draw()
  t.run_for(presence_out_ms)
  assert_eq(t.all(@ui.Status).length(), 0)
  // the action
  list.val = [toast("c", "Archived", action="Undo")]
  t.draw()
  // come in (it rises as it does)
  t.run_for(presence_in_ms)
  t.click(@ui.Button, label="Undo")
  assert_eq(acted.val, Some("c"))
  assert_eq(list.val.length(), 0)
  // the close button
  list.val = [toast("d", "Copied")]
  t.draw()
  t.run_for(presence_in_ms)
  t.click(@ui.Button, label="关闭")
  assert_eq(list.val.length(), 0)
  // a swipe to the right
  list.val = [toast("e", "Moved")]
  t.draw()
  t.run_for(presence_in_ms)
  let (x, y, w, h) = t.get(@ui.Status, label="Moved").rect
  t.drag(x + 20.0, y + h / 2.0, x + 20.0 + w / 2.0, y + h / 2.0)
  assert_eq(list.val.length(), 0)
  t.run_for(presence_out_ms)
  assert_true(t.query(@ui.Status, label="Moved") is None)
  t.assert_idle()
}

///|
/// What changed (the view's own, or an input's) drawn now, then on to when sheet `key` is at rest (sheet_rest).
fn to_rest(t : @ui.Tester, key : String) -> Unit {
  t.draw()
  t.run_for(sheet_rest(key) - t.time())
}

///|
test "sheet: up from the bottom, the page hidden; a press above it, Escape and a drag down by its top close it" {
  let open = Ref(true)
  let drags : Array[SheetDrag] = []
  let t = @ui.Tester::new(fn(c) {
    c.text("Page") |> ignore
    let r = sheet(c, "s", open.val, h=300.0, label="Chat info", fn() { button(c, "Pin") |> ignore })
    open.val = r.open
    match r.dragged {
      Some(d) => drags.push(d)
      None => ()
    }
  })
  to_rest(t, "s")
  let (_, y, _, h) = t.get(@ui.Dialog, label="Chat info").rect
  assert_eq(y, 844.0 - 300.0)
  assert_eq(h, 300.0)
  assert_true(t.query(@ui.Text, label="Page") is None)
  t.click(@ui.Button, label="Pin")
  assert_true(open.val)
  t.tap(100.0, 100.0)
  assert_false(open.val)
  to_rest(t, "s")
  assert_true(t.query(@ui.Dialog) is None)
  open.val = true
  to_rest(t, "s")
  t.press("Escape")
  assert_false(open.val)
  to_rest(t, "s")
  open.val = true
  to_rest(t, "s")
  // a short drag goes back; a long one closes it
  t.drag(195.0, 560.0, 195.0, 600.0)
  to_rest(t, "s")
  assert_true(open.val)
  t.drag(195.0, 560.0, 195.0, 700.0)
  assert_false(open.val)
  assert_eq(drags, [DraggedBack, DraggedClosed])
}

///|
test "sheet with detents: let go nearer the top it goes full; low enough it closes; another height on the spring" {
  let open = Ref(true)
  let tall = Ref(0.5)
  let t = @ui.Tester::new(fn(c) {
    open.val = sheet(c, "s", open.val, share=tall.val, detents=[0.55, 0.94], label="Workspaces", fn() {  }).open
  })
  to_rest(t, "s")
  assert_true((t.get(@ui.Dialog, label="Workspaces").rect.3 - 422.0).abs() < 1.0)
  // dragged up past the middle: full
  t.drag(195.0, 430.0, 195.0, 200.0)
  to_rest(t, "s")
  assert_true((t.get(@ui.Dialog, label="Workspaces").rect.3 - 844.0 * 0.94).abs() < 1.0)
  // asked another height: there
  tall.val = 0.7
  to_rest(t, "s")
  assert_true((t.get(@ui.Dialog, label="Workspaces").rect.3 - 844.0 * 0.7).abs() < 1.0)
  // dragged down to under 30%: closed
  t.drag(195.0, 260.0, 195.0, 700.0)
  assert_false(open.val)
}

///|
test "sheet: closed by the view, it sinks away and is gone" {
  let open = Ref(true)
  let shown = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let r = sheet(c, "s", open.val, h=300.0, fn() { button(c, "OK") |> ignore })
    shown.val = r.shown
    if r.open != open.val {
      open.val = r.open
    }
  })
  to_rest(t, "s")
  assert_true(shown.val)
  open.val = false
  t.draw()
  assert_true(shown.val)
  t.run_for(sheet_rest("s") - t.time())
  assert_false(shown.val)
  assert_true(t.query(@ui.Dialog) is None)
  t.assert_idle()
}

///|
test "toasts: the room beside one takes no press (what is under it does)" {
  let taps = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), justify=JEnd, fn() {
      if button(c, "Under", key="under", w=Fill(1.0)).clicked {
        taps.val += 1
      }
    })
    |> ignore
    toaster(c, "toasts", [toast("a", "Saved")], bottom=0.0) |> ignore
  })
  t.draw()
  let (_, y, _, h) = t.get(@ui.Status, label="Saved").rect
  t.tap(8.0, y + h / 2.0)
  assert_eq(taps.val, 1)
}

///|
test "sheet_rest: a test runs to when a sheet is at rest, opened or closed, by the key it is built by" {
  let open = Ref(false)
  let shown = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let r = sheet(c, "info", open.val, h=300.0, fn() { button(c, "OK") |> ignore })
    shown.val = r.shown
    if r.open != open.val {
      open.val = r.open
    }
  })
  t.draw()
  assert_eq(sheet_rest("info"), -1.0)
  open.val = true
  t.draw()
  let up = sheet_rest("info")
  assert_true(up > t.time())
  t.run_for(up - t.time())
  t.assert_idle()
  // there, its button where the sheet's top puts it
  assert_true(t.get(@ui.Button, label="OK").rect.1 >= 844.0 - 300.0)
  open.val = false
  t.draw()
  let down = sheet_rest("info")
  t.run_for(down - t.time())
  t.assert_idle()
  assert_false(shown.val)
  assert_eq(sheet_rest("nothing of that name"), -1.0)
}

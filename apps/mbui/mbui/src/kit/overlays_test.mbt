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
  let d = t.get(@ui.Role::Dialog, label="Edit profile")
  assert_eq(d.description, "Your name as others see it")
  assert_true(d.modal)
  // the page under it is out of the tree; the focus went to its first
  assert_true(t.query(@ui.Role::Button, label="Edit profile") is None)
  assert_true(t.get(@ui.Role::TextField, label="Name").focused)
  // Tab stays in it: the field, Save, the close button, round
  t.tab()
  t.tab()
  assert_eq(t.focused().unwrap().label, "关闭")
  t.tab()
  assert_eq(t.focused().unwrap().label, "Name")
  t.press("Escape")
  assert_false(open.val)
  t.draw()
  assert_true(t.query(@ui.Role::Dialog) is None)
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
  t.click(@ui.Role::Button, label="关闭")
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
  assert_eq(t.get(@ui.Role::AlertDialog, label="Delete the chat?").description, "It cannot be undone")
  assert_eq(t.focused().unwrap().label, "取消")
  t.tap(5.0, 5.0)
  assert_true(open.val)
  t.press("Enter")
  assert_false(open.val)
  assert_eq(done.val, 0)
  open.val = true
  t.frame()
  t.draw()
  t.click(@ui.Role::Button, label="Delete")
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
  t.click(@ui.Role::Button, label="Filters")
  assert_true(open.val)
  t.draw()
  let (_, ty, _, th) = t.get(@ui.Role::Button, label="Filters").rect
  let (_, py, _, _) = t.get(@ui.Role::Dialog, label="Filters").rect
  assert_true(py >= ty + th)
  // not modal: the page stays in the tree
  assert_true(t.query(@ui.Role::Button, label="Filters") is Some(_))
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Apply"))
  // its trigger closes it (a press on it is not outside)
  t.click(@ui.Role::Button, label="Filters")
  assert_false(open.val)
  t.click(@ui.Role::Button, label="Filters")
  assert_true(open.val)
  t.tap(380.0, 800.0)
  assert_false(open.val)
}

///|
test "popover: it comes from 97% and clear, the first time it opens too; it goes back the same way, a little quicker" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "Filters", key="filters")
    if tr.clicked {
      open.val = !open.val
    }
    open.val = popover(c, "pop", open.val, tr.id, label="Filters", fn() { c.text("Unread only") |> ignore }).value
  })
  t.click(@ui.Role::Button, label="Filters")
  // half way in (pop_ms on the ease-out): smaller and fainter than it is
  t.run_for(pop_ms / 2.0)
  let (sx, sy, alpha) = t.look_of("Unread only").unwrap()
  assert_true(sx > 0.97 && sx < 1.0 && sy == sx, msg="\{sx} \{sy}")
  assert_true(alpha > 0.0 && alpha < 1.0, msg="\{alpha}")
  t.run_for(pop_ms)
  assert_eq(t.look_of("Unread only"), Some((1.0, 1.0, 1.0)))
  // closed by its trigger: going (half way out: smaller and fainter, pop_out_ms), then gone
  t.click(@ui.Role::Button, label="Filters")
  assert_false(open.val)
  t.run_for(@kit.pop_out_ms / 2.0)
  let (sx, _, alpha) = t.look_of("Unread only").unwrap()
  assert_true(sx > 0.97 && sx < 1.0, msg="\{sx}")
  assert_true(alpha > 0.0 && alpha < 1.0, msg="\{alpha}")
  t.run_for(pop_out_ms)
  assert_true(t.find("Unread only") is None)
}

///|
test "popover: not taking the focus, it stays where it was (a field typed in keeps it), Escape still closes it" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "Filters", key="filters")
    if tr.clicked {
      open.val = true
    }
    open.val = popover(c, "pop", open.val, tr.id, label="Filters", focus=false, fn() { button(c, "Apply") |> ignore })
      .value
  })
  t.click(@ui.Role::Button, label="Filters")
  let before = t.focused().map(fn(s) { s.label })
  t.draw()
  assert_true(open.val)
  assert_true(t.query(@ui.Role::Dialog, label="Filters") is Some(_))
  assert_eq(t.focused().map(fn(s) { s.label }), before)
  assert_true(before != Some("Apply"))
  t.key(@ui.key_escape)
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
  let (x, y, w, h) = t.get(@ui.Role::Button, label="Bold").rect
  // (taken at its moment)
  let moved = t.time()
  t.move(x + w / 2.0, y + h / 2.0)
  let due = moved + tooltip_delay_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_false(shown.val)
  t.run_for(due - t.time())
  assert_true(shown.val)
  t.draw()
  ignore(t.get(@ui.Role::Tooltip, label="Bold (⌘B)"))
  // a press shuts it until the pointer leaves
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_false(shown.val)
  // a whole delay rested there again: still shut
  t.run_for(tooltip_delay_ms)
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
test "tooltip: not through a dialog over its trigger: the pointer rests on the dialog's ground, not on the trigger" {
  let shown = Ref(false)
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=40.0, fn() {
      let r = button(c, "Bold", key="bold")
      shown.val = tooltip(c, "tip", r.id, "Bold (⌘B)")
    })
    |> ignore
    open.val = dialog(c, "d", open.val, "Hello", w=200.0, fn() { c.text("Inside") |> ignore }).value
  })
  let (x, y, w, h) = t.get(@ui.Role::Button, label="Bold").rect
  open.val = true
  t.draw()
  assert_true(t.query(@ui.Role::Dialog, label="Hello") is Some(_))
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(tooltip_delay_ms * 2.0)
  assert_false(shown.val)
}

///|
test "tooltip: lying over its own trigger, it stays: the pointer on it there is on the trigger still" {
  let shown = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=40.0, fn() {
      let r = button(c, "Bold", key="bold")
      // (put where the pointer is, over the trigger, as an edge's tip follows the pointer)
      let at = match c.rect_of(r.id) {
        Some((x, y, w, h)) => (x + w / 2.0, y + h / 2.0, 0.0, 0.0)
        None => (0.0, 0.0, 0.0, 0.0)
      }
      shown.val = tooltip(c, "tip", r.id, "Bold (⌘B)", at~, side=Bottom, offset=-4.0)
    })
    |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(@ui.Role::Button, label="Bold").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(tooltip_delay_ms)
  assert_true(shown.val)
  t.draw()
  let (tx, ty, tw, th) = t.get(@ui.Role::Tooltip, label="Bold (⌘B)").rect
  // (the tip is over the trigger where the pointer is)
  assert_true(tx < x + w / 2.0 + 2.0 && ty < y + h / 2.0 && tx + tw > x + w / 2.0 && ty + th > y + h / 2.0)
  t.run_for(tooltip_delay_ms)
  assert_true(shown.val)
}

///|
test "tooltip: to a finger, shown as it is held on the trigger (no tap then), gone a moment after it is lifted or with the next touch" {
  let shown = Ref(false)
  let taps = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      c.column(gap=40.0, pad=80.0, fn() {
        let r = button(c, "Bold", key="bold")
        if r.clicked {
          taps.val += 1
        }
        shown.val = tooltip(c, "tip", r.id, "Bold")
      })
      |> ignore
    },
    platform=2,
  )
  let (x, y, w, h) = t.get(@ui.Role::Button, label="Bold").rect
  // a tap: a tap, no tip
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(taps.val, 1)
  assert_false(shown.val)
  // held: the tip, and lifting it taps nothing
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  assert_true(shown.val)
  let lifted = t.time()
  t.release(x + w / 2.0, y + h / 2.0)
  assert_eq(taps.val, 1)
  assert_true(shown.val)
  // (a millisecond before it goes)
  let due = lifted + tooltip_lifted_ms
  t.run_for(due - 1.0 - t.time())
  assert_true(shown.val)
  t.run_for(due - t.time())
  assert_false(shown.val)
  // held again and lifted: the next touch puts it away at once, wherever it lands, a tap let go before a frame saw it
  // down too; one on the trigger itself is a tap of it
  for at in [(10.0, 10.0), (x + w / 2.0, y + h / 2.0)] {
    t.press_at(x + w / 2.0, y + h / 2.0)
    t.draw()
    t.run_for(@ui.long_press_ms)
    t.release(x + w / 2.0, y + h / 2.0)
    assert_true(shown.val)
    t.tap(at.0, at.1)
    assert_false(shown.val, msg="a tap at \{at}")
  }
  assert_eq(taps.val, 2)
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  t.press_at(10.0, 10.0)
  t.draw()
  assert_false(shown.val, msg="a finger down elsewhere")
  t.release(10.0, 10.0)
}

///|
test "hover card: to a finger, opened as it holds the trigger, or by a tap with `tap`; a press outside closes it" {
  let held = Ref(false)
  let tapped = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      c.column(gap=40.0, pad=80.0, fn() {
        let a = button(c, "Held", key="held")
        held.val = hover_card(c, "card-a", a.id, fn() { c.text("A's card") |> ignore })
        let b = button(c, "Tapped", key="tapped")
        tapped.val = hover_card(c, "card-b", b.id, tap=true, fn() { c.text("B's card") |> ignore })
      })
      |> ignore
    },
    platform=2,
  )
  let (ax, ay, aw, ah) = t.get(@ui.Role::Button, label="Held").rect
  // a tap on one without `tap`: nothing
  t.tap(ax + aw / 2.0, ay + ah / 2.0)
  assert_false(held.val)
  t.press_at(ax + aw / 2.0, ay + ah / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.release(ax + aw / 2.0, ay + ah / 2.0)
  assert_true(held.val)
  // a press outside closes it
  t.tap(380.0, 800.0)
  assert_false(held.val)
  let (bx, by, bw, bh) = t.get(@ui.Role::Button, label="Tapped").rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_true(tapped.val)
  // tapped again: closed
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_false(tapped.val)
}

///|
test "tooltip: by its trigger from the first frame it is drawn, the trigger come with the keyboard's focus on it; and as it goes, its trigger gone with it" {
  let shows = Ref(false)
  let trigger = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=200.0, fn() {
      if shows.val {
        let r = button(c, "Bold", key="bold")
        trigger.val = r.id
        if !c.has_focus(r.id) {
          c.focus_on(r.id, visible=true)
        }
      }
      tooltip(c, "tip", trigger.val, "Bold (⌘B)") |> ignore
    })
    |> ignore
  })
  // where the tip's words are drawn, if anywhere: never by the window's corner (the trigger is 200 in)
  let by_trigger = fn() raise {
    match t.drawn_of("Bold (⌘B)") {
      Some((x, y)) => assert_true(x > 100.0 && y > 100.0, msg="the tip drawn at (\{x}, \{y})")
      None => ()
    }
  }
  shows.val = true
  t.draw()
  by_trigger()
  t.draw()
  assert_true(t.drawn_of("Bold (⌘B)") is Some(_))
  by_trigger()
  // the trigger gone, its focus with it: the tip goes out where it was
  shows.val = false
  t.draw()
  by_trigger()
  t.run_for(@kit.pop_out_ms / 2.0)
  by_trigger()
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
  let (ax, ay, aw, ah) = t.get(@ui.Role::Button, label="A").rect
  let (bx, by, bw, bh) = t.get(@ui.Role::Button, label="B").rect
  t.move(ax + aw / 2.0, ay + ah / 2.0)
  t.run_for(tooltip_delay_ms)
  assert_true(a.val)
  t.move(bx + bw / 2.0, by + bh / 2.0)
  t.draw()
  assert_false(a.val)
  assert_true(b.val)
  // its skip gone by: the wait again
  t.move(1.0, 1.0)
  t.run_for(tooltip_skip_ms)
  t.move(ax + aw / 2.0, ay + ah / 2.0)
  t.draw()
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
  let (x, y, w, h) = t.get(@ui.Role::Button, label="@ada").rect
  // (taken at its moment)
  let moved = t.time()
  t.move(x + w / 2.0, y + h / 2.0)
  let due = moved + hover_card_open_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_false(open.val)
  t.run_for(due - t.time())
  assert_true(open.val)
  t.draw()
  // onto the card: still open
  let (cx, cy, cw, ch) = t.rect_of("Ada Lovelace").unwrap()
  t.move(cx + cw / 2.0, cy + ch / 2.0)
  t.run_for(hover_card_close_ms)
  assert_true(open.val)
  // off both: closed after its delay
  // (taken at its moment)
  let moved = t.time()
  t.move(380.0, 800.0)
  let due = moved + hover_card_close_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_true(open.val)
  t.run_for(due - t.time())
  assert_false(open.val)
}

///|
test "hover card and tooltip: not while a press elsewhere is dragged across the trigger; once let go there, after the wait" {
  let card = Ref(false)
  let tip = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=40.0, pad=40.0, fn() {
      let a = button(c, "@ada", key="ada", variant=Ghost)
      card.val = hover_card(c, "card", a.id, fn() { c.text("Ada Lovelace, the first programmer") |> ignore })
      let b = button(c, "Bold", key="bold")
      tip.val = tooltip(c, "tip", b.id, "Bold (⌘B)")
    })
    |> ignore
  })
  let (ax, ay, aw, ah) = t.get(@ui.Role::Button, label="@ada").rect
  let (bx, by, bw, bh) = t.get(@ui.Role::Button, label="Bold").rect
  // pressed on the ground (an edge dragged), carried over each trigger and held there past its wait: neither opens
  t.press_at(380.0, 800.0)
  t.move(ax + aw / 2.0, ay + ah / 2.0)
  t.run_for(hover_card_open_ms * 2.0)
  assert_false(card.val)
  t.move(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(tooltip_delay_ms * 2.0)
  assert_false(tip.val)
  // let go there: the tip once the pointer has rested its wait from then
  let lifted = t.time()
  t.release(bx + bw / 2.0, by + bh / 2.0)
  t.move(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(lifted + tooltip_delay_ms - 1.0 - t.time())
  assert_false(tip.val)
  t.run_for(lifted + tooltip_delay_ms - t.time())
  assert_true(tip.val)
  // and the card so, the pointer come to it with no button down
  let moved = t.time()
  t.move(ax + aw / 2.0, ay + ah / 2.0)
  t.run_for(moved + hover_card_open_ms - 1.0 - t.time())
  assert_false(card.val)
  t.run_for(moved + hover_card_open_ms - t.time())
  assert_true(card.val)
}

///|
test "toasts: each goes after its time, paused under the pointer; closed, acted on, swiped away" {
  let list : Ref[Array[Toast]] = Ref([])
  let acted : Ref[String?] = Ref(None)
  // how long the test gives each toast
  let life_ms = 3000.0
  let t = @ui.Tester::new(fn(c) {
    let r = toaster(c, "toasts", list.val, duration=life_ms)
    list.val = r.open
    if r.acted is Some(_) {
      acted.val = r.acted
    }
  })
  list.val = [toast("a", "Saved"), toast("b", "Sent", description="To the team", action="Undo")]
  t.draw()
  assert_eq(t.all(@ui.Role::Status).length(), 2)
  assert_eq(t.get(@ui.Role::Status, label="Sent").description, "To the team")
  ignore(t.get(@ui.Role::Region, label="通知"))
  // paused while the pointer is over them
  let (x, y, w, h) = t.get(@ui.Role::Status, label="Saved").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(life_ms)
  assert_eq(list.val.length(), 2)
  // (none of their time went by before the pointer came over them)
  // (taken at its moment)
  let moved = t.time()
  t.move(1.0, 1.0)
  let due = moved + life_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_eq(list.val.length(), 2)
  t.run_for(due - t.time())
  assert_eq(list.val.map(fn(x) { x.id }), [])
  // drawn while they go out (from the frame at their time), gone once they have
  t.run_for(presence_out_ms)
  assert_eq(t.all(@ui.Role::Status).length(), 0)
  // the action
  list.val = [toast("c", "Archived", action="Undo")]
  t.draw()
  // come in (it rises as it does)
  t.run_for(presence_in_ms)
  t.click(@ui.Role::Button, label="Undo")
  assert_eq(acted.val, Some("c"))
  assert_eq(list.val.length(), 0)
  // the close button
  list.val = [toast("d", "Copied")]
  t.draw()
  t.run_for(presence_in_ms)
  t.click(@ui.Role::Button, label="关闭")
  assert_eq(list.val.length(), 0)
  // a swipe to the right
  list.val = [toast("e", "Moved")]
  t.draw()
  t.run_for(presence_in_ms)
  let (x, y, w, h) = t.get(@ui.Role::Status, label="Moved").rect
  t.drag(x + 20.0, y + h / 2.0, x + 20.0 + w / 2.0, y + h / 2.0)
  assert_eq(list.val.length(), 0)
  t.run_for(presence_out_ms)
  assert_true(t.query(@ui.Role::Status, label="Moved") is None)
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
  let (_, y, _, h) = t.get(@ui.Role::Dialog, label="Chat info").rect
  assert_eq(y, 844.0 - 300.0)
  assert_eq(h, 300.0)
  assert_true(t.query(@ui.Role::Text, label="Page") is None)
  t.click(@ui.Role::Button, label="Pin")
  assert_true(open.val)
  t.tap(100.0, 100.0)
  assert_false(open.val)
  to_rest(t, "s")
  assert_true(t.query(@ui.Role::Dialog) is None)
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
  assert_true((t.get(@ui.Role::Dialog, label="Workspaces").rect.3 - 422.0).abs() < 1.0)
  // dragged up past the middle: full
  t.drag(195.0, 430.0, 195.0, 200.0)
  to_rest(t, "s")
  assert_true((t.get(@ui.Role::Dialog, label="Workspaces").rect.3 - 844.0 * 0.94).abs() < 1.0)
  // asked another height: there
  tall.val = 0.7
  to_rest(t, "s")
  assert_true((t.get(@ui.Role::Dialog, label="Workspaces").rect.3 - 844.0 * 0.7).abs() < 1.0)
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
  assert_true(t.query(@ui.Role::Dialog) is None)
  t.assert_idle()
}

///|
test "sheet: asked another height while open (what it holds grown), that tall at once; closed, it sinks away from there and is gone" {
  let open = Ref(true)
  let tall = Ref(300.0)
  let shown = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let r = sheet(c, "s", open.val, h=tall.val, fn() { button(c, "OK") |> ignore })
    shown.val = r.shown
    if r.open != open.val {
      open.val = r.open
    }
  })
  to_rest(t, "s")
  // what it holds grew (a fitted sheet as this frame lays it out): placed by its size, not chased to it
  tall.val = 600.0
  t.draw()
  let (_, _, _, h) = t.get(@ui.Role::Dialog).rect
  assert_eq(h, 600.0)
  // (nothing set off by it: the sheet at rest)
  assert_true(sheet_rest("s") <= t.time())
  open.val = false
  t.draw()
  t.run_for(sheet_rest("s") - t.time())
  assert_false(shown.val)
  assert_true(t.query(@ui.Role::Dialog) is None)
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
  let (_, y, _, h) = t.get(@ui.Role::Status, label="Saved").rect
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
  assert_true(t.get(@ui.Role::Button, label="OK").rect.1 >= 844.0 - 300.0)
  open.val = false
  t.draw()
  let down = sheet_rest("info")
  t.run_for(down - t.time())
  t.assert_idle()
  assert_false(shown.val)
  assert_eq(sheet_rest("nothing of that name"), -1.0)
}

///|
test "toasts: one gone (its time out) is drawn going away until its rest (toast_rest), then nothing moves" {
  let list : Ref[Array[Toast]] = Ref([])
  let life = 3000.0
  let t = @ui.Tester::new(fn(c) { list.val = toaster(c, "toasts", list.val, duration=life).open })
  list.val = [toast("a", "Saved")]
  t.draw()
  t.run_for(life)
  assert_eq(list.val.length(), 0)
  t.draw()
  let rest = toast_rest("toasts")
  assert_true(rest > t.time() && rest < @double.infinity)
  t.run_for(rest - t.time())
  assert_eq(t.all(@ui.Role::Status).length(), 0)
  assert_eq(toast_rest("toasts"), -1.0)
  t.assert_idle()
}

///|
test "toasts: toast_due says when the next goes (its time out), none while paused; at it, it goes and its exit begins" {
  let list : Ref[Array[Toast]] = Ref([])
  let life = 2600.0
  let t = @ui.Tester::new(fn(c) { list.val = toaster(c, "toasts", list.val, duration=life).open })
  assert_eq(toast_due("toasts"), -1.0)
  list.val = [toast("a", "Saved")]
  t.draw()
  let shown = t.time()
  assert_true((toast_due("toasts") - (shown + life)).abs() < 0.001, msg="\{toast_due("toasts")}")
  // (not a wake what is shown waits for)
  t.run_for(presence_in_ms)
  assert_eq(t.next_wake(), None)
  // paused under the pointer: none due
  let (x, y, w, h) = t.get(@ui.Role::Status, label="Saved").rect
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(toast_due("toasts"), -1.0)
  t.move(1.0, 1.0)
  // going on again: what was left of its time from here (none of it went while paused)
  let due = toast_due("toasts")
  assert_true(due > t.time() && due < shown + life + presence_in_ms + 100.0, msg="\{due}")
  t.run_for(due - t.time())
  assert_eq(list.val.length(), 0)
  assert_eq(toast_due("toasts"), -1.0)
  let rest = toast_rest("toasts")
  assert_true(rest > t.time() && rest < @double.infinity)
  t.run_for(rest - t.time())
  assert_eq(t.all(@ui.Role::Status).length(), 0)
  t.assert_idle()
}

///|
test "popover: a wheel turned over it scrolls nothing under it; beside it, what is under scrolls" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      let tr = button(c, "Filters", key="filters")
      if tr.clicked {
        open.val = !open.val
      }
      scroll_area(c, "s", 400.0, label="Log", fn() {
        c.column(fn() {
          for i in 0..<80 {
            c.text("line \{i}") |> ignore
          }
        })
        |> ignore
      })
      open.val = popover(c, "pop", open.val, tr.id, label="Filters", focus=false, fn() { c.text("Unread only") |> ignore }).value
    })
    |> ignore
  })
  t.click(@ui.Role::Button, label="Filters")
  t.run_for(pop_ms)
  let (px, py, pw, ph) = t.get(@ui.Role::Dialog, label="Filters").rect
  let (sx, sy, sw, sh) = t.get(@ui.Role::ScrollArea, label="Log").rect
  // (the popover lies over the list)
  assert_true(py < sy + sh && py + ph > sy && px < sx + sw)
  let (_, y0, _, _) = t.rect_of("line 0").unwrap()
  t.wheel(px + pw / 2.0, py + ph / 2.0, 120.0)
  t.run_for(pop_ms)
  assert_eq(t.rect_of("line 0").map(fn(r) { r.1 }), Some(y0))
  assert_true(open.val)
  // beside it, the list takes the wheel
  t.wheel(sx + sw - 4.0, sy + sh - 4.0, 120.0)
  t.run_for(pop_ms)
  let (_, y1, _, _) = t.rect_of("line 0").unwrap_or((0.0, -1000.0, 0.0, 0.0))
  assert_true(y1 < y0)
}

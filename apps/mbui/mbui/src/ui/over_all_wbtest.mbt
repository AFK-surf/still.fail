// What of the window's tree is over all else of it (View::over_all: a toast's) where the old frame has a modal layer
// open (a sheet of the old views'): drawn over the layer, pressed where it is drawn and the layer beside it, read out
// and acted on, gone to by Tab and pressed by Enter; going out (leaving), none of it.

///|
/// An old view the whole window (400 by 300) with a modal layer over it, a button the whole of it (pressed: `under`
/// counted); a node of the tree's over all else at the window's top left, 80 by 40, read out as a button "顶上"
/// (pressed: `top` counted), there while `on` (leaving over 100 ms); made after it, a node of the root's where it is, as
/// big (pressed: `late` counted), there while `late_on`. The layer open while `open` (dismissed, not); the keys the
/// page under it is given, in `page_keys`.
fn over_all_tester(
  on : @signals.Signal[Bool],
  top : Ref[Int],
  under : Ref[Int],
  late_on? : @signals.Signal[Bool] = @signals.signal(false),
  late? : Ref[Int] = Ref(0),
  open? : Ref[Bool] = Ref(true),
  page_keys? : Array[Int] = [],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      // (the page under the layer: what keys come to it, taking them all)
      h
      .grow(Is(1.0))
      .on_key(fn(k) {
        page_keys.push(k.code)
        true
      })
      |> ignore
      old(h, fn(c) {
        guard open.val else { return }
        let o = c.overlay("sheet", modal=true, outside=false, fn() {
          let id = c.id("sheet button")
          c.focusable(id)
          if c.interact(id).clicked {
            under.val = under.val + 1
          }
          let b = c.box(id~, w=Px(400.0), h=Px(300.0), bg=0xFFFFFFFFL, fn() {  })
          c.semantics(b, Button, id~, label="弹层", actions=[Activate])
        })
        if o.dismissed is Some(_) {
          open.val = false
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.over(Is(true)).over_all(Is(true)) |> ignore
      v.show(fn() { on.get() }, fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .ground(Is(0xFF7F7FFFL))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="顶上"))))
        .on_press(fn() { top.val = top.val + 1 })
        |> ignore
      }, leave=over_all_leave_ms)
    })
    |> ignore
    root.show(fn() { late_on.get() }, fn(l) {
      l
      .over(Is(true))
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .ground(Is(0xFFFFFFFFL))
      .presses(Is(true))
      .on_press(fn() { late.val = late.val + 1 })
      |> ignore
    })
  })
  t.draw()
  t.draw()
  t
}

///|
test "over all else, the old frame's modal layer open: drawn over it, pressed where it is drawn, the layer beside it" {
  let (top, old) = (Ref(0), Ref(0))
  let t = over_all_tester(@signals.signal(true), top, old)
  // (its ground the last drawn there: over the layer's)
  let rects = t.drawn_rects()
  let last = rects.length() - 1
  let over = last >= 0 && rects[last].0 == 0.0 && rects[last].1 == 0.0 && rects[last].2 == 80.0 && rects[last].3 == 40.0
  t.tap(40.0, 20.0)
  let pressed = (top.val, old.val)
  t.tap(200.0, 150.0)
  assert_eq((over, pressed, (top.val, old.val)), (true, (1, 0), (1, 1)), msg="\{rects}")
}

///|
test "over all else, the old frame's modal layer open: read out, acted on and focused as a screen reader asks; Tab goes to it, Enter presses it" {
  let (top, old) = (Ref(0), Ref(0))
  let t = over_all_tester(@signals.signal(true), top, old)
  let read = t.all(Button, label="顶上").length()
  t.act(Button, Activate, label="顶上")
  let acted = top.val
  t.act(Button, Focus, label="顶上")
  let focused = t.focused().map(fn(s) { s.label })
  // (Tab from it round to the layer's, and back to it)
  t.tab()
  let tabbed = t.focused().map(fn(s) { s.label })
  t.tab()
  let back = t.focused().map(fn(s) { s.label })
  t.key(key_enter)
  assert_eq(
    (read, acted, focused, tabbed, back, top.val, old.val),
    (1, 1, Some("顶上"), Some("弹层"), Some("顶上"), 2, 0),
  )
}

///|
test "over all else, going out: pressed, acted on and gone to by Tab no more, a press there the layer's" {
  let (top, old) = (Ref(0), Ref(0))
  let on = @signals.signal(true)
  let t = over_all_tester(on, top, old)
  // (the id it is read out by as it is there: asked of it as it goes, as a screen reader would ask it)
  let id = t.query(Button, label="顶上").map(fn(s) { s.id }).unwrap_or(0)
  on.set(false)
  // (asked at once, no frame drawn since)
  g().ask_action(id, Activate)
  let at_once = top.val
  t.draw()
  // (leaving: still drawn, half its way gone)
  t.run_for(over_all_leave_ms / 2.0)
  g().ask_action(id, Activate)
  let leaving = top.val
  // (read out still as it goes, nothing to be done to it)
  let reads = t.all(Button, label="顶上").filter(fn(s) { s.actions.contains(Activate) }).length()
  t.tap(40.0, 20.0)
  t.tab()
  t.tab()
  let tabbed = t.focused().map(fn(s) { s.label })
  assert_eq((id != 0, at_once, leaving, reads, top.val, old.val, tabbed), (true, 0, 0, 0, 0, 1, Some("弹层")))
}

///|
test "over all else, a node of the root's made after it, later: under it, drawn and pressed under it" {
  let (top, under, late) = (Ref(0), Ref(0), Ref(0))
  let late_on = @signals.signal(false)
  let t = over_all_tester(@signals.signal(true), top, under, late_on~, late~)
  // (its own ground, drawn alone there: the last drawn)
  let own = t.drawn_rects().last().map(fn(r) { r.4 })
  late_on.set(true)
  t.draw()
  let rects = t.drawn_rects()
  let last = rects.last().map(fn(r) { (r.0, r.1, r.2, r.3, r.4) })
  let lates = rects.filter(fn(r) { r.0 == 0.0 && r.1 == 0.0 && r.2 == 80.0 && r.3 == 40.0 }).length()
  t.tap(40.0, 20.0)
  assert_eq(
    (last.map(fn(r) { r.4 }) == own, lates, top.val, late.val, under.val),
    (true, 2, 1, 0, 0),
    msg="\{rects}",
  )
}

///|
test "over all else with the focus, the old frame's modal layer open: Enter presses it; a key it does not take not the page's under the layer, Escape the layer's (it closes)" {
  let (top, under) = (Ref(0), Ref(0))
  let open = Ref(true)
  let page_keys : Array[Int] = []
  let t = over_all_tester(@signals.signal(true), top, under, open~, page_keys~)
  t.act(Button, Focus, label="顶上")
  t.key(key_enter)
  let pressed = top.val
  t.key(key_code_up)
  let up = (page_keys.copy(), open.val)
  t.key(key_escape)
  t.draw()
  assert_eq((pressed, up, page_keys, open.val), (1, ([], true), [], false))
}

///|
/// A node "P" holding a node "C" that takes presses (there while `c_on`), 80 by 40 at the window's top left; over it,
/// while `cover_on`, a node of the root's taking presses, as big. What P says of the pointer within what it holds
/// (View::pointed_in), as it is told.
fn pointed_in_tester(c_on : @signals.Signal[Bool], cover_on : @signals.Signal[Bool]) -> (Tester, Ref[Bool]) {
  let within = Ref(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
      p.reacts(fn() { p.pointed_in() }, fn(w) { within.val = w })
      p.show(fn() { c_on.get() }, fn(c) {
        c.width(Is(Some(80.0))).height(Is(Some(40.0))).presses(Is(true)).on_press(fn() {  }) |> ignore
      })
    })
    |> ignore
    root.show(fn() { cover_on.get() }, fn(v) {
      v.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(40.0))).presses(Is(true)).on_press(fn() {  }) |> ignore
    })
  })
  t.draw()
  (t, within)
}

///|
test "the pointer on a node held by another, still: the holder pointed within; the node let go, not, the pointer not moved" {
  let c_on = @signals.signal(true)
  let (t, within) = pointed_in_tester(c_on, @signals.signal(false))
  t.move(40.0, 20.0)
  t.draw()
  let on = within.val
  c_on.set(false)
  t.draw()
  assert_eq((on, within.val), (true, false))
}

///|
test "the pointer on a node held by another, still: something over it taking presses there come, the holder pointed within no more" {
  let cover_on = @signals.signal(false)
  let (t, within) = pointed_in_tester(@signals.signal(true), cover_on)
  t.move(40.0, 20.0)
  t.draw()
  let on = within.val
  cover_on.set(true)
  t.draw()
  assert_eq((on, within.val), (true, false))
}

///|
test "over all else, a modal layer of the tree's open under it: pressed and acted on, the layer beside it" {
  let (top, layer) = (Ref(0), Ref(0))
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(m) {
      m.over(Is(true)).modal(Is(true)).presses(Is(true)).on_press(fn() { layer.val = layer.val + 1 }) |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.over(Is(true)).over_all(Is(true)).row(Is(true)) |> ignore
      v.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .presses(Is(true))
        .says(Is(Some(@view.said(Button, label="顶上"))))
        .on_press(fn() { top.val = top.val + 1 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.tap(40.0, 20.0)
  t.act(Button, Activate, label="顶上")
  t.tap(200.0, 150.0)
  assert_eq((top.val, layer.val), (2, 1))
}

///|
/// How long the node over all else takes to leave (over_all_tester's).
let over_all_leave_ms : Double = 100.0

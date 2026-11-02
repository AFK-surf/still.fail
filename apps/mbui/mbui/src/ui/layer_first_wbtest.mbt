// A modal layer that gives the focus, as it opens, to the first of what it holds that takes it
// (View::focus_opens_first), as an old trapping overlay does by default (Ctx::overlay's initial_focus): the first of the
// fields an old view it hosts builds, typed into at once; moved on to the second, kept there as the old view is built
// again; none taking it, its own ground. And Ctx::blur: no layer, the tree's or the old frame's, gives back the focus
// let go of as each goes.

///|
/// A window whose tree holds an old view with a field "页字段" (asking for the focus as it is first built); while
/// `open`, a modal layer of the tree's over it giving the focus to the first of what it holds that takes it (or, `old`,
/// an old modal overlay of that old view's own, as the old frame does), holding an old view with fields "甲框" and
/// "乙框" (`fields`: else words alone), built again as `again` changes.
fn first_tester(
  open : @signals.Signal[Bool],
  again : @signals.Signal[Int],
  fields : Bool,
  old_frame : Bool,
  a : Field,
  b : Field,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  let asked = Ref(false)
  let held = fn(c : Ctx) {
    again.get() |> ignore
    if fields {
      c.editor("层/甲", field=a, placeholder="甲框") |> ignore
      c.editor("层/乙", field=b, placeholder="乙框") |> ignore
    } else {
      c.text("只有字") |> ignore
    }
  }
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        c.editor("页/字段", placeholder="页字段") |> ignore
        if !asked.val {
          asked.val = true
          c.focus_editor("页/字段")
        }
        if old_frame && open.get() {
          c.stacked(2, fn() { c.overlay("弹层", modal=true, outside=false, fn() { held(c) }) |> ignore })
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    if !old_frame {
      root.show(fn() { open.get() }, fn(l) {
        l.over(Is(true)).stacked(Is(2)).modal(Is(true)).presses(Is(true)).focusable(Is(true), keys=0, tab=false) |> ignore
        old(l, fn(c) { held(c) }).height(Is(Some(120.0))).width(Is(Some(200.0))) |> ignore
        l.focus_opens_first() |> ignore
      })
    }
  })
  t
}

///|
fn first_focused(t : Tester) -> String {
  t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
}

///|
/// What the focus is on: as the page is first drawn, the layer opened, a word typed, Tab, the old view built again,
/// the layer closed.
fn first_said(fields : Bool, old_frame : Bool) -> Array[String] {
  let (open, again) = (@signals.signal(false), @signals.signal(0))
  let (a, b) = (Field::new(), Field::new())
  let t = first_tester(open, again, fields, old_frame, a, b)
  t.draw()
  let page = first_focused(t)
  open.set(true)
  t.draw()
  let opened = first_focused(t)
  t.type_text("字")
  t.draw()
  let typed = "\{first_focused(t)} 甲 \{a.text()} 乙 \{b.text()}"
  t.key(key_tab)
  t.draw()
  let tabbed = first_focused(t)
  again.set(1)
  t.draw()
  let built = first_focused(t)
  open.set(false)
  t.draw()
  [page, opened, typed, tabbed, built, first_focused(t)]
}

///|
test "a modal layer giving the focus to the first that takes it: its first field, typed into; Tab to the second, kept there as what holds them is built again; closed, back on the page's field: as an old trapping overlay" {
  let tree = first_said(true, false)
  let old_one = first_said(true, true)
  assert_eq((tree == old_one, tree), (true, [
    "TextField 页字段", "TextField 甲框", "TextField 甲框 甲 字 乙 ", "TextField 乙框", "TextField 乙框", "TextField 页字段",
  ]))
}

///|
test "a modal layer giving the focus to the first that takes it, holding nothing that takes it: its own ground; closed, back on the page's field: as an old trapping overlay" {
  let tree = first_said(false, false)
  let old_one = first_said(false, true)
  assert_eq((tree[0], tree[5], old_one[0], old_one[5], tree[1] == old_one[1]), (
    "TextField 页字段", "TextField 页字段", "TextField 页字段", "TextField 页字段", true,
  ))
}

///|
test "two layers of the tree's open, each giving the focus to its field, the focus let go of (Ctx::blur), then each closed, the top first: nothing given the focus back" {
  let (low, high) = (@signals.signal(false), @signals.signal(false))
  let asked = Ref(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        c.editor("页/字段", placeholder="页字段") |> ignore
        if !asked.val {
          asked.val = true
          c.focus_editor("页/字段")
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    for k, layer in [(low, "下层框"), (high, "上层框")] {
      let (open, name) = layer
      root.show(fn() { open.get() }, fn(l) {
        l.over(Is(true)).stacked(Is(2 + k)).modal(Is(true)).presses(Is(true)).focusable(Is(true), keys=0, tab=false) |> ignore
        old(l, fn(c) { c.editor("层/\{name}", placeholder=name) |> ignore }).height(Is(Some(60.0))).width(Is(Some(200.0))) |> ignore
        l.focus_opens_first() |> ignore
      })
    }
  })
  t.draw()
  low.set(true)
  t.draw()
  let low_open = first_focused(t)
  high.set(true)
  t.draw()
  let high_open = first_focused(t)
  g().blur()
  t.draw()
  let let_go = first_focused(t)
  high.set(false)
  t.draw()
  let high_closed = first_focused(t)
  low.set(false)
  t.draw()
  assert_eq([low_open, high_open, let_go, high_closed, first_focused(t)], [
    "TextField 下层框", "TextField 上层框", "none", "none", "none",
  ])
}

///|
/// A window whose tree holds an old view with a field "页字段" (given the focus as it is first built; while `step` is 1,
/// as it is built, the focus let go of and that field asking for it again); while `low` and `high`, modal layers of the
/// tree's over it at 2 and 3 giving the focus to the first that takes it, each holding an old view with a field
/// ("下层框", "上层框").
fn stacked_tester(low : @signals.Signal[Bool], high : @signals.Signal[Bool], step : @signals.Signal[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  let asked = Ref(false)
  let let_go = Ref(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        c.editor("页/字段", placeholder="页字段") |> ignore
        if !asked.val {
          asked.val = true
          c.focus_editor("页/字段")
        }
        // (once, as the frame it is set in builds it)
        if step.get() == 1 && !let_go.val {
          let_go.val = true
          c.blur()
          c.focus_editor("页/字段")
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    for k, layer in [(low, "下层框"), (high, "上层框")] {
      let (open, name) = layer
      root.show(fn() { open.get() }, fn(l) {
        l.over(Is(true)).stacked(Is(2 + k)).modal(Is(true)).presses(Is(true)).focusable(Is(true), keys=0, tab=false) |> ignore
        old(l, fn(c) { c.editor("层/\{name}", placeholder=name) |> ignore }).height(Is(Some(60.0))).width(Is(Some(200.0))) |> ignore
        l.focus_opens_first() |> ignore
      })
    }
  })
  t
}

///|
test "two layers giving the focus to the first that takes it opened in one change: the top's field; the top closed, the one under it's field (not taken by it before); that closed, back on the page's field" {
  let (low, high, step) = (@signals.signal(false), @signals.signal(false), @signals.signal(0))
  let t = stacked_tester(low, high, step)
  t.draw()
  // (in one change, as layer_focus_wbtest's both_opened)
  @signals.start_batch()
  low.set(true)
  high.set(true)
  @signals.end_batch()
  t.draw()
  let both = first_focused(t)
  high.set(false)
  t.draw()
  let low_only = first_focused(t)
  low.set(false)
  t.draw()
  assert_eq([both, low_only, first_focused(t)], ["TextField 上层框", "TextField 下层框", "TextField 页字段"])
}

///|
test "a layer giving the focus to the first that takes it opened, in that frame the focus let go of and the page's field asking for it under the layer: not given its field after; closed, nothing given the focus back" {
  let (low, high, step) = (@signals.signal(false), @signals.signal(false), @signals.signal(0))
  let t = stacked_tester(low, high, step)
  t.draw()
  low.set(true)
  step.set(1)
  t.draw()
  step.set(2)
  t.draw()
  let opened = first_focused(t)
  low.set(false)
  t.draw()
  // (as it opened: let go of in that frame, not given its field after, the person's having let it go; closed: nothing
  // given back)
  assert_eq([opened, first_focused(t)], ["none", "none"])
}

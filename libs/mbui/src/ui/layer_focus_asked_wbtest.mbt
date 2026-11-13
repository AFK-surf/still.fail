// A field of an old view asking for the focus (Ctx::focus_editor) under a modal layer of the tree's that gives the
// focus as it opens (View::focus_opens). Asked as the frame the layer opened in builds it (a page first drawn under it,
// or opened in the same change): what the layer gives back as it goes, as an old overlay built over the page in that
// frame has it. Asked a frame after: not given it, the focus in the layer, what had it as it opened kept (the old
// overlay's, recorded once). A field in an old layer of its own over the tree's (a menu an old view opens) asks for
// its own: taken.

///|
/// An old view the whole window with a button "旧按钮" and a field "页字段" (asking for the focus once as it is built
/// while `ask`); while `open`, a modal layer of the tree's at 2 over it holding "取消", giving it the focus as it opens,
/// and an old view's field "层字段" given the focus once as it opens (as a question's field is); while `menu`, an old
/// modal layer of the old view's own at 3 over that, giving the focus to none of its own, holding a field "弹层字段"
/// asking for the focus as it is built.
fn asked_tester(
  open : @signals.Signal[Bool],
  ask : @signals.Signal[Bool],
  menu : @signals.Signal[Bool],
) -> Tester {
  let asked = Ref(false)
  // (the tree made first, what hosts it told of its layers' focus as it is made (set_view_app), then its layer open:
  // as a question is made once the window's width is known, not as the tree is made)
  let ready = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        let id = c.id("旧按钮")
        c.focusable(id)
        let b = c.box(id~, w=Px(120.0), h=Px(40.0), top=100.0, left=0.0, fn() {  })
        c.semantics(b, Button, id~, label="旧按钮", actions=[Activate])
        c.editor("页/字段", placeholder="页字段") |> ignore
        // (once each time it is asked: a chat's composer asks as its chat is switched to)
        if ask.get() {
          if !asked.val {
            asked.val = true
            c.focus_editor("页/字段")
          }
        } else {
          asked.val = false
        }
        if menu.get() {
          c.stacked(3, fn() {
            c.overlay("弹层", modal=true, initial_focus=0, outside=false, fn() {
              c.editor("弹层/字段", placeholder="弹层字段") |> ignore
              if !c.has_focus(c.id("弹层/字段")) {
                c.focus_editor("弹层/字段")
              }
            })
            |> ignore
          })
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { ready.get() && open.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(2)).modal(Is(true)).presses(Is(true)) |> ignore
      let no = l.box(fn(x) {
        x
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="取消"))))
        .on_press(fn() {  })
        |> ignore
      })
      l.focus_opens(no) |> ignore
      // (its own field, an old view's, given the focus as it opens, once, as a question's is: ask_node)
      let mine = Ref(false)
      old(l, fn(c) {
        c.editor("层/字段", placeholder="层字段") |> ignore
        if !mine.val {
          mine.val = true
          c.focus_editor("层/字段")
        }
      })
      .height(Is(Some(40.0)))
      .width(Is(Some(160.0)))
      |> ignore
    })
  })
  ready.set(true)
  t
}

///|
fn asked_focused(t : Tester) -> String {
  t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
}

///|
test "a modal layer of the tree's opened before the page under it was first drawn, nothing to give back: the field the page asks for the focus as it is first drawn not given it; the focus in it; closed, on that field" {
  let (open, ask, menu) = (@signals.signal(true), @signals.signal(true), @signals.signal(false))
  let t = asked_tester(open, ask, menu)
  t.draw()
  let inside = asked_focused(t)
  ask.set(false)
  open.set(false)
  t.draw()
  assert_eq((inside, asked_focused(t)), ("TextField 层字段", "TextField 页字段"))
}

///|
test "a modal layer of the tree's opened from the old button with the focus, a field of the page under it asking for the focus as that frame builds it: the focus in it; closed, on that field (as an old overlay built after the page has it)" {
  let (open, ask, menu) = (@signals.signal(false), @signals.signal(false), @signals.signal(false))
  let t = asked_tester(open, ask, menu)
  t.draw()
  t.act(Button, Focus, label="旧按钮")
  open.set(true)
  ask.set(true)
  t.draw()
  let inside = asked_focused(t)
  open.set(false)
  t.draw()
  assert_eq((inside, asked_focused(t)), ("TextField 层字段", "TextField 页字段"))
}

///|
test "a modal layer of the tree's opened from the old button with the focus, a field of the page under it asking for the focus a frame after it opened: not given it, the focus in it still; closed, back on the old button, not that field" {
  let (open, ask, menu) = (@signals.signal(false), @signals.signal(false), @signals.signal(false))
  let t = asked_tester(open, ask, menu)
  t.draw()
  t.act(Button, Focus, label="旧按钮")
  open.set(true)
  t.draw()
  ask.set(true)
  t.draw()
  let inside = asked_focused(t)
  open.set(false)
  t.draw()
  assert_eq((inside, asked_focused(t)), ("TextField 层字段", "Button 旧按钮"))
}

///|
test "a modal layer of the tree's at 2 opened before the page was first drawn, an old modal layer of the page's own at 3 over it giving the focus to none of its own, its field asking for the focus as it is built: that field has it; nothing given back to it by the tree's layer" {
  let (open, ask, menu) = (@signals.signal(true), @signals.signal(false), @signals.signal(true))
  let t = asked_tester(open, ask, menu)
  t.draw()
  t.draw()
  let up = asked_focused(t)
  assert_eq(up, "TextField 弹层字段")
}

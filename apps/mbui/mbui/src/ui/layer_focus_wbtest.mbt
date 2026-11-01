// A layer of the window's tree that gives the focus as it opens (View::focus_opens): the focus to the node it names as
// it opens, whatever had it (an old view's stop, a node of the tree's); back to that as it goes, where the focus is in
// it or nowhere then, no frame waited for; moved elsewhere meanwhile, left there.

///|
/// An old view the whole window with a button "旧按钮"; a node of the tree's, a button "树按钮" at the top left 80 by
/// 40; while `open`, a modal layer of the tree's over all of them holding "取消" (counted in `cancels`) and "确定"
/// (counted in `oks`), giving the focus to "取消" as it opens; leaving over `layer_focus_leave_ms`.
fn layer_focus_tester(open : @signals.Signal[Bool], cancels : Ref[Int], oks : Ref[Int]) -> Tester {
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
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b
      .over(Is(true))
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="树按钮"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)).modal(By(fn() { !l.leaving() })).row(Is(true)) |> ignore
      let button = fn(label : String, n : Ref[Int]) {
        l.box(fn(x) {
          x
          .width(Is(Some(80.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .focusable(Is(true))
          .says(Is(Some(@view.said(Button, label~))))
          .on_press(fn() { n.val = n.val + 1 })
          |> ignore
        })
      }
      let no = button("取消", cancels)
      button("确定", oks) |> ignore
      l.focus_opens(no) |> ignore
    }, leave=layer_focus_leave_ms)
  })
  t.draw()
  t
}

///|
let layer_focus_leave_ms : Double = 100.0

///|
fn layer_focused(t : Tester) -> String? {
  t.focused().map(fn(s) { s.label })
}

///|
test "a layer of the tree's giving the focus, opened from an old view's button with the focus: the focus on 取消, Enter its; closed, back on the old button, no frame waited for" {
  let open = @signals.signal(false)
  let (cancels, oks) = (Ref(0), Ref(0))
  let t = layer_focus_tester(open, cancels, oks)
  t.act(Button, Focus, label="旧按钮")
  let before = layer_focused(t)
  open.set(true)
  let opened = layer_focused(t)
  t.draw()
  t.key(key_enter)
  let entered = (cancels.val, oks.val)
  open.set(false)
  let closed = layer_focused(t)
  t.run_for(layer_focus_leave_ms)
  assert_eq((before, opened, entered, closed, layer_focused(t)), (Some("旧按钮"), Some("取消"), (1, 0), Some("旧按钮"), Some("旧按钮")))
}

///|
test "a layer of the tree's giving the focus, opened from the tree's button with the focus: the focus on 取消; closed, back on the tree's button" {
  let open = @signals.signal(false)
  let t = layer_focus_tester(open, Ref(0), Ref(0))
  t.act(Button, Focus, label="树按钮")
  open.set(true)
  t.draw()
  let opened = layer_focused(t)
  open.set(false)
  t.draw()
  assert_eq((opened, layer_focused(t)), (Some("取消"), Some("树按钮")))
}

///|
test "a layer of the tree's giving the focus, the focus moved in it to 确定: closed, back on what had it as it opened" {
  let open = @signals.signal(false)
  let t = layer_focus_tester(open, Ref(0), Ref(0))
  t.act(Button, Focus, label="树按钮")
  open.set(true)
  t.draw()
  t.tab()
  let moved = layer_focused(t)
  open.set(false)
  t.draw()
  assert_eq((moved, layer_focused(t)), (Some("确定"), Some("树按钮")))
}

///|
/// Two layers of the tree's giving the focus, each a modal layer holding a button "<name>的取消" it gives it to and
/// "<name>的确定" after it: "上" at
/// 5 while `up`, "下" at 4 while `down`, made in `order` (by name), each leaving over `leave`; under them a tree's button
/// "树按钮".
fn two_layers_tester(
  up : @signals.Signal[Bool],
  down : @signals.Signal[Bool],
  order? : Array[String] = ["上", "下"],
  leave? : Double = 0.0,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="树按钮"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    for name in order {
      let (on, stack) = if name == "上" { (up, 5) } else { (down, 4) }
      root.show(fn() { on.get() }, fn(v) {
        v.over(Is(true)).stacked(Is(stack)).modal(By(fn() { !v.leaving() })) |> ignore
        let no = v.box(fn(x) {
          x
          .width(Is(Some(80.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .focusable(Is(true))
          .says(Is(Some(@view.said(Button, label=name + "的取消"))))
          .on_press(fn() {  })
          |> ignore
        })
        v.box(fn(x) {
          x
          .width(Is(Some(80.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .focusable(Is(true))
          .says(Is(Some(@view.said(Button, label=name + "的确定"))))
          .on_press(fn() {  })
          |> ignore
        })
        |> ignore
        v.focus_opens(no) |> ignore
      }, leave~)
    }
  })
  t.draw()
  t
}

///|
/// Both of two_layers_tester's opened in one change from the tree's button with the focus: where the focus is then.
fn both_opened(t : Tester, up : @signals.Signal[Bool], down : @signals.Signal[Bool]) -> String? raise {
  t.act(Button, Focus, label="树按钮")
  @signals.start_batch()
  up.set(true)
  down.set(true)
  @signals.end_batch()
  layer_focused(t)
}

///|
test "two layers of the tree's giving the focus opened in one change, the upper (at 5) made before the lower (at 4): the focus on the upper's; the upper closed, on the lower's; the lower closed, back on the tree's button; no frame waited for" {
  let (up, down) = (@signals.signal(false), @signals.signal(false))
  let t = two_layers_tester(up, down)
  let opened = both_opened(t, up, down)
  up.set(false)
  let lower = layer_focused(t)
  down.set(false)
  let back = layer_focused(t)
  t.draw()
  assert_eq((opened, lower, back, layer_focused(t)), (Some("上的取消"), Some("下的取消"), Some("树按钮"), Some("树按钮")))
}

///|
test "two layers of the tree's giving the focus opened in one change: the lower closed first, the focus stays on the upper's; the upper closed, back on the tree's button; no frame waited for" {
  let (up, down) = (@signals.signal(false), @signals.signal(false))
  let t = two_layers_tester(up, down)
  let opened = both_opened(t, up, down)
  down.set(false)
  let stays = layer_focused(t)
  up.set(false)
  let back = layer_focused(t)
  t.draw()
  assert_eq((opened, stays, back, layer_focused(t)), (Some("上的取消"), Some("上的取消"), Some("树按钮"), Some("树按钮")))
}

///|
test "two layers of the tree's giving the focus opened in one change, closed in one change, made either way round: back on the tree's button; no frame waited for" {
  let got = []
  for order in [["上", "下"], ["下", "上"]] {
    let (up, down) = (@signals.signal(false), @signals.signal(false))
    let t = two_layers_tester(up, down, order~)
    let opened = both_opened(t, up, down)
    @signals.start_batch()
    up.set(false)
    down.set(false)
    @signals.end_batch()
    let back = layer_focused(t)
    t.draw()
    got.push((opened, back, layer_focused(t)))
  }
  assert_eq(got, [(Some("上的取消"), Some("树按钮"), Some("树按钮")), (Some("上的取消"), Some("树按钮"), Some("树按钮"))])
}

///|
test "a layer of the tree's giving the focus closed, opened again as it goes (the same node, shown again), closed again: the focus on its 取消 again, at last back on the tree's button" {
  let (up, down) = (@signals.signal(false), @signals.signal(false))
  let t = two_layers_tester(up, down, leave=layer_focus_leave_ms)
  t.act(Button, Focus, label="树按钮")
  up.set(true)
  t.draw()
  let opened = layer_focused(t)
  up.set(false)
  // (halfway out)
  t.run_for(layer_focus_leave_ms / 2.0)
  let going = layer_focused(t)
  up.set(true)
  t.draw()
  let again = layer_focused(t)
  up.set(false)
  t.run_for(layer_focus_leave_ms)
  assert_eq((opened, going, again, layer_focused(t)), (Some("上的取消"), Some("树按钮"), Some("上的取消"), Some("树按钮")))
}

///|
test "the lower of two layers of the tree's opened alone, the focus moved in it to its 确定, the upper opened over it: closed the lower first, then the upper, or both in one change: back on the tree's button; no frame waited for" {
  let got = []
  for together in [false, true] {
    let (up, down) = (@signals.signal(false), @signals.signal(false))
    let t = two_layers_tester(up, down)
    t.act(Button, Focus, label="树按钮")
    down.set(true)
    t.draw()
    t.tab()
    let moved = layer_focused(t)
    up.set(true)
    let opened = layer_focused(t)
    // (between: the lower closed alone, the focus still on the upper's, no frame drawn)
    let mut between = Some("上的取消")
    if together {
      @signals.start_batch()
      down.set(false)
      up.set(false)
      @signals.end_batch()
    } else {
      down.set(false)
      between = layer_focused(t)
      up.set(false)
    }
    let back = layer_focused(t)
    t.draw()
    got.push((moved, opened, between, back, layer_focused(t)))
  }
  let want = (Some("下的确定"), Some("上的取消"), Some("上的取消"), Some("树按钮"), Some("树按钮"))
  assert_eq(got, [want, want])
}

///|
test "an old view's field with the focus and the keyboard, a modal layer of the tree's opened over it: what is typed goes to none of it" {
  let field = Field::new()
  let modal = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=360.0, h=740.0, platform=2)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("example/field", placeholder="输入文字", field~) |> ignore }).grow(Is(1.0)) |> ignore
    root.show(fn() { modal.get() }, fn(v) {
      v.over(Is(true)).modal(Is(true)).presses(Is(true)).ground(Is(0x7F7F7F7FL)) |> ignore
    })
  })
  t.draw()
  t.tap_text("输入文字")
  t.type_text("写到一半")
  modal.set(true)
  t.draw()
  t.type_text("不该进去")
  assert_eq(field.text(), "写到一半")
}

///|
/// A tree's button "树按钮"; a modal layer of the tree's "下" at 4 holding an old view with a stop "下的格" (an old view's
/// stop hosted in it, as a question's field is) while `down`, giving the focus to its own button "下的取消"; over it "上"
/// at 5 giving it to "上的取消" while `up`.
fn hosted_layers_tester(up : @signals.Signal[Bool], down : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="树按钮"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    for name in ["下", "上"] {
      let (on, stack) = if name == "上" { (up, 5) } else { (down, 4) }
      root.show(fn() { on.get() }, fn(v) {
        v.over(Is(true)).stacked(Is(stack)).modal(By(fn() { !v.leaving() })) |> ignore
        let no = v.box(fn(x) {
          x
          .width(Is(Some(80.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .focusable(Is(true))
          .says(Is(Some(@view.said(Button, label=name + "的取消"))))
          .on_press(fn() {  })
          |> ignore
        })
        if name == "下" {
          old(v, fn(c) {
            let id = c.id("下的格")
            c.focusable(id)
            let b = c.box(id~, w=Px(120.0), h=Px(40.0), fn() {  })
            c.semantics(b, Button, id~, label="下的格", actions=[Activate])
          })
          |> ignore
        }
        v.focus_opens(no) |> ignore
      })
    }
  })
  t.draw()
  t
}

///|
test "a stop of an old view hosted in the lower of two layers of the tree's with the focus, the upper opened over it: closed the lower first, then the upper, or both in one change: back on the tree's button; no frame waited for" {
  let got = []
  for together in [false, true] {
    let (up, down) = (@signals.signal(false), @signals.signal(false))
    let t = hosted_layers_tester(up, down)
    t.act(Button, Focus, label="树按钮")
    down.set(true)
    t.draw()
    t.act(Button, Focus, label="下的格")
    let hosted = layer_focused(t)
    up.set(true)
    let opened = layer_focused(t)
    let mut between = Some("上的取消")
    if together {
      @signals.start_batch()
      down.set(false)
      up.set(false)
      @signals.end_batch()
    } else {
      down.set(false)
      between = layer_focused(t)
      up.set(false)
    }
    let back = layer_focused(t)
    t.draw()
    got.push((hosted, opened, between, back, layer_focused(t)))
  }
  let want = (Some("下的格"), Some("上的取消"), Some("上的取消"), Some("树按钮"), Some("树按钮"))
  assert_eq(got, [want, want])
}


///|
/// What a modal layer of the tree's at 2 ("问": closed by Escape, its on_key; told every other key it is asked, in
/// `leaked`) does with the keys while an old view's field hosted in it ("字段", given up by Enter: `submitted`) has the
/// focus; under it an old view the whole window, and while `menu`, an old menu at `menu_at` (not modal: a field's own
/// list, the focus left in the field; `menu_modal`, modal, giving the focus to none of its own), closed by Escape
/// (`menu` set false then). Beside the field in the layer, after it, a node that takes Escape too (`beside`: each it is
/// told): one that does not hold the field.
struct HostedFieldCase {
  open : @signals.Signal[Bool]
  menu : @signals.Signal[Bool]
  field : Field
  leaked : Array[Int]
  submitted : Array[String]
  beside : Ref[Int]
}

///|
fn hosted_field_tester(menu_at : Int, menu_modal? : Bool = false) -> (Tester, HostedFieldCase) {
  let k : HostedFieldCase = {
    open: @signals.signal(true, same=fn(a, b) { a == b }),
    menu: @signals.signal(false, same=fn(a, b) { a == b }),
    field: Field::new(),
    leaked: [],
    submitted: [],
    beside: Ref(0),
  }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        if k.menu.get() {
          c.stacked(menu_at, fn() {
            c.with_dismissed(fn(_) {  }, fn() {
              let o = c.overlay("菜单", modal=menu_modal, initial_focus=if menu_modal { 0 } else { -2 }, outside=false, fn() {
                let b = c.box(w=Px(120.0), h=Px(40.0), top=200.0, bg=0xFF7F7FFFL, fn() {  })
                c.semantics(b, Button, label="菜单")
              })
              if o.dismissed is Some(_) {
                k.menu.set(false)
              }
            })
          })
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { k.open.get() }, fn(v) {
      v
      .over(Is(true))
      .stacked(Is(2))
      .modal(Is(true))
      .presses(Is(true))
      .on_key(fn(key) {
        if key.code == key_escape {
          k.open.set(false)
          true
        } else {
          k.leaked.push(key.code)
          false
        }
      })
      |> ignore
      old(v, fn(c) {
        match c.editor("问/字段", placeholder="字段", field=k.field, enter_sends=true).submitted {
          Some(s) => k.submitted.push(s)
          None => ()
        }
      })
      .height(Is(Some(60.0)))
      |> ignore
      v.box(fn(b) {
        b
        .width(Is(Some(40.0)))
        .height(Is(Some(40.0)))
        .on_key(fn(key) {
          if key.code == key_escape {
            k.beside.val = k.beside.val + 1
            true
          } else {
            false
          }
        })
        |> ignore
      })
      |> ignore
    })
  })
  t.draw()
  t.tap_text("字段")
  t.type_text("写到半")
  (t, k)
}

///|
test "a modal layer of the tree's holding an old view's field with the focus, no menu: its moves and Enter the field's, none told the layer; Escape, which no field takes, the layer's, not what beside the field in it takes Escape too: closed, what was typed kept" {
  let (t, k) = hosted_field_tester(1)
  let typing = t.focused().map(fn(s) { s.role })
  t.key_named("left") |> ignore
  t.type_text("一")
  t.key_named("enter") |> ignore
  let kept = (k.field.text(), k.submitted.copy(), k.leaked.copy(), k.open.get())
  t.key_named("escape") |> ignore
  assert_eq(
    (typing, kept, k.open.get(), k.beside.val, k.field.text()),
    (Some(TextField), ("写到一半", ["写到一半"], [], true), false, 0, "写到一半"),
  )
}

///|
test "a modal layer of the tree's at 2 holding an old view's field with the focus, an old menu at 3 over it: Escape closes the menu alone, the layer open; Escape again, the layer" {
  let (t, k) = hosted_field_tester(3)
  k.menu.set(true)
  t.draw()
  let opened = (k.menu.get(), t.focused().map(fn(s) { s.role }))
  t.key_named("escape") |> ignore
  let first = (k.menu.get(), k.open.get())
  t.key_named("escape") |> ignore
  assert_eq((opened, first, k.open.get()), ((true, Some(TextField)), (false, true), false))
}

///|
test "a modal layer of the tree's at 2 holding an old view's field with the focus, an old menu at 1 under it: Escape closes the layer alone, the menu open" {
  let (t, k) = hosted_field_tester(1)
  k.menu.set(true)
  t.draw()
  t.key_named("escape") |> ignore
  assert_eq((k.open.get(), k.menu.get()), (false, true))
}

///|
test "a modal layer of the tree's at 2 holding an old view's field with the focus, an old modal at 1 under it (the focus left in the field): its moves and Enter the field's still; the old modal open" {
  let (t, k) = hosted_field_tester(1, menu_modal=true)
  k.menu.set(true)
  t.draw()
  let opened = (k.menu.get(), t.focused().map(fn(s) { s.role }))
  t.key_named("left") |> ignore
  t.type_text("一")
  t.key_named("enter") |> ignore
  assert_eq(
    (opened, k.field.text(), k.submitted, k.leaked, k.menu.get(), k.open.get()),
    ((true, Some(TextField)), "写到一半", ["写到一半"], [], true, true),
  )
}

///|
test "a modal layer of the tree's at 2 holding an old view's field with the focus, an old modal at 3 over it: Enter none of the field's, its layer open" {
  let (t, k) = hosted_field_tester(3, menu_modal=true)
  k.menu.set(true)
  t.draw()
  t.key_named("enter") |> ignore
  assert_eq((k.submitted, k.menu.get(), k.open.get()), ([], true, true))
}

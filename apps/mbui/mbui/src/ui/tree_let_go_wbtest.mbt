// Internal drags are handed on in the release event, through layout-only boxes but not through an input target.

///|
fn let_go_at(t : Tester, x : Double, y : Double) -> Unit {
  t.touch(0, 280.0, 180.0)
  t.touch(1, x, y)
  t.touch(2, x, y)
}

///|
test "takes_let_go: nested targets precede the window under layout-only layers" {
  let called : Array[String] = []
  let folder_takes = @signals.signal(true)
  let chat_takes = @signals.signal(true)
  let top = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    takes_let_go(root, fn(_, _) { called.push("window"); true })
    root.box(fn(chat) {
      chat.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(160.0))) |> ignore
      takes_let_go(chat, fn(_, _) { called.push("chat"); chat_takes.get() })
      chat.box(fn(folder) {
        folder.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(60.0))) |> ignore
        takes_let_go(folder, fn(_, _) { called.push("folder"); folder_takes.get() })
      }) |> ignore
    }) |> ignore
    root.show(fn() { top.get() }, fn(other) {
      other.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      takes_let_go(other, fn(_, _) { called.push("top"); true })
    })
    // These draw no controls, but used to make the window taker run before the chat.
    root.box(fn(layout) { layout.over(Is(true)) |> ignore }) |> ignore
  })
  t.draw()
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["folder"])
  called.clear()
  folder_takes.set(false)
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["folder", "chat"])
  called.clear()
  chat_takes.set(false)
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["folder", "chat", "window"])
  called.clear()
  chat_takes.set(true)
  let_go_at(t, 120.0, 100.0)
  assert_eq(called, ["chat"])
  called.clear()
  let_go_at(t, 270.0, 170.0)
  assert_eq(called, ["window"])
  called.clear()
  top.set(true)
  t.draw()
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["top"])
  called.clear()
  top.set(false)
  t.draw()
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["folder", "chat"])
}

///|
test "takes_let_go: a control or modal above another target blocks it" {
  let called : Array[String] = []
  let covering = @signals.signal(false)
  let modal = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    takes_let_go(root, fn(_, _) { called.push("window"); true })
    root.box(fn(chat) {
      chat.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(160.0))) |> ignore
      takes_let_go(chat, fn(_, _) { called.push("chat"); true })
    }) |> ignore
    root.show(fn() { covering.get() }, fn(cover) {
      cover.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))).on_press(fn() { }) |> ignore
    })
    root.show(fn() { modal.get() }, fn(layer) {
      layer.over(Is(true)).modal(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      takes_let_go(layer, fn(_, _) { called.push("modal"); true })
    })
  })
  t.draw()
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["chat"])
  called.clear()
  covering.set(true)
  t.draw()
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["window"])
  called.clear()
  covering.set(false)
  modal.set(true)
  t.draw()
  let_go_at(t, 40.0, 40.0)
  assert_eq(called, ["modal"])
  called.clear()
  let_go_at(t, 150.0, 120.0)
  assert_false(called.contains("chat"))
}

///|
test "takes_let_go: the old island actually taking the point decides" {
  let called : Array[String] = []
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    takes_let_go(root, fn(_, _) { called.push("window"); true })
    root.box(fn(chat) {
      chat.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(160.0))) |> ignore
      takes_let_go(chat, fn(_, _) { called.push("chat"); true })
      old(chat, fn(c) {
        let id = c.id("inside")
        c.clicked(id) |> ignore
        c.box(id~, w=Px(80.0), h=Px(60.0), fn() { }) |> ignore
      }).over(Is(true)) |> old_takes_own |> ignore
    }) |> ignore
    root.box(fn(cover) {
      cover.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      old(cover, fn(c) {
        let id = c.id("outside")
        c.clicked(id) |> ignore
        c.box(id~, w=Px(40.0), h=Px(40.0), fn() { }) |> ignore
      }).over(Is(true)) |> old_takes_own |> ignore
    }) |> ignore
  })
  t.draw()
  t.frame()
  let_go_at(t, 20.0, 20.0)
  assert_eq(called, ["window"])
  called.clear()
  let_go_at(t, 60.0, 30.0)
  assert_eq(called, ["chat"])
  called.clear()
  let_go_at(t, 150.0, 120.0)
  assert_eq(called, ["chat"])
}

///|
test "takes_let_go: a drawn-only cover and a field stay in their chat" {
  let called : Array[String] = []
  let draft = Field::new(text="draft")
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    takes_let_go(root, fn(_, _) { called.push("window"); true })
    root.box(fn(chat) {
      chat.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(160.0))) |> ignore
      takes_let_go(chat, fn(_, _) { called.push("chat"); true })
      chat.box(fn(cover) { cover.over(Is(true)).presses(Is(false)).hides(Is(true)) |> ignore }) |> ignore
      field(chat, draft, placeholder="draft", font_size=10.0) |> ignore
    }) |> ignore
    root.box(fn(layout) { layout.over(Is(true)) |> ignore }) |> ignore
  })
  t.draw()
  let (x, y) = t.find("draft").unwrap()
  t.tap(x, y)
  assert_eq(t.focused().map(fn(s) { s.role }), Some(TextField))
  called.clear()
  t.touch(0, 280.0, 180.0)
  t.touch(1, x, y)
  draft.focus()
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.role }), Some(TextField))
  t.touch(2, x, y)
  assert_eq(called, ["chat"])
  assert_eq(t.focused().map(fn(s) { s.role }), Some(TextField))
  assert_eq(draft.text(), "draft")
}

///|
test "takes_let_go: the target's event-time position is used without a frame" {
  let called : Array[String] = []
  let offset = @signals.signal((0.0, 0.0))
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    takes_let_go(root, fn(_, _) { called.push("window"); true })
    root.box(fn(target) {
      target.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(80.0))).offset(By(fn() { offset.get() })) |> ignore
      takes_let_go(target, fn(_, _) { called.push("target"); true })
    }) |> ignore
  })
  t.draw()
  t.touch(0, 280.0, 180.0)
  offset.set((120.0, 0.0))
  t.touch(1, 150.0, 30.0)
  t.touch(2, 150.0, 30.0)
  assert_eq(called, ["target"])
}

///|
test "let_go_here follows the visible candidates while the pointer rests" {
  let cover = @signals.signal(false)
  let child_shown = @signals.signal(true)
  let state : Array[(Bool, Bool)] = []
  let child : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    takes_let_go(root, fn(_, _) { true })
    root.box(fn(chat) {
      chat.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(150.0))) |> ignore
      takes_let_go(chat, fn(_, _) { true })
      chat.show(fn() { child_shown.get() }, fn(folder) {
        folder.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(60.0))) |> ignore
        child.val = Some(folder)
        takes_let_go(folder, fn(_, _) { true })
      })
      chat.reacts(fn() { (let_go_here(chat), child.val.map(fn(v) { let_go_here(v) }).unwrap_or(false)) },
        fn(now) { state.push(now) })
    }) |> ignore
    root.show(fn() { cover.get() }, fn(box) {
      box.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))).on_press(fn() { }) |> ignore
    })
  })
  t.draw()
  t.move(40.0, 40.0)
  assert_eq(state.last(), Some((true, true)))
  cover.set(true)
  t.draw()
  assert_eq(state.last(), Some((false, false)))
  cover.set(false)
  t.draw()
  assert_eq(state.last(), Some((true, true)))
  child_shown.set(false)
  t.draw()
  assert_eq(state.last(), Some((true, false)))
}

///|
test "let_go old_drop_within respects an old target's clip and what covers its island" {
  let cover_old = @signals.signal(false)
  let cover_new = @signals.signal(false)
  let target = Ref(0)
  let other = Ref(0)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(slot) {
      slot.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      old(slot, fn(c) {
        c.box(w=Px(100.0), h=Px(100.0), radius=30.0, clip=true, fn() {
          let id = c.id("clipped-target")
          target.val = id
          c.interact(id) |> ignore
          c.box(id~, w=Px(100.0), h=Px(100.0), fn() { }) |> ignore
        }) |> ignore
      }).over(Is(true)) |> old_takes_own |> ignore
    }) |> ignore
    root.show(fn() { cover_old.get() }, fn(slot) {
      slot.over(Is(true)).width(Is(Some(70.0))).height(Is(Some(70.0))) |> ignore
      old(slot, fn(c) {
        let id = c.id("covering-old")
        other.val = id
        c.interact(id) |> ignore
        c.box(id~, w=Px(70.0), h=Px(70.0), fn() { }) |> ignore
      }).over(Is(true)) |> old_takes_own |> ignore
    })
    root.show(fn() { cover_new.get() }, fn(box) {
      box.over(Is(true)).width(Is(Some(70.0))).height(Is(Some(70.0))).on_press(fn() { }) |> ignore
    })
  })
  t.draw()
  t.frame()
  assert_true(old_drop_within(50.0, 50.0).contains(target.val))
  assert_false(old_drop_within(1.0, 1.0).contains(target.val))
  cover_old.set(true)
  t.draw()
  assert_true(old_drop_within(50.0, 50.0).contains(other.val))
  assert_false(old_drop_within(50.0, 50.0).contains(target.val))
  cover_old.set(false)
  cover_new.set(true)
  t.draw()
  assert_true(old_drop_within(50.0, 50.0).is_empty())
  cover_new.set(false)
  t.draw()
  assert_true(old_drop_within(50.0, 50.0).contains(target.val))
}

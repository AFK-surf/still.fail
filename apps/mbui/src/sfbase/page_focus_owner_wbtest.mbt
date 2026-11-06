// A window can keep several navigation entries alive, including pages with the same control keys.

///|
test "shell focus follows the same navigation entry and stops when it is left" {
  let shell = @signals.signal(0)
  let active = @signals.signal(2)
  let before = Ref((0, 2))
  let first = Ref(0)
  let second = Ref(0)
  let captured : Ref[Bool?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=800.0, platform=0)
  @ui.set_view_app(fn(root) {
    let owner = page_focus_owner(root)
    root.pick(fn() {
      let next = (shell.get(), active.get())
      let (old_shell, old_entry) = before.val
      if old_entry != next.1 {
        owner.leave(old_entry)
      }
      if old_shell != next.0 && old_entry == next.1 {
        captured.val = Some(owner.replace(next.1))
      }
      before.val = next
      next.0
    }, fn(group, _) {
      for (entry, label) in [(1, "First"), (2, "Second")] {
        group.box(fn(page) {
          page.height(Is(Some(300.0))) |> ignore
          page_focus_entry(page, entry)
          @sf.page_node(page, fn() { label }, fn() { ["one"] }, fn(b, _) {
            b.box(fn(row) {
              row.height(Is(Some(60.0))).words(Is(label))
              .says(Is(Some(@view.said(Button, label~)))) |> ignore
              @sf.presses_node(row, fn() {
                if entry == 1 { first.val += 1 } else { second.val += 1 }
              })
              @sf.page_focus_node(row, "same-key") |> ignore
            }) |> ignore
          }, on_back=fn() {  }, frame=fn() { { ..@sf.no_frame, named: true } }, width=fn() { 700.0 })
        }) |> ignore
      }
    })
  })
  t.draw()
  t.act(Button, Focus, label="Second")
  shell.set(1)
  t.draw()
  assert_eq(captured.val, Some(true))
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Second"))
  t.key(@ui.key_space)
  assert_eq((first.val, second.val), (0, 1))
  @ui.view_tree().unwrap().event(t.time(), fn() {
    active.set(1)
    shell.set(2)
  })
  t.draw()
  assert_true(t.focused() is None)
  shell.set(3)
  t.draw()
  assert_eq(captured.val, Some(false))
}

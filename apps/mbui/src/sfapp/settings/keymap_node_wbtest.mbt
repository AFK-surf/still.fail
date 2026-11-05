// A node's actions of the keymap (keymap.mbt actions_node): done by their keys as the tree asks them of what takes keys,
// none while the 快捷键 page records, one not said for a focused field not by a key that field had, and one chosen from
// the menu bar done there at once.

///|
fn keymap_prefs() -> Json {
  {
    "keymap": {
      "actions": [
        { "action": "chat.latest", "keys": ["Mod+J"] },
        { "action": "composer.focus", "keys": ["Mod+K"] },
        { "action": "chat.find", "keys": ["Mod+F"] },
      ],
    },
  }
}

///|
/// The key `binding` is, pressed (`binding_key`'s), told at `at` and the frame drawn.
fn press(t : @ui.Tester, binding : String, at : Double) -> Unit {
  let (code, mods) = binding_key(binding).unwrap()
  t.key_told(code, mods, at)
  t.draw()
}

///|
test "a node's actions done by their keys at once, none while keys are recorded, one not for a field not from it" {
  keymap_reset()
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=200.0, platform=0)
  let draft = @ui.Field::new(text="draft")
  let done : Array[String] = []
  @ui.set_view_app(fn(root) {
    root.box(fn(page) {
      page.grow(Is(1.0)) |> ignore
      actions_node(page, fn() { Some(keymap_prefs()) }, [
        ("chat.latest", true, fn() { done.push("latest"); true }),
        ("composer.focus", false, fn() { done.push("focus"); true }),
        // (one that cannot now: nothing done, the key not taken)
        ("chat.find", false, fn() { false }),
      ])
      @ui.field(page, draft).width(Is(Some(300.0))).height(Is(Some(22.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  press(t, "Mod+J", 10.0)
  press(t, "Mod+K", 20.0)
  assert_eq(done, ["latest", "focus"])
  // (a key none of them is, or one of an action that cannot now: nothing done)
  press(t, "Mod+L", 30.0)
  press(t, "Mod+F", 35.0)
  assert_eq(done, ["latest", "focus"])
  // (while the 快捷键 page records new keys: none)
  keys_recording.set("chat.latest")
  press(t, "Mod+J", 40.0)
  keys_recording.set("")
  assert_eq(done, ["latest", "focus"])
  // (a field with the focus: what is said for it too done by its keys there, what is not, not)
  draft.focus()
  t.draw()
  press(t, "Mod+J", 50.0)
  press(t, "Mod+K", 60.0)
  assert_eq(done, ["latest", "focus", "latest"])
}

///|
test "an action chosen from the menu bar done by the node that does it, at once; by the old views' frame where none does" {
  keymap_reset()
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=200.0, platform=0)
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let done : Array[String] = []
  @ui.set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(page) {
      actions_node(page, fn() { Some(keymap_prefs()) }, [("chat.latest", false, fn() { done.push("latest"); true })])
    })
  })
  t.draw()
  ask_action("chat.latest")
  assert_eq(done, ["latest"])
  assert_eq(action_asked.val, "")
  // (its node gone: the old views' to read, by the frame after)
  shown.set(false)
  t.draw()
  ask_action("chat.latest")
  assert_eq(done, ["latest"])
  assert_eq(action_asked.val, "chat.latest")
  action_asked_done()
}

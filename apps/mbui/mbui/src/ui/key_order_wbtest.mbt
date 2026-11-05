// The order a key is asked in (view_key): a layer of the old frame's taking the keys first (none under it told); a field
// with the focus, what it takes as its own; then, what is in a layer over the focus's (what was opened over the page: Escape
// to it before the page), what holds the focus, the innermost first, the root (the app's keys, as its keymap says),
// where nothing has the focus the root alone; what none took, the old frame's (key_in).

///|
/// A window whose root says what keys it took (`root_keys`: those it takes, ⌘K); a page holding a field of `f` taking
/// Escape (`page_keys`); over the page, while `opened`, what the shell opened over it (a layer of its own), taking Escape (`shell_keys`);
/// while `modal`, a modal layer of the old frame's.
fn key_order_tester(
  f : Field,
  root_keys : Array[Int],
  page_keys : Array[Int],
  shell_keys : Array[Int],
  opened? : @signals.Signal[Bool] = @signals.signal(false),
  modal? : Ref[Bool] = Ref(false),
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.on_key(fn(k) {
      if k.code == key_of_char('k') && k.mods == mod_cmd {
        root_keys.push(k.code)
        true
      } else {
        false
      }
    })
    |> ignore
    root.box(fn(page) {
      page
      .over(Is(true))
      .width(Is(Some(300.0)))
      .height(Is(Some(40.0)))
      .on_key(fn(k) {
        if k.code == key_escape {
          page_keys.push(k.code)
          true
        } else {
          false
        }
      })
      |> ignore
      field(page, f, font_size=10.0, max_lines=1) |> ignore
    })
    |> ignore
    root.show(fn() { opened.get() }, fn(v) {
      v
      .over(Is(true))
      .stacked(Is(2))
      .offset(Is((0.0, 100.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .on_key(fn(k) {
        if k.code == key_escape {
          shell_keys.push(k.code)
          true
        } else {
          false
        }
      })
      |> ignore
    })
    old(root, fn(c) {
      guard modal.val else { return }
      c.overlay("sheet", modal=true, outside=false, fn() {
        c.box(w=Px(100.0), h=Px(100.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a key its field does not take, ⌘K, the focus in it: on out through what holds it to the root's" {
  let f = Field::new(text="ab")
  let (root_keys, page_keys, shell_keys) = ([], [], [])
  let t = key_order_tester(f, root_keys, page_keys, shell_keys)
  f.focus()
  t.draw()
  t.key(key_of_char('k'), mods=mod_cmd)
  assert_eq((root_keys, f.text()), ([key_of_char('k')], "ab"))
}

///|
test "a key its field takes, the focus in it: the field's alone, none of what holds it told" {
  let f = Field::new(text="ab")
  let (root_keys, page_keys, shell_keys) = ([], [], [])
  let t = key_order_tester(f, root_keys, page_keys, shell_keys)
  f.focus()
  t.draw()
  t.key(key_backspace)
  t.key(key_of_char('z'), mods=mod_cmd)
  assert_eq((root_keys, page_keys, f.text()), ([], [], "ab"))
  t.key(key_backspace)
  assert_eq((root_keys, page_keys, f.text()), ([], [], "a"))
}

///|
test "a modal layer of the old frame's open: a key none of the tree's under it is told" {
  let f = Field::new(text="ab")
  let (root_keys, page_keys, shell_keys) = ([], [], [])
  let modal = Ref(true)
  let t = key_order_tester(f, root_keys, page_keys, shell_keys, modal~)
  t.draw()
  t.key(key_of_char('k'), mods=mod_cmd)
  t.key(key_escape)
  assert_eq((root_keys, page_keys, shell_keys), ([], [], []))
}

///|
test "nothing with the focus: a key the root's, as its keymap says" {
  let f = Field::new(text="ab")
  let (root_keys, page_keys, shell_keys) = ([], [], [])
  let t = key_order_tester(f, root_keys, page_keys, shell_keys)
  t.key(key_of_char('k'), mods=mod_cmd)
  assert_eq((root_keys, page_keys, f.text()), ([key_of_char('k')], [], "ab"))
}

///|
test "Escape, the focus in the page's field: what the shell opened over the page first, the page once that is gone" {
  let f = Field::new(text="ab")
  let (root_keys, page_keys, shell_keys) = ([], [], [])
  let opened = @signals.signal(true)
  let t = key_order_tester(f, root_keys, page_keys, shell_keys, opened~)
  f.focus()
  t.draw()
  t.key(key_escape)
  let first = (shell_keys.copy(), page_keys.copy())
  opened.set(false)
  t.draw()
  t.key(key_escape)
  assert_eq((first, shell_keys, page_keys), (([key_escape], []), [key_escape], [key_escape]))
}

///|
test "a node in the field's own layer drawn over it, taking ⌘K too: the focus in the field, ⌘K not its but the root's" {
  let f = Field::new(text="ab")
  let (root_keys, cover_keys) = ([], [])
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.on_key(fn(k) {
      if k.code == key_of_char('k') && k.mods == mod_cmd {
        root_keys.push(k.code)
        true
      } else {
        false
      }
    })
    |> ignore
    field(root, f, font_size=10.0, max_lines=1).over(Is(true)).width(Is(Some(300.0))) |> ignore
    // (a button over the field, drawn after it in the same layer)
    root.box(fn(b) {
      b
      .over(Is(true))
      .width(Is(Some(40.0)))
      .height(Is(Some(20.0)))
      .on_key(fn(k) {
        if k.code == key_of_char('k') && k.mods == mod_cmd {
          cover_keys.push(k.code)
          true
        } else {
          false
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  f.focus()
  t.draw()
  t.key(key_of_char('k'), mods=mod_cmd)
  assert_eq((cover_keys, root_keys), ([], [key_of_char('k')]))
}

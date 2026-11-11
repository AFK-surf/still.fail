// Tab and Shift+Tab with the focus in a field of the window's tree, as any key: first what the keymap binds them to
// from where the focus is (view_key), the action that takes it having it; the focus moved, as ever, where none does or
// none is bound.

///|
/// A row of a button "A", a field of `f` (read out "字") in a box of the context "Offers" that does `take` for Tab and
/// `back` for Shift+Tab (counting each time it is asked in `asked`: what they answer, whether they take it), a button
/// "B"; Tab bound to `take` and Shift+Tab to `back` in that context where `bound`. The field focused.
fn tab_tester(f : Field, takes : Bool, bound : Bool, asked : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=100.0)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    if bound {
      root
      .keymap(
        Is(
          @view.Keymap::new([
            { keys: [{ code: key_tab, mods: 0 }], action: "offers.take", when: @view.KeyWhen::In("Offers") },
            { keys: [{ code: key_tab, mods: mod_shift_key }], action: "offers.back", when: @view.KeyWhen::In("Offers") },
          ]),
        ),
      )
      |> ignore
    }
    let button = fn(name : String) {
      root.box(fn(b) {
        b
        .width(Is(Some(60.0)))
        .height(Is(Some(30.0)))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label=name))))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
    }
    button("A")
    root.box(fn(h) {
      h
      .width(Is(Some(200.0)))
      .key_context("Offers")
      .on_action("offers.take", fn(_) {
        asked.val = asked.val + 1
        takes
      })
      .on_action("offers.back", fn(_) {
        asked.val = asked.val + 1
        takes
      })
      |> ignore
      field(h, f, label="字", font_size=10.0, max_lines=1) |> ignore
    })
    |> ignore
    button("B")
  })
  t.draw()
  t.tap(160.0, 5.0)
  t.frame()
  t
}

///|
/// Where the focus is after Tab (or Shift+Tab where `back`) from the field, and how many times an action was asked:
/// with an action bound that takes it (`takes`) or not, or none bound.
fn tab_from_field(takes : Bool, bound : Bool, back : Bool) -> (String, Int) raise {
  let asked = Ref(0)
  let t = tab_tester(Field::new(text="ab"), takes, bound, asked)
  assert_true(t.focus_said().has_prefix("TextField \"字\""), msg=t.focus_said())
  t.tab(back~)
  t.frame()
  let said = t.focus_said()
  let at = match said.find(" at ") {
    Some(i) => said.exact_view(end=i).to_owned()
    None => said
  }
  (at, asked.val)
}

///|
test "Tab in a field of the tree's, an action of the focus's chain bound to it that takes it: its, once; the focus stays in the field" {
  assert_eq(tab_from_field(true, true, false), ("TextField \"字\"", 1))
}

///|
test "Tab in a field of the tree's, an action bound to it that does not take it: the focus moves on to the next, as with none bound" {
  assert_eq(tab_from_field(false, true, false), ("Button \"B\"", 1))
  assert_eq(tab_from_field(false, false, false), ("Button \"B\"", 0))
}

///|
test "Shift+Tab in a field of the tree's: an action bound to it that takes it, its, the focus kept; one that does not, or none bound, the focus back to the one before" {
  assert_eq(tab_from_field(true, true, true), ("TextField \"字\"", 1))
  assert_eq(tab_from_field(false, true, true), ("Button \"A\"", 1))
  assert_eq(tab_from_field(false, false, true), ("Button \"A\"", 0))
}

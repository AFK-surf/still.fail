// A dropdown menu's item chosen by a pointer, what was chosen opening a modal layer (the window's tree's, or the old
// frame's own) whose field is given the focus once as it opens: once all of it has come and gone the focus is in that
// field, what is typed goes into it. The menu closing gives the focus back to what had it as it opened (the page's
// field) only where it is still in the menu or nowhere: the pointer resting on the item it chose does not take it
// back into the menu as the menu goes.

///|
/// The page's field "Page field" with the focus, a button "Menu" opening the dropdown "m" of one item "New"; "New"
/// chosen, the layer (the tree's where `tree_layer`, else the old frame's) opened, its field "Layer field" given the
/// focus once. What is typed into the layer's field, and the Tester.
fn dropdown_then_layer(tree_layer : Bool) -> (@ui.Tester, @ui.Field) {
  let open = Ref(false)
  let layer = @signals.signal(false)
  let page = @ui.Field::new()
  let inner = @ui.Field::new()
  let asked = Ref(false)
  let page_view = fn(c : @ui.Ctx) {
      c.editor("page", placeholder="Page field", field=page) |> ignore
      let trigger = c.id("menu")
      if @kit.button(c, "Menu", key="menu").clicked {
        open.val = true
      }
      let m = @kit.dropdown_menu(c, "m", open.val, trigger, [@kit.menu_item("new", label="New")])
      open.val = m.open
      if m.chosen == Some("new") {
        open.val = false
        layer.set(true)
      }
      if !tree_layer && layer.get() {
        c.overlay("layer", modal=true, initial_focus=0, fn() {
          c.box(top=150.0, left=0.0, w=Px(200.0), fn() {
            c.editor("inner", placeholder="Layer field", field=inner) |> ignore
          })
          |> ignore
          if !asked.val {
            asked.val = true
            c.focus_editor("inner")
          }
        })
        |> ignore
      }
    }
  let t = @ui.Tester::new(fn(_c) {  }, platform=0)
  t.check_looks(false)
  @ui.set_view_app(
    fn(root) {
      root.box(fn(h) {
        h.grow(Is(1.0)) |> ignore
        @ui.old(h, page_view).grow(Is(1.0)) |> ignore
      })
      |> ignore
      if tree_layer {
        root.show(fn() { layer.get() }, fn(l) {
          l.over(Is(true)).stacked(Is(3)).modal(Is(true)) |> ignore
          l.box(fn(gap) { gap.height(Is(Some(150.0))) |> ignore }) |> ignore
          l.box(fn(b) {
            b.width(Is(Some(200.0))) |> ignore
            l.focus_opens(@ui.field(b, inner, placeholder="Layer field")) |> ignore
          })
          |> ignore
        })
      }
    },
  )
  t.draw()
  match t.find("Page field") {
    Some((x, y)) => t.tap(x, y)
    None => ()
  }
  t.draw()
  (t, inner)
}

///|
/// `words` tapped where they are; the test fails where they are not, saying what is.
fn tap_said(t : @ui.Tester, words : String) -> Unit raise {
  match t.find(words) {
    Some((x, y)) => t.tap(x, y)
    None => fail("no \{words}: \{t.words().map(fn(w) { w.0 }).join("|")}; focus \{t.focus_said()}")
  }
}

///|
/// The menu opened by a click on "Menu", its "New" clicked, all of it run on to where it has come and gone; where the
/// focus is then, and the layer's field's words once "typed" is typed.
fn dropdown_chosen(t : @ui.Tester, inner : @ui.Field) -> (String?, String?, String) raise {
  let first = t.focused().map(fn(s) { s.label })
  tap_said(t, "Menu")
  t.draw()
  t.run_for(dropdown_layer_ms)
  tap_said(t, "New")
  t.draw()
  t.run_for(dropdown_layer_ms)
  let after = t.focused().map(fn(s) { s.label })
  t.type_text("typed")
  t.draw()
  (first, after, inner.text())
}

///|
/// How long a menu's way in or out, and a layer's, are run on for (pop_in's, pop_out's and more).
let dropdown_layer_ms : Double = 400.0

///|
test "a dropdown's item chosen by a pointer opening a modal layer of the tree's, its field given the focus as it opens: the focus in that field once the menu has gone, typing goes in it" {
  let (t, inner) = dropdown_then_layer(true)
  assert_eq(dropdown_chosen(t, inner), (Some("Page field"), Some("Layer field"), "typed"))
}

///|
test "a dropdown's item chosen by a pointer opening a modal layer of the old frame's, its field given the focus once: the focus in that field once the menu has gone, typing goes in it" {
  let (t, inner) = dropdown_then_layer(false)
  assert_eq(dropdown_chosen(t, inner), (Some("Page field"), Some("Layer field"), "typed"))
}

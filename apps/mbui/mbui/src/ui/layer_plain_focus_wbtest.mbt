// A field of an old view and a modal layer of the tree's that gives no focus (a viewer's: View::modal alone, no
// View::focus_opens). The field holding the focus as the layer opens over it: its input method put away while the layer
// is over it (Ctx::sync_ime, by what may be typed into: Ctx::typing_allowed), its focus kept for it, the field's
// again as the layer goes. The field asking for the focus once the layer is open (a page first drawn under it): not
// given it (Ctx::focus_editor), none of it kept for after.

///|
/// An old view the whole window with a field "页字段", asking for the focus once as it is built while `ask`; while
/// `open`, a modal layer of the tree's over it giving no focus, holding a box (`leaves`: one that leaves what is typed to
/// the field under it, a menu a finger opened beside it: View::leaves_typing).
fn plain_modal_tester(open : @signals.Signal[Bool], ask : @signals.Signal[Bool], leaves? : Bool = false) -> Tester {
  let asked = Ref(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        c.editor("页/字段", placeholder="页字段") |> ignore
        if ask.get() {
          if !asked.val {
            asked.val = true
            c.focus_editor("页/字段")
          }
        } else {
          asked.val = false
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)).modal(Is(true)).presses(Is(true)) |> ignore
      if leaves {
        l.leaves_typing() |> ignore
      }
      l.box(fn(x) { x.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
    })
  })
  t
}

///|
test "a field of an old view with the focus, a modal layer of the tree's giving no focus opened over it: its input method put away while the layer is over it; the layer gone, the field's again, its input method with it" {
  let (open, ask) = (@signals.signal(false), @signals.signal(true))
  let t = plain_modal_tester(open, ask)
  t.draw()
  t.draw()
  assert_true(t.ime().0, msg="the field's, the layer not open: \{t.ime()}")
  open.set(true)
  t.draw()
  assert_true(!t.ime().0, msg="its input method put away under the layer: \{t.ime()}")
  open.set(false)
  t.draw()
  assert_true(t.ime().0, msg="the layer gone: the field's again: \{t.ime()}")
}

///|
test "a modal layer of the tree's giving no focus open, a field of an old view under it asking for the focus as it is built: not given it, its input method none; the layer gone, nothing of it kept for the field" {
  let (open, ask) = (@signals.signal(true), @signals.signal(false))
  let t = plain_modal_tester(open, ask)
  t.draw()
  ask.set(true)
  t.draw()
  t.draw()
  let under = t.ime()
  open.set(false)
  t.draw()
  t.draw()
  // (what it was told under the layer, and once it is gone: the field given no focus, none kept for it)
  assert_eq((under.0, t.ime().0), (false, false), msg="under it \{under}, gone \{t.ime()}")
}

///|
test "a field of an old view with the focus, a modal layer of the tree's opened over it that leaves what is typed to it: its input method kept while the layer is over it, what is typed the field's" {
  let (open, ask) = (@signals.signal(false), @signals.signal(true))
  let t = plain_modal_tester(open, ask, leaves=true)
  t.draw()
  t.draw()
  open.set(true)
  t.draw()
  assert_true(t.ime().0, msg="its input method kept under the layer: \{t.ime()}")
  t.type_text("ab")
  t.draw()
  assert_eq(t.ime().1, "ab", msg="what is typed the field's")
}

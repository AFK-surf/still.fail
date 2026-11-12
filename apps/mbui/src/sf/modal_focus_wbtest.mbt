// A modal layer open over a field with the keyboard's focus: the focus is not left under it. Its keys are the topmost
// layer's (Escape closes it), what is typed goes into nothing under it, the field's input method is put away; as it goes,
// the focus, the input method and what is typed are the field's again, what was written in it still there. The same
// the four ways (the field an old view's or a node's, the layer an old panel or one of nodes), on 小屏 with a keyboard
// and mouse and with a finger. A layer that is not modal (a list beside a field) leaves the field its focus and keys.

///|
/// A page holding one field ("页面输入框", an old view's `old_field`, else a node's), what is presented over it, at the
/// window of `at`; what is written in the field in `f`.
fn field_page_tester(at : (Int, Double, Double), old_field : Bool, f : @ui.Field) -> @ui.Tester {
  presenters_reset()
  let (platform, w, h) = at
  let tree = fn(root : @view.View) {
    @ui.set_tree_theme(ui_theme_now)
    if old_field {
      @ui.old(root, fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), pad=40.0, fn() {
            c.editor("page", placeholder="页面输入框", field=f) |> ignore
          })
          |> ignore
          presented(c)
        })
      }).grow(Is(1.0))
      |> ignore
    } else {
      root.box(fn(b) {
        b.grow(Is(1.0)).pad(Is(40.0)) |> ignore
        input_node(b, f, placeholder="页面输入框", label="页面输入框") |> ignore
      })
      |> ignore
      // (the old presenters' own layer: what the shell keeps as an old view)
      @ui.old(root, fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() { presented(c) })
      }).over(Is(true))
      |> ignore
    }
    presented_nodes(root)
  }
  let t = @ui.Tester::new(@ui.old_views_here, tree~, w~, h~, platform~)
  t.draw()
  t.draw()
  t
}

///|
/// The field pressed and given the focus.
fn focus_page_field(t : @ui.Tester, at : String) -> Unit raise {
  t.act(@ui.Role::TextField, Focus, label="页面输入框")
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("页面输入框"), msg="\{at}: the page's field focused: \{Repr(t.focused().map(fn(s) { (s.role, s.label) }))}")
}

///|
/// A panel "盖住" (`nodes`: of nodes) opened over the page with the focus where it is, as a key or a shortcut opens one.
fn open_over(t : @ui.Tester, nodes : Bool) -> Unit {
  if nodes {
    panel_nodes("盖住", fn(v, _) { words_node(v, fn() { "盖住的字" }, fn() { desk_muted }) |> ignore }, from=Unanchored)
  } else {
    panel("盖住", fn(c, _) { c.text("盖住的字") |> ignore }, from=Unanchored)
  }
  t.frame()
  come_to_rest(t)
}

///|
let modal_focus_ways : Array[(Bool, Bool, String)] = [
  (true, false, "old panel over an old field"),
  (true, true, "panel of nodes over an old field"),
  (false, false, "old panel over a node field"),
  (false, true, "panel of nodes over a node field"),
]

///|
test "a modal layer over a field with the focus: its keys, nothing typed under it, the input method away; closed, all the field's again, the four ways" {
  // (each way on its own: what fails in each said, all of them)
  let failed : Array[String] = []
  for at in [(0, 390.0, 844.0), phone] {
    for way in modal_focus_ways {
      let (old_field, nodes, name) = way
      let msg = "\{name}, platform \{at.0}"
      try modal_focus_way(at, old_field, nodes, msg) catch {
        e => failed.push(e.to_string())
      }
    }
  }
  assert_true(failed.is_empty(), msg=failed.join("\n"))
}

///|
/// One way of modal_focus_ways at the window of `at`: the field focused and written in, the layer opened over it,
/// typed, Escape, typed again.
fn modal_focus_way(at : (Int, Double, Double), old_field : Bool, nodes : Bool, msg : String) -> Unit raise {
  let f = @ui.Field::new()
  let t = field_page_tester(at, old_field, f)
  focus_page_field(t, msg)
  t.type_text("写")
  t.draw()
  assert_eq(f.text(), "写", msg~)
  assert_true(t.ime().0, msg="\{msg}: the host told of the field")
  open_over(t, nodes)
  assert_true(t.find("盖住的字") is Some(_), msg="\{msg}: open")
  // (up: not the field's focus, nor what is typed, nor its input method)
  assert_false(t.focused().map(fn(s) { s.label }) == Some("页面输入框"), msg="\{msg}: focus under it")
  assert_false(t.ime().0, msg="\{msg}: the input method up under it: \{Repr(t.ime())}")
  t.type_text("下")
  t.draw()
  assert_eq(f.text(), "写", msg="\{msg}: typed under it")
  // (Escape the layer's: closed)
  t.press("Escape")
  t.draw()
  come_to_rest(t)
  assert_true(t.find("盖住的字") is None, msg="\{msg}: Escape closes it")
  // (gone: the focus, its input method and what is typed the field's again, what was in it still)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("页面输入框"), msg="\{msg}: focus back")
  assert_true(t.ime().0, msg="\{msg}: the input method back: \{Repr(t.ime())}")
  t.type_text("回")
  t.draw()
  assert_eq(f.text(), "写回", msg~)
}

///|
test "a layer that is not modal beside a field with the focus: the focus, what is typed and its keys the field's still" {
  for at in [(0, 390.0, 844.0), phone] {
    for old_field in [true, false] {
      let msg = "old field \{old_field}, platform \{at.0}"
      let f = @ui.Field::new()
      let shown = @signals.signal(false)
      presenters_reset()
      let (platform, w, h) = at
      let tree = fn(root : @view.View) {
        @ui.set_tree_theme(ui_theme_now)
        if old_field {
          @ui.old(root, fn(c) {
            begin(c) |> ignore
            c.with_theme(ui_theme(), fn() {
              c.box(w=Fill(1.0), h=Fill(1.0), pad=40.0, fn() {
                c.editor("page", placeholder="页面输入框", field=f) |> ignore
              })
              |> ignore
            })
          }).grow(Is(1.0))
          |> ignore
        } else {
          root.box(fn(b) {
            b.grow(Is(1.0)).pad(Is(40.0)) |> ignore
            input_node(b, f, placeholder="页面输入框", label="页面输入框") |> ignore
          })
          |> ignore
        }
        // (a list beside it, over the page, not modal: a field's suggestions)
        root.show(fn() { shown.get() }, fn(l) {
          l.over(Is(true)).modal(Is(false)).width(Is(Some(200.0))).height(Is(Some(80.0))) |> ignore
          words_node(l, fn() { "候选" }, fn() { desk_muted }) |> ignore
        })
      }
      let t = @ui.Tester::new(@ui.old_views_here, tree~, w~, h~, platform~)
      t.draw()
      t.draw()
      focus_page_field(t, msg)
      shown.set(true)
      t.draw()
      assert_true(t.find("候选") is Some(_), msg~)
      assert_eq(t.focused().map(fn(s) { s.label }), Some("页面输入框"), msg="\{msg}: focus kept")
      assert_true(t.ime().0, msg="\{msg}: input method kept")
      t.type_text("字")
      t.key_named("left") |> ignore
      t.type_text("一")
      t.draw()
      assert_eq(f.text(), "一字", msg="\{msg}: typed and its keys the field's")
    }
  }
}

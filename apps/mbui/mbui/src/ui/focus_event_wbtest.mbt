// A field given the keyboard by an event must receive the next input even when no frame separates the two events.

///|
test "a key gives an already drawn field the host's input method at that event, for retained and old fields" {
  for legacy in [false, true] {
    let f = Field::new()
    let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
    set_view_app(fn(root) {
      root.on_key(fn(key) {
        if key.code != key_space { return false }
        g().focus_field(f)
        true
      }) |> ignore
      root.box(fn(slot) {
        slot.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(30.0))) |> ignore
        if legacy {
          old(slot, fn(c) {
            c.box(w=Px(200.0), h=Px(30.0), fn() {
              c.editor("words", field=f, font_size=12.0, max_lines=1, plain=true) |> ignore
            }) |> ignore
          }) |> ignore
        } else {
          field(slot, f, font_size=12.0, max_lines=1) |> ignore
        }
      }) |> ignore
    })
    t.draw()
    assert_false(t.ime().0)
    let at = t.time()
    t.key_told(key_space, 0, at)
    assert_true(t.ime().0, msg="input method at the key's moment, old field: \{legacy}")
    t.text_told("ab", at)
    assert_eq(f.text(), "ab", msg="old field: \{legacy}")
    // The next input method may compose and commit before a frame too.
    on_text(1, "ni", 2, 0)
    assert_eq(f.st.marked, "ni", msg="composing, old field: \{legacy}")
    on_text(0, "你", 0, 0)
    assert_eq(f.text(), "ab你", msg="committed, old field: \{legacy}")
  }
}

///|
test "a request for a present field only does not take focus later when that field appears" {
  let shown = @signals.signal(false, same=fn(a, b) { a == b })
  let f = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.on_key(fn(key) {
      if key.code != key_space { return false }
      g().focus_field(f, ask_later=false)
      true
    }) |> ignore
    root.show(fn() { shown.get() }, fn(slot) {
      slot.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(slot, f, font_size=12.0, max_lines=1) |> ignore
    })
  })
  t.draw()
  t.key_told(key_space, 0, t.time())
  shown.set(true)
  t.draw()
  assert_false(t.ime().0)
  assert_eq(g().focused_id(), 0)
}

///|
test "a modal opened and closed by events tells the host whether the focused field takes typing before another frame" {
  for legacy in [false, true] {
    let shown = @signals.signal(false)
    let f = Field::new()
    let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
    set_view_app(fn(root) {
      root.box(fn(slot) {
        slot.width(Is(Some(200.0))).height(Is(Some(30.0))) |> ignore
        if legacy {
          old(slot, fn(c) {
            c.box(w=Px(200.0), h=Px(30.0), fn() {
              c.editor("modal/field", field=f, placeholder="field", font_size=12.0, max_lines=1, plain=true) |> ignore
            }) |> ignore
          }) |> ignore
        } else {
          field(slot, f, placeholder="field") |> ignore
        }
      }) |> ignore
      root.show(fn() { shown.get() }, fn(layer) {
        layer.over(Is(true)).stacked(Is(2)).modal(Is(true)).focus_returns() |> ignore
      })
    })
    t.draw()
    host_event(fn() { g().focus_field(f) })
    assert_true(t.ime().0, msg="focused field, old: \{legacy}")
    host_event(fn() { shown.set(true) })
    assert_false(t.ime().0, msg="under modal, old: \{legacy}")
    host_event(fn() { shown.set(false) })
    assert_true(t.ime().0, msg="modal closed, old: \{legacy}")
    t.text_told("ab", t.time())
    assert_eq(f.text(), "ab", msg="modal closed, old: \{legacy}")
  }
}

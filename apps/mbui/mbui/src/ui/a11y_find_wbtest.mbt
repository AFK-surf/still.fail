// A test finds what a screen reader finds by its role and name and the rest of Find (Tester::all): part of its name, its
// state, what one holds; it asserts what the host's accessibility was told (Tester::a11y_dump); and what can be done
// and has no name is found (sem_unnamed).

///|
/// Two groups, 甲 and 乙, each a button named 保存 and a checkbox named 提醒 (甲's checked), and a button named as
/// `last` says, pressed doing nothing; read out where `reads` says.
fn find_tester(last : String, reads? : Bool = true) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.set_a11y(reads)
  set_view_app(fn(root) {
    let part = fn(v : @view.View, name : String, on : Bool) {
      v.says(Is(Some(@view.said(Group, label=name)))) |> ignore
      v.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .on_press(fn() {  })
        .says(Is(Some(@view.said(Button, label="保存"))))
        |> ignore
      })
      |> ignore
      v.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .on_press(fn() {  })
        .says(Is(Some(@view.said(Checkbox, label="提醒", check=if on { On } else { Off }))))
        |> ignore
      })
      |> ignore
    }
    root.box(fn(v) { part(v, "甲", true) }) |> ignore
    root.box(fn(v) { part(v, "乙", false) }) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() {  })
      .says(Is(Some(@view.said(Button, label=last))))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "found by part of its name, by its state, within what holds it" {
  let t = find_tester("全部保存")
  assert_eq(t.all(Button, has="保存").length(), 3)
  assert_eq(t.all(Button, label="保存").length(), 2)
  assert_eq(t.get(Checkbox, checked=On).rect, t.get(Checkbox, within=t.get(Group, label="甲")).rect)
  let b = t.get(Button, label="保存", within=t.get(Group, label="乙"))
  assert_true(b.rect != t.get(Button, label="保存", within=t.get(Group, label="甲")).rect)
  assert_true(t.query(Checkbox, checked=Mixed) is None)
}

///|
test "what the host's accessibility was told, as a screen reader finds it" {
  let t = find_tester("全部保存")
  assert_eq(
    t.a11y_dump(),
    (
      #|Group "甲"
      #|  Button "保存"
      #|  Checkbox "提醒" checked
      #|Group "乙"
      #|  Button "保存"
      #|  Checkbox "提醒" unchecked
      #|Button "全部保存"
      #|
    ),
  )
}

///|
test "what can be done and has no name is found; one named is not" {
  let t = find_tester("", reads=false)
  let bad = g().semantics_tree().filter(sem_unnamed)
  assert_eq(bad.map(fn(s) { s.role }), [Button])
  ignore(t)
}

// The indexed source's snapshot and its layout reads are views of the same current ChatRows.

///|
fn sized_test_rows(messages : Json) -> @sfbase.ChatRows {
  let value : Json = { "messages": messages }
  let ms = @sfbase.ChatMessages::of_value(Some(value))
  @sfbase.ChatRows::new(ms, fn(m) { "m:" + m.ts })
}

///|
test "the indexed source reads its snapshot and keys from the same current chat rows" {
  let first = sized_test_rows([
    { "seq": 1, "ts": "first", "text": "a" },
    { "seq": 2, "ts": "second", "text": "b" },
  ])
  let second = sized_test_rows([
    { "seq": 4, "ts": "new", "text": "c" },
  ])
  let rows = @signals.signal(first, same=fn(a, b) { physical_equal(a, b) })
  let out : Ref[@ui.NodeRowsIndexed[Entry]?] = Ref(None)
  let t = @ui.Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  @ui.set_view_app(fn(root) {
    let sized = rows_sized(@ui.ListRows::new(), root, fn() { rows.get() },
      watched=fn() { false }, ms=fn(_) { None }, from=fn(_) { None },
      comes=fn(_) { false }, middle=fn(_) { false }, grown=fn(_) { false },
      lead=fn(_, _) { 0.0 }, lead_in_layout=fn(_, _) { fn() { 0.0 } }, own=fn(_) { false })
    out.val = Some(sized)
  })
  t.draw()
  let sized = out.val.unwrap()
  let source = sized.source
  assert_eq((source.snapshot)().1, first.snapshot().1)
  assert_eq((source.key)(1), first.key(1))
  rows.set(second)
  t.draw()
  let key = second.key(1)
  assert_eq((source.snapshot)().1, second.snapshot().1)
  assert_eq((source.key)(1), key)
  assert_eq((source.find)(key, 1), Some(1))
  assert_true((source.contains)(key))
  assert_true((sized.item_of)(key) is Some(_))
}

///|
test "the captured rows can be laid out, then replaced, without reading signals in layout" {
  let first = sized_test_rows([
    { "seq": 1, "ts": "first", "text": "a" },
    { "seq": 2, "ts": "second", "text": "b" },
  ])
  let second = sized_test_rows([
    { "seq": 4, "ts": "new", "text": "c" },
  ])
  let rows = @signals.signal(first, same=fn(a, b) { physical_equal(a, b) })
  let made : Array[String] = []
  let t = @ui.Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  @ui.set_view_app(fn(root) {
    let sized = rows_sized(@ui.ListRows::new(), root, fn() { rows.get() },
      watched=fn() { false }, ms=fn(_) { None }, from=fn(_) { None },
      comes=fn(_) { false }, middle=fn(_) { false }, grown=fn(_) { false },
      lead=fn(_, _) { 0.0 }, lead_in_layout=fn(_, _) { fn() { 0.0 } }, own=fn(_) { false })
    root.scrolls_anchored(@view.Scroll::list(), fn() { [] }, indexed=sized.source, ahead=0.0, fn(row, key) {
      made.push(key)
      row.height(Is(Some(24.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(made.contains("m:first"), msg="the first snapshot was laid out: \{made}")
  rows.set(second)
  t.draw()
  assert_true(made.contains("m:new"), msg="the replacement snapshot was laid out: \{made}")
}

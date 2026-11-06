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

///|
test "a row far from the end asked for again by its key is found where it was, not past every row after it" {
  let messages : Array[Json] = []
  for i in 0..<3000 {
    messages.push({ "seq": (i + 1).to_double(), "ts": "t\{i}", "text": "x" })
  }
  let rows = sized_test_rows(Json::array(messages))
  let out : Ref[@ui.NodeRowsIndexed[Entry]?] = Ref(None)
  let t = @ui.Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  @ui.set_view_app(fn(root) {
    let sized = rows_sized(@ui.ListRows::new(), root, fn() { rows },
      watched=fn() { false }, ms=fn(_) { None }, from=fn(_) { None },
      comes=fn(_) { false }, middle=fn(_) { false }, grown=fn(_) { false },
      lead=fn(_, _) { 0.0 }, lead_in_layout=fn(_, _) { fn() { 0.0 } }, own=fn(_) { false })
    out.val = Some(sized)
  })
  t.draw()
  let sized = out.val.unwrap()
  let key = rows.key(5)
  assert_true((sized.item_of)(key) is Some((_, 5)))
  // (asked again, as each event and frame that reads it asks: a few rows looked at each time, not the 2,994 after it)
  let was = rows.work()
  for _ in 0..<10 {
    assert_true((sized.item_of)(key) is Some((_, 5)))
  }
  let looked = rows.work() - was
  assert_true(looked <= 100, msg="rows looked at for 10 asks: \{looked}")
}

///|
/// Rows of `n` messages, seqs 1 to n, ts `t<i>`, as many as `drop` taken out of every so many and `swap` pairs swapped.
fn far_test_messages(n : Int, drop? : Int = 0, swap? : Bool = false) -> Json {
  let out : Array[Json] = []
  for i in 0..<n {
    if drop > 0 && i % drop == 0 {
      continue
    }
    out.push({ "seq": (i + 1).to_double(), "ts": "t\{i}", "text": "x" })
  }
  if swap {
    // (two messages' places traded: the order the core says, keys moved)
    let a = out[10]
    out[10] = out[n / 2]
    out[n / 2] = a
  }
  Json::array(out)
}

///|
/// The rows sized over `rows`, made in a tester's app.
fn far_test_sized(rows : @signals.Signal[@sfbase.ChatRows]) -> (@ui.Tester, @ui.NodeRowsIndexed[Entry]) {
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
  (t, out.val.unwrap())
}

///|
test "rows read for the first time one after another from far up are each found beside the one before, not past every row after it" {
  let rows = sized_test_rows(far_test_messages(3000))
  let (_, sized) = far_test_sized(@signals.signal(rows, same=fn(a, b) { physical_equal(a, b) }))
  // (the first, far up: looked for once from the end)
  assert_true((sized.item_of)(rows.key(2000)) is Some((_, 2000)))
  let was = rows.work()
  // (a list scrolled to older rows: each one before the one read last, read for the first time)
  for i = 1999; i >= 1000; i = i - 1 {
    assert_true((sized.item_of)(rows.key(i)) is Some((_, j)) && j == i)
  }
  let looked = rows.work() - was
  assert_true(looked <= 10 * 1000, msg="rows looked at for 1,000 rows read first: \{looked}")
}

///|
test "a row read again after the rows are made anew with messages taken out, moved and put back is found where it is now" {
  let first = sized_test_rows(far_test_messages(600))
  let rows = @signals.signal(first, same=fn(a, b) { physical_equal(a, b) })
  let (t, sized) = far_test_sized(rows)
  for i in [5, 300, 590] {
    ignore((sized.item_of)(first.key(i)))
  }
  // (taken out, then moved, then those taken out back in: rows gone, moved and come)
  for next in [
    sized_test_rows(far_test_messages(600, drop=7)),
    sized_test_rows(far_test_messages(600, swap=true)),
    sized_test_rows(far_test_messages(600)),
  ] {
    rows.set(next)
    t.draw()
    // (each key where a look at every row finds it, or none where it is gone)
    for i in 0..<first.length() {
      let k = first.key(i)
      let mut want : Int? = None
      for j in 0..<next.length() {
        if next.key(j) == k {
          want = Some(j)
          break
        }
      }
      let got = (sized.item_of)(k).map(fn(x) { x.1 })
      assert_eq(got, want, msg="\{k}")
    }
  }
}

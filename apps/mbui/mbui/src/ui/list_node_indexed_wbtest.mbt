///|
/// Rows read by position (ListRows::in_node_indexed's source), each read of a row counted.
priv struct IndexedRows {
  keys : Array[String]
  at : Map[String, Int]
  rev : @signals.Signal[Int]
  gone : Array[(Int, String)]
  pending : Array[RowsChange[(String, Double)]]
  reads : Ref[Int]
}

///|
fn IndexedRows::new(n : Int) -> IndexedRows {
  let keys = Array::makei(n, fn(i) { "m\{i}" })
  let at : Map[String, Int] = {}
  for i, k in keys {
    at[k] = i
  }
  { keys, at, rev: @signals.signal(0), gone: [], pending: [Whole], reads: Ref(0) }
}

///|
fn IndexedRows::source(self : IndexedRows) -> @view.AnchoredSource[String] {
  {
    snapshot: fn() { (self.rev.get(), self.keys.length()) },
    key: fn(i) { self.reads.val += 1; self.keys[i] },
    // (found by its key alone: what a store keeps by key, not looked for among the rest)
    find: fn(k, _) { self.reads.val += 1; self.at.get(k) },
    removed_since: fn(rev) {
      Some(self.gone.filter(fn(g) { g.0 > rev }).map(fn(g) { g.1 }))
    },
    contains: fn(k) { self.at.contains(k) },
  }
}

///|
fn IndexedRows::item(self : IndexedRows, i : Int) -> (String, Double) {
  self.reads.val += 1
  (self.keys[i], 60.0)
}

///|
fn IndexedRows::came(self : IndexedRows, k : String) -> Unit {
  self.at[k] = self.keys.length()
  self.keys.push(k)
  self.pending.push(Came(k))
  self.rev.set(self.rev.get() + 1)
}

///|
fn IndexedRows::went(self : IndexedRows, i : Int) -> Unit {
  let k = self.keys[i]
  let after = if i > 0 { Some(self.keys[i - 1]) } else { None }
  self.keys.remove(i) |> ignore
  self.at.remove(k)
  for j in i..<self.keys.length() {
    self.at[self.keys[j]] = j
  }
  self.gone.push((self.rev.get() + 1, k))
  self.pending.push(Went(k, (k, 60.0), after))
  self.rev.set(self.rev.get() + 1)
}

///|
fn indexed_list(n : Int) -> (Tester, IndexedRows, NodeRowsIndexed[(String, Double)]) {
  let src = IndexedRows::new(n)
  let out : Ref[NodeRowsIndexed[(String, Double)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node_indexed(root, src.source(), fn(i) { src.item(i) }, fn() {
      let all = src.pending.copy()
      src.pending.clear()
      all
    }, fn(k) { src.at.get(k).map(fn(_) { 0 }) })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_anchored(@view.Scroll::list(), fn() { [] }, est=60.0, indexed=rows.source,
      rooms=rows.room_now, fn(row, k) {
        row.height(By(fn() { (rows.item_of)(k).map(fn(x) { x.0.1 }) })).ground(Is(0x3366CCFFL)) |> ignore
      }) |> ignore
  })
  t.draw()
  t.run_for(row_size_ms)
  (t, src, out.val.unwrap())
}

///|
/// How many reads of its rows one row coming at the end of `n` takes, from the frame it comes to its room open.
fn indexed_reads_for_one(n : Int) -> Int {
  let (t, src, _) = indexed_list(n)
  src.reads.val = 0
  src.came("new")
  t.draw()
  t.run_for(row_size_ms)
  src.reads.val
}

///|
test "an indexed list's row come at its end reads as much of thirty rows as of three thousand" {
  assert_eq(indexed_reads_for_one(30), indexed_reads_for_one(3000))
}

///|
test "an indexed list's row come at its end opens in its room on the rows' way" {
  let (t, src, _) = indexed_list(30)
  src.came("new")
  t.draw()
  let start = t.time()
  let mut opening = false
  for ms in [17.5, 73.75] {
    t.frame_at(start + ms)
    match t.row(30) {
      Some((_, _, _, h)) if h > 0.0 && h < 60.0 => opening = true
      _ => ()
    }
  }
  t.frame_at(start + row_size_ms)
  assert_true(opening, msg="it opens on the frames between")
  assert_eq(t.row(30).map(fn(r) { r.3 }), Some(60.0))
}

///|
test "an indexed list's row gone leaves in its room where it was, then is gone from it" {
  let (t, src, rows) = indexed_list(30)
  src.went(29)
  t.draw()
  let (_, n) = (rows.source.snapshot)()
  assert_eq(n, 30, msg="the row leaving is still among them")
  assert_eq((rows.source.key)(29), "m29")
  assert_eq((rows.source.find)("m29", 29), Some(29))
  assert_true((rows.item_of)("m29") is Some((("m29", _), 29)))
  let start = t.time()
  let mut closing = false
  for ms in [17.5, 73.75] {
    t.frame_at(start + ms)
    match t.row(29) {
      Some((_, _, _, h)) if h > 0.0 && h < 60.0 => closing = true
      _ => ()
    }
  }
  t.frame_at(start + row_size_ms + 1.0)
  assert_true(closing, msg="it closes on the frames between")
  assert_eq((rows.source.snapshot)().1, 29)
  assert_true((rows.source.contains)("m29") is false)
}

///|
test "an indexed list given whole shows its rows as they are, nothing coming" {
  let (t, src, rows) = indexed_list(30)
  // (one more, all of them given anew: read again, say)
  src.at["new"] = src.keys.length()
  src.keys.push("new")
  src.pending.push(Whole)
  src.rev.set(src.rev.get() + 1)
  t.draw()
  assert_eq((rows.moving)(), [])
  assert_eq(t.row(30).map(fn(r) { r.3 }), Some(60.0))
}

///|
test "an indexed list's row come and gone in one change never was: nothing leaving, nothing moving" {
  let (t, src, rows) = indexed_list(30)
  // (said and held back at once: it comes and goes as one change)
  src.pending.push(Came("brief"))
  src.pending.push(Went("brief", ("brief", 60.0), Some("m29")))
  src.rev.set(src.rev.get() + 1)
  t.draw()
  assert_eq((rows.source.snapshot)().1, 30, msg="nothing among them leaving")
  assert_true((rows.source.find)("brief", 29) is None)
  assert_eq((rows.moving)(), [])
}

///|
test "an indexed list's row gone and come again in one change is there still, not leaving nor coming" {
  let (t, src, rows) = indexed_list(30)
  src.pending.push(Went("m29", ("m29", 60.0), Some("m28")))
  src.pending.push(Came("m29"))
  src.rev.set(src.rev.get() + 1)
  t.draw()
  assert_eq((rows.source.snapshot)().1, 30)
  assert_eq((rows.source.find)("m29", 29), Some(29))
  assert_eq((rows.moving)(), [])
  assert_eq(t.row(29).map(fn(r) { r.3 }), Some(60.0))
}

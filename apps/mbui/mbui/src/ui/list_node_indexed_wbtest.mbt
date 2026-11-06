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
/// A changed row can leave the source without a leaving animation. If it returns under the same key after that
/// motion is over (or cancelled), a later change must not start from the old incarnation's measured height.
fn indexed_gone_during_change(how : Int) -> Double raise {
  let src = IndexedRows::new(30)
  let watching = @signals.signal(true)
  let out : Ref[NodeRowsIndexed[(String, Double)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node_indexed(root, src.source(), fn(i) { src.item(i) }, fn() {
      let all = src.pending.copy()
      src.pending.clear()
      all
    }, fn(k) { src.at.get(k).map(fn(_) { 0 }) }, watched=fn() { watching.get() }, comes=fn(_) { false })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_anchored(@view.Scroll::list(), fn() { [] }, est=60.0, indexed=rows.source,
      rooms=rows.room_now, fn(row, k) {
        row.height(By(fn() { (rows.item_of)(k).map(fn(x) { x.0.1 }) })) |> ignore
      }) |> ignore
  })
  t.draw()
  t.run_for(row_size_ms)
  let rows = out.val.unwrap()
  (rows.room)("m0", 60.0) |> ignore
  src.pending.push(Set("m0"))
  src.rev.set(src.rev.get() + 1)
  t.draw()
  assert_true((rows.moving)().contains("m0"), msg="the old row is changing")
  // An indexed source reports a removal in removed_since, with no row kept for a leave transition.
  src.keys.remove(0) |> ignore
  src.at.remove("m0")
  for i, k in src.keys { src.at[k] = i }
  src.gone.push((src.rev.get() + 1, "m0"))
  src.rev.set(src.rev.get() + 1)
  t.draw()
  assert_true((rows.moving)().contains("m0"), msg="the original cause still protects the old height")
  if how == 2 {
    // A brief come and go in one batch has no row in the final source and no entry in its removal history.
    @signals.start_batch()
    src.pending.push(Came("m0"))
    src.pending.push(Went("m0", ("m0", 60.0), None))
    src.rev.set(src.rev.get() + 1)
    @signals.end_batch()
    t.draw()
  } else if how == 1 {
    watching.set(false)
    t.draw()
    watching.set(true)
    t.draw()
  } else {
    t.run_for(row_size_ms + 1.0)
  }
  assert_true(!(rows.moving)().contains("m0"), msg="the old cause ended or was cancelled")
  // Keep the replacement out of the laid-out window until its new height is queried below.
  t.scroll_to(0)
  t.draw()
  assert_true(t.visible().1 < 25, msg="the viewport is away from the end: \{t.visible()}")
  @signals.start_batch()
  src.came("m0")
  src.pending.push(Set("m0"))
  @signals.end_batch()
  t.draw()
  assert_true(t.visible().1 < 25, msg="the replacement remains out of view: \{t.visible()}")
  assert_true((rows.moving)().contains("m0"), msg="the replacement has its own change")
  (rows.room)("m0", 120.0).height
}

///|
test "an indexed row removed while changing forgets its old height when its cause ends" {
  assert_eq(indexed_gone_during_change(0), 120.0)
}

///|
test "an indexed row removed while changing forgets its old height when its cause is cancelled" {
  assert_eq(indexed_gone_during_change(1), 120.0)
}

///|
test "a brief come and go forgets a removed row's previously protected height" {
  assert_eq(indexed_gone_during_change(2), 120.0)
}

///|
test "an indexed list forgets removed rows when their source no longer has the removal history" {
  let src = IndexedRows::new(30)
  let original = src.source()
  let expired = Ref(false)
  let source : @view.AnchoredSource[String] = {
    ..original,
    removed_since: fn(rev) { if expired.val { None } else { (original.removed_since)(rev) } },
  }
  let out : Ref[NodeRowsIndexed[(String, Double)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node_indexed(root, source, fn(i) { src.item(i) }, fn() {
      let all = src.pending.copy()
      src.pending.clear()
      all
    }, fn(k) { src.at.get(k).map(fn(_) { 0 }) }, comes=fn(_) { false })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_anchored(@view.Scroll::list(), fn() { [] }, est=60.0, indexed=rows.source,
      rooms=rows.room_now, fn(row, k) {
        row.height(By(fn() { (rows.item_of)(k).map(fn(x) { x.0.1 }) })) |> ignore
      }) |> ignore
  })
  t.draw()
  t.run_for(row_size_ms)
  let rows = out.val.unwrap()
  (rows.room)("m0", 60.0) |> ignore
  src.keys.remove(0) |> ignore
  src.at.remove("m0")
  for i, k in src.keys { src.at[k] = i }
  expired.val = true
  src.rev.set(src.rev.get() + 1)
  t.draw()
  expired.val = false
  t.scroll_to(0)
  t.draw()
  assert_true(t.visible().1 < 25, msg="the viewport is away from the end: \{t.visible()}")
  @signals.start_batch()
  src.came("m0")
  src.pending.push(Set("m0"))
  @signals.end_batch()
  t.draw()
  assert_true(t.visible().1 < 25, msg="the replacement remains out of view: \{t.visible()}")
  assert_eq((rows.room)("m0", 120.0).height, 120.0)
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

///|
/// How many times a row's room was worked out, and how many rows were measured, opening a list of `n` rows 60 tall in a
/// window 300 tall, 160 made ahead of it each way: those in sight and ahead alone, whatever `n`.
fn indexed_open_work(n : Int) -> (Int, Int) {
  let src = IndexedRows::new(n)
  let sizes : ListRows[(String, Double)] = ListRows::new()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = sizes.in_node_indexed(root, src.source(), fn(i) { src.item(i) }, fn() {
      let all = src.pending.copy()
      src.pending.clear()
      all
    }, fn(k) { src.at.get(k).map(fn(_) { 0 }) })
    root.height(Is(Some(300.0))).scrolls_anchored(@view.Scroll::list(), fn() { [] }, est=60.0, ahead=160.0,
      indexed=rows.source, rooms=rows.room_now, fn(row, k) {
        row.height(By(fn() { (rows.item_of)(k).map(fn(x) { x.0.1 }) })) |> ignore
      }) |> ignore
  })
  let measured = view_tree().map(fn(tree) { tree.work.measured }).unwrap_or(0)
  t.draw()
  t.run_for(row_size_ms)
  (sizes.rooms_worked(), view_tree().map(fn(tree) { tree.work.measured }).unwrap_or(0) - measured)
}

///|
test "a list opened works out the rooms of and measures the rows in sight and ahead of it alone, of 30 as of 3000" {
  let (rooms, measured) = indexed_open_work(3000)
  assert_eq((rooms, measured), indexed_open_work(30))
  // (300 in sight and 160 ahead under it, rows 60 tall: 8 of them, each worked out a few times over as it opens)
  assert_true(rooms <= 8 * 4, msg="\{rooms} rooms worked out")
}

///|
/// (a row measured twice in one layout as it opens, at its own height and at its room's: found laid out the second
/// time, no box whose layout was kept from before, what lies over its parts laid out with it: flex's p_gen)
test "an indexed list's row made otherwise as it opens: what lies over a part of it laid out at its size, as in a row at rest" {
  let kind = @signals.signal(0, same=fn(a, b) { a == b })
  let over : Ref[@view.View?] = Ref(None)
  let src = IndexedRows::new(3)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node_indexed(root, src.source(), fn(i) { src.item(i) }, fn() {
      let all = src.pending.copy()
      src.pending.clear()
      all
    }, fn(k) { src.at.get(k).map(fn(_) { 0 }) })
    root.height(Is(Some(300.0))).scrolls_anchored(@view.Scroll::list(), fn() { [] }, est=60.0, indexed=rows.source,
      rooms=rows.room_now, fn(row, _k) {
        row.pick(fn() { kind.get() }, fn(b, k) {
          b.height(Is(Some(60.0))) |> ignore
          if k == 1 {
            b.box(fn(m) {
              m.width(Is(Some(80.0))).height(Is(Some(50.0))).clips(Is(true)) |> ignore
              m.box(fn(o) {
                over.val = Some(o)
                o.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(50.0))).ground(Is(0xFF0000FFL)) |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        })
      }) |> ignore
  })
  t.draw()
  t.run_for(row_size_ms)
  src.came("new")
  t.draw()
  t.run_for(row_size_ms / 3.0)
  kind.set(1)
  t.draw()
  t.run_for(row_size_ms)
  let (_, _, w, h) = over.val.unwrap().laid_window_now()
  assert_eq((w, h), (80.0, 50.0))
}

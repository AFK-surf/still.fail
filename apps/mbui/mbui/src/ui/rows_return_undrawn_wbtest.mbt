// Rows steady's return (rows_steady.mbt, rows_steady_return) holds what is seen: a row going, its room under half
// closed and what it holds at alpha 0, whose place moves back as another row comes is not said; a row drawn that does
// the same is (the coordinator of the migration, 2026-11-11).

///|
/// A list held at its end, its rows short of its view standing at its end (a chat's), of the rows `ids()` gives keyed
/// by their ids, each coming and going where it is (ListRows::enter, leave): row 100 20 tall and on a way of 600 ms
/// (as words sent fly), every other 50 tall and 300 ms.
fn return_rows(ids : () -> Array[Int]) -> (Ctx) -> Unit {
  let rows : ListRows[Int] = ListRows::new()
  fn(c) {
    let now = ids()
    let (items, keys) = rows.rows(
      c,
      now.map(fn(i) { "r" + i.to_string() }),
      now,
      fn(_) { "" },
      ms=fn(k) { if k == "r100" { Some(600.0) } else { None } },
    )
    c.list(
      "list",
      items.length(),
      50.0,
      fn(k) {
        let h = if items[k] == 100 { 20.0 } else { 50.0 }
        let b = c.box(h=Px(h), fn() { c.text("Row \{items[k]}", wrap=false) |> ignore })
        rows.enter(c, b, keys[k])
        rows.leave(c, b, keys[k])
      },
      stick_end=true,
      from_end=true,
      sized=rows.sized(),
    )
    |> ignore
  }
}

///|
/// Rows 0 to 3 at the list's end; row `goes` goes as row 100 comes after it (what is over row 100 going down by 30 as
/// the two rooms close and open on one way), and 540 ms on, that way all but over, row 200 comes under row 100 (what is
/// over it going up by 50): every frame drawn on the way, the rows not steady found (none failing the Tester).
fn return_walk(goes : Int) -> Array[String] {
  let ids = @signals.signal([0, 1, 2, 3])
  let t = Tester::new(return_rows(fn() { ids.get() }), w=300.0, h=400.0)
  // (each found counted, none failing this Tester)
  rows_steady_bars[rows_steady.file] = 99
  t.run_for(row_size_ms * 2.0)
  let t0 = t.time()
  let kept = [0, 1, 2, 3].filter(fn(i) { i != goes })
  kept.insert(goes, 100)
  ids.set(kept)
  let mut came = false
  while t.time() < t0 + 1400.0 {
    if !came && t.time() >= t0 + 540.0 {
      came = true
      let now = ids.get()
      let at = now.search(100).unwrap()
      ids.set(now[:at + 1].to_owned() + [200] + now[at + 1:].to_owned())
    }
    t.frame()
  }
  rows_steady.found.iter().collect()
}

///|
test "rows steady: a row going, under half open, its place moving back as a row comes under the one after it: not drawn, no return said" {
  // (frames it walks itself, judged by the default run alone: test_at_a_rate)
  if test_at_a_rate() {
    return
  }
  // (row 0 goes, row 100 coming in its place: row 0 down 30 and back up 50 once all but closed; rows 1 to 3 stand,
  // rows 100 and 200 only go up)
  let found = return_walk(0)
  assert_eq(found, [])
}

///|
test "rows steady: the same walk, the row moving back drawn whole: its return said" {
  if test_at_a_rate() {
    return
  }
  // (row 1 goes, row 100 coming in its place: row 0, whole, over them, down 30 and back up 50)
  let found = return_walk(1)
  assert_true(found.iter().any(fn(f) { f.has_suffix("/r0 (list list)") }), msg="\{Repr(found)}")
}

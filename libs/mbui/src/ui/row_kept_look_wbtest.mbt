// A list's row coming or going where it is (ListRows::enter, leave), kept as its nodes on its way (kept_nodes.mbt) while
// what is built before the list makes more nodes or fewer: its nodes put back elsewhere among the frame's, it is drawn
// as it is where nothing before it changed, its look read of its own node where that is now (Ctx::node_held), never of
// what is in the place it was built in: another node there, or one left of a frame before past the frame's last.

///|
/// The colour of what the row coming or going holds, at its left (none else of it in the frame).
let kept_row_ink : Int64 = 0xD0402AFFL

///|
/// A bar of `more` marks over a list showing only what its rows read (kept as their nodes however the frame is built),
/// of the rows `ids` gives, each coming and going where it is; row 4 holds a box of kept_row_ink 40 wide at its left.
fn kept_row_page(ids : @signals.Signal[Array[Int]], more : @signals.Signal[Int]) -> (Ctx) -> Unit {
  let rows : ListRows[Int] = ListRows::new()
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      // (as tall whatever it holds: the list stands where it stood)
      c.box(dir=Row, w=Fill(1.0), h=Px(20.0), gap=2.0, fn() {
        for _ in 0..<more.get() {
          c.box(w=Px(4.0), h=Px(4.0), bg=0x3366CCFFL, fn() {  }) |> ignore
        }
      })
      |> ignore
      let now = ids.get()
      let (items, keys) = rows.rows(c, now.map(fn(i) { "r\{i}" }), now, fn(_) { "" })
      c.list(
        "rows",
        items.length(),
        50.0,
        fn(k) {
          let i = items[k]
          let b = c.box(w=Fill(1.0), h=Px(50.0), dir=Row, align=AStart, fn() {
            c.box(w=Px(40.0), h=Px(50.0), bg=if i == 4 { kept_row_ink } else { 0x999999FFL }, fn() {  }) |> ignore
          })
          rows.enter(c, b, keys[k])
          rows.leave(c, b, keys[k])
        },
        rows_read=true,
        sized=rows.sized(),
      )
      |> ignore
    })
    |> ignore
  }
}

///|
/// Row 4 coming (`goes` false: rows 0 to 3 there, then 0 to 4) or going (0 to 4, then 0 to 3), the bar holding `before`
/// marks till `change_ms` on its way and `after` from the next frame: the frame as drawn `at_ms` later, how many rows the
/// frame that changed the bar kept as their nodes, and where what row 4 holds is drawn then (x, y, w, h). Drawn as a
/// host draws its frames (none built again whole to compare: that one would build the row again where it is now).
fn kept_row_drawn(
  goes : Bool,
  before : Int,
  after : Int,
  change_ms : Double,
  at_ms : Double,
) -> (Array[Array[Double]], Int, Array[Double]) raise {
  let ids = @signals.signal(if goes { [0, 1, 2, 3, 4] } else { [0, 1, 2, 3] })
  let more = @signals.signal(before)
  let t = Tester::new(kept_row_page(ids, more), w=300.0, h=400.0)
  t.check_looks(false)
  t.draw()
  ids.set(if goes { [0, 1, 2, 3] } else { [0, 1, 2, 3, 4] })
  t.frame()
  t.run_for(change_ms)
  more.set(after)
  t.frame()
  let kept = t.rows_as_nodes().0
  t.run_for(at_ms - change_ms)
  (insts(), kept, rect_of_color(kept_row_ink)[0:4].to_owned())
}

///|
test "a row coming or going where it is, kept as its nodes on its way as nodes before its list come or go: drawn as where none did, the place it was built in another node's or past the frame's last" {
  let ms = row_size_ms
  // (coming, from nothing: well open by then; going: well open still)
  let cases = [
    (false, 0, 30, 0.2 * ms, 0.6 * ms),
    (false, 30, 0, 0.2 * ms, 0.6 * ms),
    (true, 0, 30, 0.05 * ms, 0.15 * ms),
    (true, 30, 0, 0.05 * ms, 0.15 * ms),
  ]
  let parted = []
  for cs in cases {
    let (goes, before, after, change_ms, at_ms) = cs
    let (drawn, kept, row) = kept_row_drawn(goes, before, after, change_ms, at_ms)
    // (the same, the bar as it is then all the while)
    let (still, _, still_row) = kept_row_drawn(goes, after, after, change_ms, at_ms)
    // (kept as its nodes, the row: what is asked of it; grown or shrunk then, about the middle of what it holds)
    assert_true(kept > 0, msg="\{Repr(cs)}: no row kept as the bar changed")
    assert_true(still_row[2] < 40.0 && still_row[2] > 0.0, msg="\{Repr(cs)}: row 4 drawn \{Repr(still_row)}, not on its way")
    if row != still_row || drawn != still {
      parted.push("\{Repr(cs)}: row 4 drawn at \{Repr(row)}, where nothing before it changed \{Repr(still_row)}")
    }
  }
  assert_eq(parted, [], msg=parted.join("\n"))
}

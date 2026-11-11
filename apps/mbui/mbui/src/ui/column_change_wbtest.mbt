// One child put in, and one taken out, of a plain column of 17 and of 170 (View::each): what the frame that takes it,
// and any drawn after it, works out again, counted. The parts of it that belong to the one child (its box put in, its
// inputs, its run of the drawing order) do not grow with the column's other children; what still does is held to a
// bar that only falls (`column_change_known`): those of the tree's are mended in its order, input and layout parts,
// those of the paint's wait for its own mend.

///|
/// What a frame worked out, counted: nodes told whether they take input (Tree::inputs_down), entries of the drawing
/// order put in again (Tree::order_from), boxes walked as a holder's boxes were put again (Tree::boxes), and of the
/// paint, contents' drawings made again, those copied kept, and instances handed the host (ui's view_paint_work; what
/// the host compares and hashes of them is the damage's own, not counted here).
priv struct ChangeCount {
  inputs : Int
  order : Int
  boxes : Int
  made : Int
  copied : Int
  handed : Int
}

///|
fn change_said(c : ChangeCount) -> String {
  "inputs \{c.inputs}, order \{c.order}, boxes \{c.boxes}, made \{c.made}, copied \{c.copied}, handed \{c.handed}"
}

///|
fn change_count_now() -> ChangeCount {
  match view_app.val {
    Some(tree) => {
      let w = tree.work()
      {
        inputs: w.inputs_walked,
        order: w.order_copied,
        boxes: w.boxes_walked,
        made: view_paint_work.made,
        copied: view_paint_work.copied,
        handed: view_paint_work.handed,
      }
    }
    None => { inputs: 0, order: 0, boxes: 0, made: 0, copied: 0, handed: 0 }
  }
}

///|
fn change_count_less(a : ChangeCount, b : ChangeCount) -> ChangeCount {
  {
    inputs: a.inputs - b.inputs,
    order: a.order - b.order,
    boxes: a.boxes - b.boxes,
    made: a.made - b.made,
    copied: a.copied - b.copied,
    handed: a.handed - b.handed,
  }
}

///|
/// A column of `n` rows 20 tall (View::each, each made at once), each a press with words, in a window 300 by 400; one
/// row put in at its middle, then taken out again, each its own change: what the frames that took each worked out.
fn column_change(n : Int) -> (ChangeCount, ChangeCount) {
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      col.each(fn() { keys.get() }, fn(k) { k }, fn(row, item) {
        row
        .height(Is(Some(20.0)))
        .words(By(fn() { "row \{item.get()}" }))
        .on_press(fn() {  })
        .says(By(fn() { Some(@view.said(Button, label="row \{item.get()}")) }))
        |> ignore
      }, at_once=true)
    })
    |> ignore
  })
  t.draw()
  t.run_for(change_settle_ms)
  // (each change at its own moment, what the frames after it worked out till it is at rest)
  let c0 = change_count_now()
  keys.set({
    let ks = keys.untracked().copy()
    ks.insert(n / 2, 100000)
    ks
  })
  t.run_for(change_settle_ms)
  let c1 = change_count_now()
  keys.set(keys.untracked().filter(fn(k) { k != 100000 }))
  t.run_for(change_settle_ms)
  let c2 = change_count_now()
  (change_count_less(c1, c0), change_count_less(c2, c1))
}

///|
/// How long a change is given to be taken and come to rest: no way of its own (each at once), so its frame alone.
let change_settle_ms : Double = 100.0

///|
/// What one child put in (`in`) and taken out (`out`) of a column of 17 and of 170 works out again, as main had it:
/// each may only fall. What grows with the column's children here grows with them for each change of any column.
/// `copied` and `handed` are the paint's, not the drawing order's: `copied` is `view_paint_work.copied`, the nodes of
/// each kept row's drawing the paint's walk copies into the frame (ui's view_host.mbt: `list_again`, `ride_again`),
/// about three for each of the column's rows in every frame it draws, whatever the order kept; `handed` the instances
/// put into the frame for the host. Both pinned as they are till the paint's own mend.
let column_change_known : Map[(Int, String), ChangeCount] = Map::from_array([
  ((17, "in"), { inputs: 1, order: 1, boxes: 0, made: 1, copied: 54, handed: 252 }),
  ((17, "out"), { inputs: 0, order: 0, boxes: 0, made: 0, copied: 51, handed: 225 }),
  ((170, "in"), { inputs: 1, order: 1, boxes: 0, made: 1, copied: 513, handed: 2757 }),
  ((170, "out"), { inputs: 0, order: 0, boxes: 0, made: 0, copied: 510, handed: 2730 }),
])

///|
test "one child put in, and one taken out, of a plain column of 17 and of 170: what the frames that take it work out again, held to its bars" {
  let faults = []
  for n in [17, 170] {
    let (put_in, taken_out) = column_change(n)
    for change in [("in", put_in), ("out", taken_out)] {
      let (what, got) = change
      println("column_change: \{n} \{what} \{change_said(got)}")
      match column_change_known.get((n, what)) {
        Some(bar) =>
          if got.inputs > bar.inputs ||
            got.order > bar.order ||
            got.boxes > bar.boxes ||
            got.made > bar.made ||
            got.copied > bar.copied ||
            got.handed > bar.handed {
            faults.push("\{n} \{what}: \{change_said(got)} over its bar \{change_said(bar)}")
          }
        None => faults.push("\{n} \{what}: no bar for \{change_said(got)}")
      }
    }
  }
  assert_eq(faults, [])
}

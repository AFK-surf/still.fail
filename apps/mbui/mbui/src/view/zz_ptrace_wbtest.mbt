///|
/// The layout-count test's fling (list_anchor_flip_wbtest), each layout and each moment said told as it goes.
test "ptrace 4112" {
  let tall = fn(k : Int) { if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let scroll = Scroll::list()
  let tree = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(scroll, fn() { Array::makei(200, fn(i) { i }) }, est=80.0, ahead=0.0, fn(row, k) {
        row.height(Is(Some(tall(k)))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 30.0, 0.0, -900.0, 0, 10.0) |> ignore
  let mut t = 26.0
  while t < 1500.0 {
    tree.frame(300.0, 100.0, now=t) |> ignore
    t = t + 16.0
  }
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id2) else { fail("not taken") }
  foot_trace.val = true
  let m0 = meet_said.val
  tree.drag_at(id2, Down, 150.0, 90.0, 4000.0) |> ignore
  tree.drag_at(id2, Moved, 150.0, 50.0, 4005.0) |> ignore
  tree.drag_at(id2, Moved, 150.0, 10.0, 4010.0) |> ignore
  println("UP")
  tree.drag_at(id2, Up, 150.0, 10.0, 4010.0) |> ignore
  t = 4016.0
  while t < 4400.0 {
    let c = tree.work().computes
    println("FRAME \{t} begins")
    tree.frame(300.0, 100.0, now=t) |> ignore
    println("FRAME \{t} laid \{tree.work().computes - c}")
    t = t + 16.0
  }
  foot_trace.val = false
  println("MEETS said \{meet_said.val - m0}")
  tree.dispose()
}

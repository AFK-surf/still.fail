///|
fn ptrace(step : Double, change? : Bool = false) -> Unit {
  faults_stop.val = false
  let keys = @signals.signal(Array::makei(400, fn(i) { i }))
  let made : Map[Int, View] = {}
  let scroll = Scroll::list()
  let tree = Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, fn(b, k) {
        made[k] = b
        b.owns(fn() { made.remove(k) }).height(Is(Some(hist_tall(k)))).on_press(fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 50.0, 0.0, -2500.0, 0, 10.0) |> ignore
  let mut t = 10.0
  while t + 16.0 < 1500.0 {
    t = t + 16.0
    tree.frame(390.0, 844.0, now=t) |> ignore
  }
  tree.bring_to(1500.0)
  foot_trace.val = true
  println("== step \{step}")
  match tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -140.0) {
    Some(id) => {
      tree.drag_at(id, Down, 150.0, 90.0, 1500.0) |> ignore
      tree.drag_at(id, Moved, 150.0, 20.0, 1505.0) |> ignore
      tree.drag_at(id, Moved, 150.0, -50.0, 1510.0) |> ignore
      tree.drag_at(id, Up, 150.0, -50.0, 1510.0) |> ignore
    }
    None => println("not taken")
  }
  t = 1510.0
  let mut told = !change
  while t + step < 2600.0 {
    if !told && t + step >= 1520.0 {
      told = true
      println("EVENT at 1520")
      tree.event(1520.0, fn() { keys.set(keys.get()[0:keys.get().length() - 1].to_array()) })
    }
    t = t + step
    tree.frame(390.0, 844.0, now=t) |> ignore
    let f = @signals.untracked(fn() { scroll.fling.get() })
    println("FRAME t=\{t} x=\{@signals.untracked(fn() { scroll.x.get() })} past=\{scroll.past(tree)} fling=\{f.map(fn(f) { (f.end_t, f.end_x, f.till) })}")
  }
  tree.frame(390.0, 844.0, now=2600.0) |> ignore
  let rows = []
  for d in tree.drawn() {
    for k, v in made {
      if v.id().at == d.id.at {
        rows.push((k, d.y, d.h))
      }
    }
  }
  println("REST rows \{rows} x=\{@signals.untracked(fn() { scroll.x.get() })}")
  foot_trace.val = false
  tree.dispose()
  faults_stop.val = true
}

///|
test "ptrace" {
  ptrace(1000.0 / 60.0, change=true)
  ptrace(1.0e9, change=true)
}

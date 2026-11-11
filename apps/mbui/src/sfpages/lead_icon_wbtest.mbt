// A chat's lead icon alone in a window's tree (lead_icon_node): watching's dot beats on the resident clock's steps (a
// binding of its scale reading View::cycle_resident), waiting's dots breathe (its look's), each frame at a step drawn as
// it is built whole, nothing else in the tree to build it.

///|
/// A tree holding the lead icon `lead` alone.
fn lead_alone(lead : String) -> @ui.Tester {
  @ui.Tester::new(
    fn(_c) {  },
    tree=fn(root) { root.box(fn(b) { lead_icon_node(b, lead, fn() { 0x333333FFL }) }) |> ignore },
    w=100.0,
    h=100.0,
    platform=0,
  )
}

///|
/// What the tree draws now, by where and how big each is, how opaque, and the inks of its shapes (waiting's dots
/// breathe by their inks alone: icon_inks_node).
fn lead_drawn() -> String {
  @ui.view_tree()
  .unwrap()
  .drawn()
  .map(fn(d) {
    let inks = d.shapes.map(fn(s) { "\{s.fill}/\{s.stroke}" }).join(",")
    "\{d.x},\{d.y} \{d.w}x\{d.h} \{d.alpha} [\{inks}]"
  })
  .join(" | ")
}

///|
test "watching's lead alone: two of its loops run, its dot drawn otherwise from one step to another" {
  let t = lead_alone("watch")
  t.draw()
  t.run_for(lead_loop_ms * 2.0)
  // (over a loop, a step at a time: the dot beats, so what is drawn is not the same at every step)
  let seen : Set[String] = Set([])
  let mut ms = 0.0
  while ms < lead_loop_ms {
    t.run_for(@view.resident_step_ms)
    seen.add(lead_drawn())
    ms = ms + @view.resident_step_ms
  }
  assert_true(seen.length() > 1, msg="one drawing over a loop: \{seen.length()}")
}

///|
test "waiting's lead alone: two of its loops run, its dots drawn otherwise from one step to another" {
  let t = lead_alone("wait")
  t.draw()
  t.run_for(lead_loop_ms * 2.0)
  let seen : Set[String] = Set([])
  let mut ms = 0.0
  while ms < lead_loop_ms {
    t.run_for(@view.resident_step_ms)
    seen.add(lead_drawn())
    ms = ms + @view.resident_step_ms
  }
  assert_true(seen.length() > 1, msg="one drawing over a loop: \{seen.length()}")
}

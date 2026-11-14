// Where a node takes a finger (View::takes) as what asks reads it (Tree::finger_areas): said anew, told already so.

///|
test "where a node takes a finger said anew: what reads it as it is told reads the new, not the one before" {
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        node.val = Some(
          b.width(Is(Some(80.0))).height(Is(Some(40.0))).on_press(fn() {  }).takes(fn(w, h, _) { [(0.0, 0.0, w, h)] }),
        )
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = node.val.unwrap().id()
  let seen : Array[@view.FingerAreas] = []
  let stop = @signals.effect(fn() { seen.push(t.finger_areas(id)) })
  assert_eq(seen.last(), Some(@view.InWindow([(0.0, 0.0, 80.0, 40.0)])))
  node.val.unwrap().takes(fn(w, h, _) { [(w / 2.0, 0.0, w, h)] }) |> ignore
  assert_eq(seen.last(), Some(@view.InWindow([(40.0, 0.0, 80.0, 40.0)])), msg="\{seen.length()} told")
  stop()
}

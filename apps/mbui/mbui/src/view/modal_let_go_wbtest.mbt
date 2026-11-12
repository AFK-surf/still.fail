///|
/// Where a device meets it: a tool's tip (sf's tool_node_wbtest, "a modal layer coming over it while it waits"), its
/// holder under a modal layer that is shown and then let go of (a show said off): what that layer kept from taking
/// input takes it again as the layer goes, not only where a modal layer is said off while it stays.
test "a modal layer of the root's let go: what was under it told it takes input again" {
  let over = @signals.signal(false, same=fn(a, b) { a == b })
  let under : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      under.val = Some(
        root.box(fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(40.0))).on_press(fn() {  }) |> ignore
          @signals.untracked(fn() { b.takes_input() }) |> ignore
        }),
      )
      root.show(at_once=true, fn() { over.get() }, fn(m) {
        m.width(Is(Some(390.0))).height(Is(Some(844.0))).modal(Is(true)).stacked(Is(1)) |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let b = under.val.unwrap()
  assert_true(@signals.untracked(fn() { b.takes_input() }))
  over.set(true)
  t.frame(390.0, 844.0) |> ignore
  assert_false(@signals.untracked(fn() { b.takes_input() }), msg="under a modal layer")
  over.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_true(@signals.untracked(fn() { b.takes_input() }), msg="the modal layer let go")
  assert_eq(t.kept_said(), None)
}

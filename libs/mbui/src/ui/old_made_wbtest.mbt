// An old view made as the frame is built, by what another old view builds (a dialog presented as a page is built): built
// itself in that frame, what it holds drawn, nothing from outside the app needed.

///|
test "an old view made as another old view is built, in a layer of the tree's: built in that frame, what it holds drawn; each frame as built whole" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  let ask = @signals.signal(false)
  let shown = @signals.signal(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        c.text("页") |> ignore
        // (as a page builds: what it asks for presented, a layer opened)
        if ask.get() && !shown.untracked() {
          shown.set(true)
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { shown.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(2)).presses(Is(true)) |> ignore
      old(l, natural=true, fn(c) { c.text("层里的话") |> ignore }).width(Is(Some(200.0))) |> ignore
    })
  })
  t.draw()
  ask.set(true)
  t.frame()
  // (in that frame, and as it stays)
  let at_once = t.words().filter(fn(w) { w.0 == "层里的话" }).length()
  for _ in 0..<5 {
    t.frame_at(t.next_frame_time())
  }
  assert_eq((at_once, t.words().filter(fn(w) { w.0 == "层里的话" }).length()), (1, 1))
}

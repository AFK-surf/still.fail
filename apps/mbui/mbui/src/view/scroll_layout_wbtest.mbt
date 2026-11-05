///|
test "scroll content and its bar receive their sizes in one parent layout" {
  for across in [false, true] {
    let length = @signals.signal(600.0)
    let width = @signals.signal(300.0)
    let bar : ScrollBar = {
      drawn: fn() { true }, ink: fn() { 0x000000FFL }, ink_held: fn() { 0x111111FFL },
      ease: fn(t) { t }, size: 3.0, inset: 2.0, least: 28.0, near: 12.0,
      grab: 4.0, hold_ms: 900.0, fade_ms: 200.0,
    }
    let viewport : Ref[View?] = Ref(None)
    let tree = Tree::new(fn(root) {
      viewport.val = Some(root.box(fn(v) {
        v.width(By(fn() { Some(width.get()) })) |> ignore
        if !across { v.height(Is(Some(100.0))) |> ignore }
        v.scrolls(if across { Scroll::across() } else { Scroll::new() }, bar~, fn(held) {
          held.box(fn(child) {
            if across {
              child.width(By(fn() { Some(length.get()) })).height(Is(Some(40.0))) |> ignore
            } else {
              child.height(By(fn() { Some(length.get()) })) |> ignore
            }
          }) |> ignore
        }) |> ignore
      }))
    }, time=fn() { 0.0 })
    defer { tree.dispose() }
    for (content, available) in [(600.0, 300.0), (180.0, 300.0), (600.0, 240.0)] {
      @signals.start_batch()
      length.set(content)
      width.set(available)
      @signals.end_batch()
      tree.work.computes = 0
      tree.frame(500.0, 600.0, now=0.0) |> ignore
      let expected_height = if across { if content > available { 47.0 } else { 40.0 } } else { 100.0 }
      assert_eq(viewport.val.unwrap().rect(), (0.0, 0.0, available, expected_height))
      assert_eq(tree.work.computes, 1,
        msg="the content, scrollbar and reserved room must not lay out the tree again after publishing sizes")
    }
  }
}

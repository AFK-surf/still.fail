// @ui.old_anchor beside kit's own menu over the same old target (dropdown_menu, its menu_anchor): each frame where kit's
// menu goes beside and where the tree's node is, the target never drawn, drawn, moved (all else at rest), gone.

///|
test "old_anchor: where kit's open dropdown goes beside, each frame: never drawn, drawn, moved, gone" {
  let (drawn, at) = (@signals.signal(false), @signals.signal(100.0))
  let (trig, pid) = (Ref(-1), Ref(-1))
  // (where kit's menu went beside as this frame built it)
  let kit_at : Ref[(Double, Double, Double, Double)] = Ref((-1.0, -1.0, -1.0, -1.0))
  let open = @signals.signal(false)
  let node = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.old(root, fn(c) {
      let id = c.id("trigger")
      trig.val = id
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(10.0), h=Px(at.get()), fn() {  }) |> ignore
        if drawn.get() {
          c.box(id~, w=Px(50.0), h=Px(20.0), fn() {  }) |> ignore
          c.clicked(id) |> ignore
        }
      })
      |> ignore
      dropdown_menu(c, "m", true, id, [menu_item("a", label="一项")]) |> ignore
      pid.val = c.id("m/panel")
      kit_at.val = menu_anchor(c, pid.val, id, true)
    })
    .grow(Is(1.0))
    |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)) |> ignore
      let a = @ui.old_anchor(l, trig.val, (0.0, 0.0, 0.0, 0.0))
      a.ground(Is(0xff0000ffL)) |> ignore
      node.val = Some(a.id())
    })
  })
  t.draw()
  open.set(true)
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let placed = fn() {
    match tree.drawn().iter().find_first(fn(d) { Some(d.id) == node.val }) {
      Some(d) => (d.x, d.y, d.w, d.h)
      None => (-2.0, -2.0, -2.0, -2.0)
    }
  }
  let frames = fn(n : Int) {
    let out = []
    for _ in 0..<n {
      t.frame()
      out.push((kit_at.val, placed()))
    }
    out
  }
  let never = frames(3)
  drawn.set(true)
  let shown = frames(3)
  // (kit's menu in, at rest)
  t.run_for(pop_ms)
  at.set(200.0)
  let moved = frames(3)
  drawn.set(false)
  let gone = frames(4)
  println("KITANCHOR never \{never} shown \{shown} moved \{moved} gone \{gone}")
  for f in never + shown + moved + gone {
    assert_eq(f.1, f.0, msg="never \{never} shown \{shown} moved \{moved} gone \{gone}")
  }
}

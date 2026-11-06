// A style on a retained node can change which properties it says. The node, its focus and any properties the style
// does not say stay as they were; later explicit properties belong to the caller.

///|
fn style_node_drawn(v : @view.View) -> @view.Drawn {
  @ui.view_tree().unwrap().drawn_of(v.id()).unwrap()
}

///|
test "a node style comes, grows, is fixed and goes: the caller's live properties return and focus stays" {
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let width = @signals.signal(48.0, same=fn(a, b) { a == b })
  let ground = @signals.signal(0x112233FFL, same=fn(a, b) { a == b })
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let disposed = Ref(0)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.show(fn() { there.get() }, fn(v) {
        made.val = Some(v)
        v
        .width(By(fn() { Some(width.get()) }))
        .height(Is(Some(32.0)))
        .ground(By(fn() { ground.get() }))
        .radius(Is(3.0))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="style target"))))
        |> ignore
        v.owns(fn() { disposed.val += 1 }) |> ignore
        style_node(v, fn() {
          match which.get() {
            1 => @ui.style(w=Fixed(80.0), h=Fixed(40.0), bg=Data(0xAABBCCFFL), radius=Md)
            2 => @ui.style(w=Grow(1.0), bg=Data(0xAABBCCFFL))
            _ => @ui.style()
          }
        }, in_row=true)
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let id = v.id()
  assert_eq((v.laid_size(), style_node_drawn(v).ground, style_node_drawn(v).radius), ((48.0, 32.0), 0x112233FFL, 3.0))
  t.key(@ui.key_tab)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("style target"))
  which.set(1)
  t.draw()
  assert_eq((v.laid_size(), style_node_drawn(v).ground), ((80.0, 40.0), 0xAABBCCFFL))
  assert_eq(style_node_drawn(v).radius, @ui.tree_theme().corner(Md))
  assert_true(width.watched() && ground.watched())
  width.set(64.0)
  ground.set(0x445566FFL)
  which.set(2)
  t.draw()
  assert_eq((v.laid_size().0, v.laid_size().1), (300.0, 32.0))
  assert_eq(style_node_drawn(v).radius, 3.0)
  which.set(1)
  t.draw()
  assert_eq(v.laid_size(), (80.0, 40.0))
  which.set(0)
  t.draw()
  assert_eq((v.laid_size(), style_node_drawn(v).ground, style_node_drawn(v).radius), ((64.0, 32.0), 0x445566FFL, 3.0))
  assert_eq((v.id(), t.focused().map(fn(s) { s.label }), disposed.val), (id, Some("style target"), 0))
  there.set(false)
  t.draw()
  assert_eq((v.alive(), disposed.val, width.watched(), ground.watched(), which.watched()), (false, 1, false, false, false))
}

///|
test "an explicit property set after a node style keeps winning as its style changes" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() { if on.get() { @ui.style(w=Fixed(80.0), bg=Data(0xAABBCCFFL)) } else { @ui.style() } })
      v.width(Is(Some(60.0))).height(Is(Some(30.0))).ground(Is(0x112233FFL)) |> ignore
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  on.set(true)
  t.draw()
  assert_eq((v.laid_size(), style_node_drawn(v).ground), ((60.0, 30.0), 0x112233FFL))
  on.set(false)
  t.draw()
  assert_eq((v.laid_size(), style_node_drawn(v).ground), ((60.0, 30.0), 0x112233FFL))
}

///|
test "a node style follows narrow and dark blocks on the same node, even when the wide and narrow themes are the same" {
  let dark = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let light_theme = @ui.Theme::light()
  let dark_theme = @ui.Theme::dark()
  let t = @ui.Tester::new(fn(_) {  }, w=800.0, h=100.0)
  t.ctx().set_theme(light_theme, narrow=light_theme, narrow_below=500.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(fn() { if dark.get() { dark_theme } else { light_theme } })
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() {
        @ui.style(
          w=Fixed(80.0), h=Fixed(30.0), bg=Data(0x111111FFL),
          narrow=@ui.patch(w=Fixed(40.0), bg=Data(0x222222FFL)),
          dark=@ui.patch(bg=Data(0x333333FFL), radius=Md),
        )
      })
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let id = v.id()
  assert_eq((v.laid_size().0, style_node_drawn(v).ground), (80.0, 0x111111FFL))
  t.resize(400.0, 100.0)
  assert_eq((v.laid_size().0, style_node_drawn(v).ground), (40.0, 0x222222FFL))
  dark.set(true)
  t.draw()
  assert_eq((v.laid_size().0, style_node_drawn(v).ground), (40.0, 0x333333FFL))
  assert_true(style_node_drawn(v).radius > 0.0)
  t.resize(800.0, 100.0)
  dark.set(false)
  t.draw()
  assert_eq((v.id(), v.laid_size().0, style_node_drawn(v).ground, style_node_drawn(v).radius), (id, 80.0, 0x111111FFL, 0.0))
}

///|
test "a node style resolves the mouse, finger and keyboard patches in the old style's order" {
  let base = 0xFFFFFFFFL
  let hover = 0xFF000080L
  let pressed = 0x0000FF80L
  let focus = 0x00FF00FFL
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0, native=Mouse, pointing=Mouse)
  t.host_says_finger(Some(false))
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() {
        @ui.style(
          w=Fixed(100.0), h=Fixed(40.0), bg=Data(base),
          hovered=@ui.patch(bg=Data(hover)),
          focused=@ui.patch(bg=Data(focus)),
          pressed=@ui.patch(bg=Data(pressed)),
        )
      })
      v.focusable(Is(true)).on_press(fn() {  }).says(Is(Some(@view.said(Button, label="target")))) |> ignore
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(style_node_drawn(v).ground, base)
  t.move(10.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(v).ground, @ui.over(base, hover))
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(v).ground, @ui.over(@ui.over(base, hover), pressed))
  t.touch(2, 10.0, 10.0)
  t.move(180.0, 80.0)
  t.key(@ui.key_tab)
  assert_eq((t.focused().map(fn(s) { s.label }), style_node_drawn(v).ground), (Some("target"), focus))
  t.host_says_finger(Some(true))
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(v).ground, @ui.over(@ui.over(base, hover), pressed))
  t.touch(2, 10.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(v).ground, base)
}

///|
test "a node style follows caller-owned selected and disabled states in style order" {
  let selected = @signals.signal(false, same=fn(a, b) { a == b })
  let disabled = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() {
        @ui.style(
          w=Fixed(80.0), h=Fixed(32.0), bg=Data(0x111111FFL),
          selected=@ui.patch(bg=Data(0x222222FFL)),
          disabled=@ui.patch(bg=Data(0x333333FFL)),
        )
      }, selected=fn() { selected.get() }, disabled=fn() { disabled.get() })
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(style_node_drawn(v).ground, 0x111111FFL)
  selected.set(true)
  t.draw()
  assert_eq(style_node_drawn(v).ground, 0x222222FFL)
  disabled.set(true)
  t.draw()
  assert_eq(style_node_drawn(v).ground, 0x333333FFL)
  disabled.set(false)
  t.draw()
  assert_eq(style_node_drawn(v).ground, 0x222222FFL)
}

///|
test "a node style reads its dynamic look once per change, sharing one binding across its properties" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let reads = Ref(0)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      style_node(v, fn() {
        reads.val += 1
        if on.get() { @ui.style(w=Fixed(80.0), h=Fixed(32.0), bg=Data(0x222222FFL), radius=Md) }
        else { @ui.style(w=Fixed(60.0), h=Fixed(24.0), bg=Data(0x111111FFL)) }
      })
    })
    |> ignore
  })
  t.draw()
  let held = @ui.view_tree().unwrap().bindings_held()
  let before = reads.val
  on.set(true)
  t.draw()
  assert_eq((reads.val - before, @ui.view_tree().unwrap().bindings_held()), (1, held))
}

///|
test "a node style switches a column's height between fixed and growing" {
  let growing = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=120.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() { @ui.style(w=Fixed(40.0), h=if growing.get() { Grow(1.0) } else { Fixed(32.0) }) })
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(v.laid_size(), (40.0, 32.0))
  growing.set(true)
  t.draw()
  assert_eq(v.laid_size(), (40.0, 120.0))
  growing.set(false)
  t.draw()
  assert_eq(v.laid_size(), (40.0, 32.0))
}

///|
test "a node style leaves existing painted properties in their original order" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let order : Array[String] = []
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(80.0))).height(Is(Some(32.0))) |> ignore
      v.ground(Painted(fn(_) { order.push("ground"); 0x112233FFL })) |> ignore
      v.radius(Painted(fn(_) { order.push("radius"); 3.0 })) |> ignore
      style_node(v, fn() { if on.get() { @ui.style(bg=Data(0xAABBCCFFL)) } else { @ui.style() } })
    })
    |> ignore
  })
  t.draw()
  on.set(true)
  t.draw()
  order.clear()
  on.set(false)
  t.draw()
  assert_eq(order, ["ground", "radius"])
}

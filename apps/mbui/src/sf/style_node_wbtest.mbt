// A style on a retained node can change which properties it says. The node, its focus and any properties the style
// does not say stay as they were; later explicit properties belong to the caller.

///|
fn style_node_drawn(v : @view.View) -> @view.Drawn {
  @ui.view_tree().unwrap().drawn_of(v.id()).unwrap()
}

///|
/// The old box's drawn corner for a filled card inset equally on every side.
fn style_old_inner(inset : Double, outer : Double, radius : @ui.Radius) -> (Double, (Double, Double, Double, Double)) {
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Px(200.0), h=Px(120.0), pad=inset, radius=outer, bg=0x333333FFL, fn() {
      c.box(style=@ui.style(w=Full, h=Full, radius~, bg=Data(0xEEEEEEFFL)), name="inner sample", fn() {  }) |> ignore
    }) |> ignore
  }, w=300.0, h=200.0, corners_held=false)
  t.draw()
  let b = t.boxes().filter(fn(b) { b.name == "inner sample" })[0]
  (b.radius, b.radii)
}

///|
/// The old box's drawn corner around a small mark in its top left.
fn style_old_around(inset : Double, mark_radius : Double) -> Double {
  let t = @ui.Tester::new(fn(c) {
    c.box(style=@ui.style(radius=Around), w=Px(100.0), h=Px(100.0), pad=inset, bg=0x333333FFL, clip=true, name="around sample", fn() {
      c.box(w=Px(20.0), h=Px(20.0), radius=mark_radius, bg=0xEEEEEEFFL, fn() {  }) |> ignore
    }) |> ignore
  }, w=200.0, h=200.0, corners_held=false)
  t.draw()
  t.boxes().filter(fn(b) { b.name == "around sample" })[0].radius
}

///|
/// The old box's inner corner in a card's corner or in the middle of the same card.
fn style_old_moving_inner(center : Bool) -> Double {
  let t = @ui.Tester::new(fn(c) {
    c.box(
      w=Px(200.0), h=Px(120.0), pad=6.0, radius=20.0, bg=0x333333FFL,
      align=if center { ACenter } else { AStart }, justify=if center { JCenter } else { JStart },
      fn() {
        c.box(style=@ui.style(w=Fixed(40.0), h=Fixed(40.0), radius=Inner), name="moving inner", fn() {  }) |> ignore
      },
    ) |> ignore
  }, w=300.0, h=200.0, corners_held=false)
  t.draw()
  t.boxes().filter(fn(b) { b.name == "moving inner" })[0].radius
}

///|
fn style_drawn_corners(v : @view.View) -> (Double, (Double, Double, Double, Double)) {
  let d = style_node_drawn(v)
  (d.radius, d.corners.unwrap_or((d.radius, d.radius, d.radius, d.radius)))
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
test "a node style restores the latest width read during its holder's layout" {
  let holder_width = @signals.signal(200.0)
  let styled = @signals.signal(false)
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=500.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(holder) {
      holder.width(By(fn() { Some(holder_width.get()) })).height(Is(Some(40.0))) |> ignore
      holder.box(fn(v) {
        made.val = Some(v)
        v.width(Roomed(holder, fn(w, _) { Some(w / 2.0) })).height(Is(Some(20.0))) |> ignore
        style_node(v, fn() { if styled.get() { @ui.style(w=Fixed(80.0)) } else { @ui.style() } })
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(v.laid_size().0, 100.0)
  styled.set(true)
  t.draw()
  assert_eq(v.laid_size().0, 80.0)
  holder_width.set(300.0)
  t.draw()
  assert_eq(v.laid_size().0, 80.0)
  styled.set(false)
  t.draw()
  assert_eq(v.laid_size().0, 150.0)
}

///|
test "an explicit row width replaces the style's grow and basis as well as its width" {
  let growing = @signals.signal(true, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() { @ui.style(w=if growing.get() { Grow(1.0) } else { Fixed(80.0) }, h=Fixed(30.0)) }, in_row=true)
      v.width(Is(Some(60.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(v.laid_size(), (60.0, 30.0))
  growing.set(false)
  t.draw()
  assert_eq(v.laid_size(), (60.0, 30.0))
  growing.set(true)
  t.draw()
  assert_eq(v.laid_size(), (60.0, 30.0))
}

///|
test "an explicit cross-axis size leaves a style's main-axis grow in place" {
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=120.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() { @ui.style(w=Fixed(80.0), h=Grow(1.0)) })
      v.width(Is(Some(40.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(v.laid_size(), (40.0, 120.0))
  v.height(Is(Some(30.0))) |> ignore
  t.draw()
  assert_eq(v.laid_size(), (40.0, 30.0))
}

///|
test "a styled cut width gives way along a row and restores the node's own shrink binding" {
  let mode = @signals.signal(0, same=fn(a, b) { a == b })
  let row = @signals.signal(true, same=fn(a, b) { a == b })
  let own_cut = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(parent) {
      parent.width(Is(Some(100.0))).height(Is(Some(60.0))).row(By(fn() { row.get() }))
      .lines_up(Is(Some(Start))) |> ignore
      parent.box(fn(v) {
        made.val = Some(v)
        v.width(Is(Some(140.0))).height(Is(Some(36.0))).min_width(Is(Some(0.0)))
        .cuts(By(fn() { own_cut.get() })) |> ignore
        style_node(v, fn() {
          match mode.get() {
            0 => @ui.style(w=Cut)
            1 => @ui.style(w=Fixed(140.0))
            _ => @ui.style()
          }
        }, in_row=true)
        v.box(fn(content) { content.width(Is(Some(140.0))).height(Is(Some(36.0))) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let id = v.id()
  assert_eq(v.laid_size().0, 100.0)
  row.set(false)
  t.draw()
  assert_eq(v.laid_size().0, 140.0)
  row.set(true)
  mode.set(1)
  t.draw()
  assert_eq(v.laid_size().0, 140.0)
  own_cut.set(true)
  t.draw()
  assert_eq(v.laid_size().0, 100.0)
  own_cut.set(false)
  mode.set(2)
  t.draw()
  assert_eq(v.laid_size().0, 140.0)
  own_cut.set(true)
  t.draw()
  assert_eq((v.laid_size().0, v.id()), (100.0, id))
  assert_true(own_cut.watched())
}

///|
test "a later width or cuts setter replaces the styled cut behavior" {
  let mode = @signals.signal(true, same=fn(a, b) { a == b })
  let nodes : Array[@view.View] = []
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=150.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    for which in 0..<2 {
      root.box(fn(parent) {
        parent.width(Is(Some(100.0))).height(Is(Some(40.0))).row(Is(true)) |> ignore
        parent.box(fn(v) {
          nodes.push(v)
          v.min_width(Is(Some(0.0))) |> ignore
          style_node(v, fn() { @ui.style(w=if mode.get() { Cut } else { Fixed(140.0) }, h=Fixed(36.0)) }, in_row=true)
          if which == 0 { v.width(Is(Some(80.0))) |> ignore } else { v.cuts(Is(false)) |> ignore }
          v.box(fn(content) { content.width(Is(Some(140.0))).height(Is(Some(36.0))) |> ignore }) |> ignore
        }) |> ignore
      }) |> ignore
    }
  })
  t.draw()
  assert_eq((nodes[0].laid_size().0, nodes[1].laid_size().0), (80.0, 140.0))
  mode.set(false)
  t.draw()
  mode.set(true)
  t.draw()
  assert_eq((nodes[0].laid_size().0, nodes[1].laid_size().0), (80.0, 140.0))
}

///|
test "a style overlays border width and colour separately over the node's live edge" {
  let mode = @signals.signal(0, same=fn(a, b) { a == b })
  let own = @signals.signal((1.0, 0x112233FFL), same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      made.val = Some(v)
      v.edge(By(fn() { own.get() })) |> ignore
      style_node(v, fn() {
        match mode.get() {
          0 => @ui.style(border_color=Data(0xAABBCCFFL))
          1 => @ui.style(border=B4)
          2 => @ui.style(border=B2, border_color=Data(0xDDEEFFFFL))
          _ => @ui.style()
        }
      })
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(style_node_drawn(v).edge, (1.0, 0xAABBCCFFL))
  own.set((3.0, 0x334455FFL))
  t.draw()
  assert_eq(style_node_drawn(v).edge, (3.0, 0xAABBCCFFL))
  mode.set(1)
  t.draw()
  assert_eq(style_node_drawn(v).edge, (4.0, 0x334455FFL))
  mode.set(2)
  own.set((5.0, 0x556677FFL))
  t.draw()
  assert_eq(style_node_drawn(v).edge, (2.0, 0xDDEEFFFFL))
  mode.set(3)
  t.draw()
  assert_eq(style_node_drawn(v).edge, (5.0, 0x556677FFL))
  v.edge(Is((6.0, 0x778899FFL))) |> ignore
  mode.set(2)
  t.draw()
  assert_eq(style_node_drawn(v).edge, (6.0, 0x778899FFL))
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
test "linked styled corners follow the tree's window and theme and release their sources" {
  let fit : @signals.Signal[@ui.CornerFit?] = @signals.signal(None, same=fn(a, b) { a == b })
  let linked = @signals.signal(0, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let edge : @ui.CornerOf = Follow(Window, 6.0, 16.0)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0, window_corner=8.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(fn() { { ..@ui.Theme::light(), corner_fit: fit.get() } })
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() {
        @ui.style(
          w=Fixed(100.0), h=Fixed(60.0), bg=Data(0xFFFFFFFFL),
          radius=match linked.get() {
            0 => LinkedEach(edge, Own(28.0), Own(28.0), edge)
            1 => Linked(edge)
            _ => Exact(3.0)
          },
        )
      })
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let tree = @ui.view_tree().unwrap()
  let id = v.id()
  assert_eq(style_node_drawn(v).corners, Some((2.0, 28.0, 28.0, 2.0)))
  assert_true(tree.style_corner_links(id) is Some(Some(_)))
  fit.set(Some({ least: 6.0, most: 40.0, near: 0.0, far: 20.0 }))
  t.draw()
  assert_eq(style_node_drawn(v).corners, Some((16.0, 28.0, 28.0, 16.0)))
  linked.set(1)
  t.draw()
  assert_eq((style_node_drawn(v).radius, style_node_drawn(v).corners), (16.0, None))
  assert_true(tree.style_corner_links(id) is Some(Some(_)))
  linked.set(2)
  t.draw()
  assert_eq((style_node_drawn(v).radius, style_node_drawn(v).corners), (3.0, None))
  assert_true(tree.style_corner_links(id) is Some(None))
  linked.set(0)
  t.draw()
  v.radius(Is(4.0)) |> ignore
  t.draw()
  assert_eq((style_node_drawn(v).radius, style_node_drawn(v).corners), (4.0, None))
  assert_true(tree.style_corner_links(id) is None)
  assert_eq(v.id(), id)
}

///|
test "inner styled corners follow nested layout and switch to and from an exact radius" {
  let old_initial = style_old_inner(6.0, 20.0, InnerOr(Exact(6.0)))
  let old_inset = style_old_inner(8.0, 20.0, InnerOr(Exact(6.0)))
  let old_outer = style_old_inner(8.0, 24.0, InnerOr(Exact(6.0)))
  let inset = @signals.signal(6.0, same=fn(a, b) { a == b })
  let outer = @signals.signal(20.0, same=fn(a, b) { a == b })
  let inner = @signals.signal(true, same=fn(a, b) { a == b })
  let fit : @signals.Signal[@ui.CornerFit?] = @signals.signal(None, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=200.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(fn() { { ..@ui.Theme::light(), corner_fit: fit.get() } })
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      card.width(Is(Some(200.0))).height(Is(Some(120.0))).pad(By(fn() { inset.get() }))
      .radius(By(fn() { outer.get() })).ground(Is(0x333333FFL)).clips(Is(true)) |> ignore
      // The wrapper has no ground or corner; the rounded card is still the target's container.
      card.box(fn(wrapper) {
        wrapper.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
        wrapper.box(fn(v) {
          made.val = Some(v)
          style_node(v, fn() {
            @ui.style(w=Full, h=Full, bg=Data(0xEEEEEEFFL), radius=if inner.get() { InnerOr(Exact(6.0)) } else { Exact(6.0) })
          })
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let id = v.id()
  assert_eq(style_drawn_corners(v), old_initial)
  inset.set(8.0)
  t.draw()
  assert_eq(style_drawn_corners(v), old_inset)
  outer.set(24.0)
  t.draw()
  assert_eq(style_drawn_corners(v), old_outer)
  inner.set(false)
  t.draw()
  assert_eq(style_drawn_corners(v), (6.0, (6.0, 6.0, 6.0, 6.0)))
  inner.set(true)
  t.draw()
  assert_eq((style_drawn_corners(v), v.id()), (old_outer, id))
  fit.set(Some({ least: 20.0, most: 40.0, near: 0.0, far: 20.0 }))
  t.draw()
  assert_eq(style_drawn_corners(v), (6.0, (6.0, 6.0, 6.0, 6.0)))
  fit.set(None)
  t.draw()
  assert_eq(style_drawn_corners(v), old_outer)
}

///|
test "an inner styled corner follows each system window corner even when their maximum stays the same" {
  let window = FixedArray::from_array([20.0, 20.0, 20.0, 20.0])
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=120.0, window_corners=window, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.pad(Is(6.0)) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      style_node(v, fn() { @ui.style(w=Full, h=Full, bg=Data(0xEEEEEEFFL), radius=Inner) })
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let id = v.id()
  assert_eq(style_drawn_corners(v), (14.0, (14.0, 14.0, 14.0, 14.0)))
  window[1] = 16.0
  window[2] = 16.0
  t.draw()
  assert_eq((style_drawn_corners(v), v.id()), ((14.0, (14.0, 10.0, 10.0, 14.0)), id))
}

///|
test "a styled inner corner reports an impossible container and clears the fault when replaced" {
  let inner = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=120.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      style_node(v, fn() {
        @ui.style(w=Fixed(50.0), h=Fixed(30.0), radius=if inner.get() { Inner } else { Exact(4.0) })
      })
    }) |> ignore
  })
  t.draw()
  assert_true(t.corner_faults().iter().any(fn(f) { f.contains("in no rounded container") }))
  inner.set(false)
  t.draw()
  assert_true(!t.corner_faults().iter().any(fn(f) { f.contains("in no rounded container") }))
  inner.set(true)
  t.draw()
  assert_true(t.corner_faults().iter().any(fn(f) { f.contains("in no rounded container") }))
}

///|
test "an inner styled corner follows the same node when its position changes without resizing" {
  let old_corner = style_old_moving_inner(false)
  let old_middle = style_old_moving_inner(true)
  assert_true(old_corner != old_middle)
  let center = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=200.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      card.width(Is(Some(200.0))).height(Is(Some(120.0))).pad(Is(6.0)).radius(Is(20.0))
      .ground(Is(0x333333FFL))
      .lines_up(By(fn() { Some(if center.get() { Middle } else { Start }) }))
      .lies_along(By(fn() { if center.get() { Middle } else { Start } })) |> ignore
      card.box(fn(v) {
        made.val = Some(v)
        style_node(v, fn() { @ui.style(w=Fixed(40.0), h=Fixed(40.0), radius=Inner) })
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  let id = v.id()
  assert_eq((v.laid_size(), style_node_drawn(v).radius), ((40.0, 40.0), old_corner))
  center.set(true)
  t.draw()
  assert_eq((v.laid_size(), style_node_drawn(v).radius, v.id()), ((40.0, 40.0), old_middle, id))
  center.set(false)
  t.draw()
  assert_eq((style_node_drawn(v).radius, v.id()), (old_corner, id))
}

///|
test "a transparent rounded row becomes an inner corner's container when it starts taking presses" {
  let row : Ref[@view.View?] = Ref(None)
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=200.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      row.val = Some(card)
      card.width(Is(Some(200.0))).height(Is(Some(80.0))).pad(Is(6.0)).radius(Is(20.0)) |> ignore
      card.box(fn(v) {
        made.val = Some(v)
        style_node(v, fn() { @ui.style(w=Full, h=Full, radius=Inner) })
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(style_node_drawn(v).radius, 0.0)
  row.val.unwrap().on_press(fn() {  }) |> ignore
  t.draw()
  assert_eq(style_node_drawn(v).radius, @ui.concentric(20.0, 6.0))
}

///|
test "an unpressed tall inner row and its avatar follow the old corner rule" {
  let old = @ui.Tester::new(fn(c) {
    c.with_theme(ui_theme(), fn() {
      c.box(w=Px(220.0), h=Px(180.0), pad=8.0, radius=26.0, bg=0x333333FFL, clip=true, fn() {
        c.box(style=@ui.style(radius=Inner), w=Fill(1.0), h=Fill(1.0), dir=Row, pad=16.0, fn() {
          avatar(c, "alexandra@example.org", "Alexandra Chen", "", 46.0)
        }) |> ignore
      }) |> ignore
    })
  }, w=320.0, h=220.0, corners_held=false)
  old.draw()
  let old_faults = old.corner_faults()
  assert_eq(old_faults, [])
  let inner = @signals.signal(false)
  let t = @ui.Tester::new(fn(_) {  }, w=320.0, h=220.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      card.width(Is(Some(220.0))).height(Is(Some(180.0))).pad(Is(8.0))
      .radius(Is(26.0)).ground(Is(0x333333FFL)).clips(Is(true)) |> ignore
      card.box(fn(row) {
        row.row(Is(true)).height(Is(Some(164.0))).pad(Is(16.0)) |> ignore
        style_node(row, fn() { @ui.style(radius=if inner.get() { Inner } else { Exact(18.0) }) })
        avatar_node(row, fn() { "alexandra@example.org" }, fn() { "Alexandra Chen" }, fn() { "" }, 46.0)
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  inner.set(true)
  t.draw()
  assert_eq(t.corner_faults(), old_faults)
}

///|
test "a tall account card and avatar have the same corner check in old and retained trees" {
  let old = @ui.Tester::new(fn(c) {
    c.with_theme(ui_theme(), fn() {
      c.box(w=Px(256.0), h=Px(277.0), pad=16.0, radius=42.0, bg=0x777777FFL, fn() {
        c.box(w=Px(224.0), h=Px(245.0), pad=8.0, radius=26.0, bg=0x333333FFL, clip=true, fn() {
          c.box(style=@ui.style(radius=Inner), w=Fill(1.0), h=Fill(1.0), dir=Row, pad=16.0, fn() {
            avatar(c, "alexandra@example.org", "Alexandra Chen", "", 46.0)
          }) |> ignore
        }) |> ignore
      }) |> ignore
    })
  }, w=320.0, h=320.0, corners_held=false)
  old.draw()
  let old_faults = old.corner_faults()
  assert_eq(old_faults, [])
  let row_pad = @signals.signal(16.0)
  let t = @ui.Tester::new(fn(_) {  }, w=320.0, h=320.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(panel) {
      panel.width(Is(Some(256.0))).height(Is(Some(277.0))).pad(Is(16.0))
      .radius(Is(42.0)).ground(Is(0x777777FFL)) |> ignore
      panel.box(fn(card) {
        card.width(Is(Some(224.0))).height(Is(Some(245.0))).pad(Is(8.0))
        .radius(Is(26.0)).ground(Is(0x333333FFL)).clips(Is(true)) |> ignore
        card.box(fn(row) {
          row.row(Is(true)).height(Is(Some(229.0))).pad(By(fn() { row_pad.get() })) |> ignore
          style_node(row, fn() { @ui.style(radius=Inner) })
          avatar_node(row, fn() { "alexandra@example.org" }, fn() { "Alexandra Chen" }, fn() { "" }, 46.0)
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let tree_faults = t.corner_faults()
  assert_eq(tree_faults, old_faults)
  row_pad.set(4.0)
  t.draw()
  let near_faults = t.corner_faults()
  assert_true(near_faults.iter().any(fn(f) { f.contains("too square for the circle") }), msg=near_faults.join("\n"))
}

///|
test "layout-derived corners are not recomputed for unrelated text ink changes" {
  let ink = @signals.signal(0x111111FFL, same=fn(a, b) { a == b })
  let ground = @signals.signal(0x333333FFL, same=fn(a, b) { a == b })
  let calls = Ref(0)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=120.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.box(fn(card) {
      card.width(Is(Some(100.0))).height(Is(Some(80.0))).pad(Is(6.0)).radius(Is(20.0))
      .ground(By(fn() { ground.get() })) |> ignore
      card.box(fn(v) {
        style_node(v, fn() { @ui.style(w=Full, h=Full, radius=Inner) })
        v.ink(By(fn() { ink.get() })) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  @ui.view_tree().unwrap().style_corners_by(fn(_) { calls.val += 1 })
  ink.set(0x222222FFL)
  t.draw()
  assert_eq(calls.val, 0)
  ground.set(0x444444FFL)
  t.draw()
  assert_eq(calls.val, 0)
  ground.set(0L)
  t.draw()
  assert_eq(calls.val, 1)
}

///|
test "an around styled corner follows its contents and keeps clipping on the same node" {
  let old_initial = style_old_around(6.0, 10.0)
  let old_inset = style_old_around(10.0, 10.0)
  let old_mark = style_old_around(10.0, 8.0)
  let inset = @signals.signal(6.0, same=fn(a, b) { a == b })
  let mark_radius = @signals.signal(10.0, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=200.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      made.val = Some(card)
      card.pad(By(fn() { inset.get() })) |> ignore
      style_node(card, fn() { @ui.style(w=Fixed(100.0), h=Fixed(100.0), bg=Data(0x333333FFL), radius=Around, clip=true) })
      card.box(fn(mark) {
        mark.width(Is(Some(20.0))).height(Is(Some(20.0))).radius(By(fn() { mark_radius.get() })).ground(Is(0xEEEEEEFFL)) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let card = made.val.unwrap()
  let id = card.id()
  assert_eq((style_node_drawn(card).radius, style_node_drawn(card).clips), (old_initial, true))
  inset.set(10.0)
  t.draw()
  assert_eq(style_node_drawn(card).radius, old_inset)
  mark_radius.set(8.0)
  t.draw()
  assert_eq((style_node_drawn(card).radius, card.id()), (old_mark, id))
}

///|
test "an around styled corner follows a hosted old view's contents" {
  let expected = style_old_around(6.0, 10.0)
  let changed = style_old_around(6.0, 8.0)
  let mark_radius = @signals.signal(10.0)
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=200.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      made.val = Some(card)
      card.pad(Is(6.0)) |> ignore
      style_node(card, fn() { @ui.style(w=Fixed(100.0), h=Fixed(100.0), bg=Data(0x333333FFL), radius=Around, clip=true) })
      @ui.old(card, fn(c) {
        c.box(w=Px(20.0), h=Px(20.0), radius=mark_radius.get(), bg=0xEEEEEEFFL, fn() {  }) |> ignore
      }).width(Is(Some(20.0))).height(Is(Some(20.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(style_node_drawn(made.val.unwrap()).radius, expected)
  mark_radius.set(8.0)
  t.draw()
  assert_eq(style_node_drawn(made.val.unwrap()).radius, changed)
}

///|
test "an inner styled corner uses its tree theme when it hosts an old view" {
  let no_fit = style_old_inner(8.0, 24.0, InnerOr(Exact(6.0)))
  let fit : @signals.Signal[@ui.CornerFit?] = @signals.signal(
    Some({ least: 20.0, most: 40.0, near: 0.0, far: 20.0 }),
  )
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=200.0, corners_held=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(fn() { { ..@ui.Theme::light(), corner_fit: fit.get() } })
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(card) {
      card.width(Is(Some(200.0))).height(Is(Some(120.0))).pad(Is(8.0))
      .radius(Is(24.0)).ground(Is(0x333333FFL)) |> ignore
      card.box(fn(v) {
        made.val = Some(v)
        style_node(v, fn() { @ui.style(w=Full, h=Full, radius=InnerOr(Exact(6.0))) })
        @ui.old(v, fn(c) { c.box(w=Px(4.0), h=Px(4.0), fn() {  }) |> ignore })
        .width(Is(Some(4.0))).height(Is(Some(4.0))) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(style_node_drawn(made.val.unwrap()).radius, 6.0)
  fit.set(None)
  t.draw()
  assert_eq(style_drawn_corners(made.val.unwrap()), no_fit)
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
test "hover styles include a mouse over a descendant and a finger pressed on the node itself" {
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=100.0, native=Mouse, pointing=Mouse, corners_held=false)
  t.host_says_finger(Some(false))
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(parent) {
      made.val = Some(parent)
      parent.lines_up(Is(Some(Start))) |> ignore
      style_node(parent, fn() {
        @ui.style(w=Fixed(120.0), h=Fixed(64.0), bg=DangerBg, hovered=@ui.patch(bg=Hover))
      })
      parent.on_press(fn() {  }) |> ignore
      parent.box(fn(child) {
        child.width(Is(Some(40.0))).height(Is(Some(40.0))).on_press(fn() {  }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let parent = made.val.unwrap()
  let theme = @ui.tree_theme()
  let base = theme.color(DangerBg)
  let lit = @ui.over(base, theme.color(Hover))
  assert_eq(style_node_drawn(parent).ground, base)
  t.move(10.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(parent).ground, lit)
  t.move(180.0, 80.0)
  t.host_says_finger(Some(true))
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(parent).ground, base)
  t.touch(2, 10.0, 10.0)
  t.touch(0, 100.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(parent).ground, lit)
  t.touch(2, 100.0, 10.0)
  t.draw()
  assert_eq(style_node_drawn(parent).ground, base)
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
test "a size-only node style does not follow unrelated theme or narrow changes" {
  let dark = @signals.signal(false, same=fn(a, b) { a == b })
  let light_theme = @ui.Theme::light()
  let dark_theme = @ui.Theme::dark()
  let reads = Ref(0)
  let t = @ui.Tester::new(fn(_) {  }, w=800.0, h=100.0)
  t.ctx().set_theme(light_theme, narrow=light_theme, narrow_below=500.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(fn() { if dark.get() { dark_theme } else { light_theme } })
    root.box(fn(v) {
      style_node(v, fn() {
        reads.val += 1
        @ui.style(w=Fixed(80.0), h=Fixed(32.0))
      })
    })
    |> ignore
  })
  t.draw()
  let before = reads.val
  dark.set(true)
  t.draw()
  t.resize(400.0, 100.0)
  assert_eq(reads.val, before)
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
test "a fixed styled size takes precedence over a node's own grow and restores it when omitted" {
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let grow = @signals.signal(1.0, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      made.val = Some(v)
      v.width(Is(Some(40.0))).height(Is(Some(30.0))).grow(By(fn() { grow.get() })).basis(Is(Some(40.0))) |> ignore
      style_node(v, fn() {
        match which.get() {
          1 => @ui.style(w=Fixed(80.0))
          2 => @ui.style(w=Grow(1.0))
          _ => @ui.style()
        }
      }, in_row=true)
    })
    |> ignore
  })
  t.draw()
  let v = made.val.unwrap()
  assert_eq(v.laid_size().0, 300.0)
  which.set(1)
  t.draw()
  assert_eq(v.laid_size().0, 80.0)
  which.set(2)
  t.draw()
  assert_eq(v.laid_size().0, 300.0)
  which.set(1)
  t.draw()
  assert_eq(v.laid_size().0, 80.0)
  grow.set(0.0)
  t.draw()
  assert_eq(v.laid_size().0, 80.0)
  which.set(0)
  t.draw()
  assert_eq(v.laid_size().0, 40.0)
  grow.set(1.0)
  t.draw()
  assert_eq(v.laid_size().0, 300.0)
  assert_true(grow.watched())
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
